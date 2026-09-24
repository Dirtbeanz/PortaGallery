import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../models/trash_item.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import '../services/diagnostic_log_service.dart';
import '../services/photo_service.dart';
import '../services/thumbnail_service.dart';
import '../utils/date_labels.dart';

class GalleryProvider extends ChangeNotifier {
  final ConfigService _config = ConfigService();
  final DatabaseService _database = DatabaseService();

  List<PhotoItem> _photos = [];
  List<PhotoItem> get photos => _photos;

  List<Album> _albums = [];
  List<Album> get albums => _albums;

  Set<String> _favoritePaths = {};
  List<PhotoItem>? _favoritesCache;
  List<PhotoItem> get favorites =>
      _favoritesCache ??= _photos.where((p) => _favoritePaths.contains(p.path)).toList();

  Map<String, PhotoNotes> _notes = {};
  PhotoNotes getNotes(String path) => _notes[path] ?? const PhotoNotes();

  Map<String, DateTime> _dateOverrides = {};
  Map<String, DateTime> get dateOverrides => _dateOverrides;

  Map<String, int> _rotationOverrides = {};
  int rotationOf(String path) => _rotationOverrides[path] ?? 0;

  List<TrashItem> _trashItems = [];
  List<TrashItem> get trashItems => _trashItems;
  int get trashCount => _trashItems.length;

  final Map<String, String> _thumbPaths = {};
  String? thumbPathOrNull(PhotoItem photo) => _thumbPaths[photo.path];
  final Set<String> _thumbPending = {};
  final Set<String> _thumbInFlight = {};
  bool _thumbing = false;
  Map<String, PhotoItem> _photoIndex = {};

  String? libraryPath;
  bool isConfigured = false;
  bool isLoading = false;
  bool isIndexing = false;
  bool showFavoritesOnly = false;
  String searchQuery = '';
  int _zoomLevel = 1;
  int get zoomLevel => _zoomLevel;
  final Map<String, double> _aspectRatios = {};
  Map<String, double> get aspectRatios => _aspectRatios;

  int layoutVersion = 0;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _scanTask = Future<void>.value();
  Future<void> _exifTask = Future<void>.value();
  final Set<String> _thumbFailed = {};

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _driveWatcher?.cancel();
    _thumbPending.clear();
    super.dispose();
  }

  List<PhotoItem>? _visiblePhotosCache;
  bool _visiblePhotosDirty = true;

  bool get showHiddenFolders => _config.showHiddenFolders;
  bool get isDriveMissing =>
      isConfigured &&
      libraryPath != null &&
      libraryPath!.isNotEmpty &&
      !Directory(libraryPath!).existsSync();

  Timer? _driveWatcher;
  bool _lastDrivePresent = true;

  SortMode sortMode = SortMode();

  Future<void> initialize() async {
    final generation = _generation;
    await _config.load();
    if (!_isCurrent(generation)) return;
    libraryPath = _config.libraryPath;
    isConfigured = _config.hasLibrary;
    _favoritePaths = await _database.getFavoritePaths();
    _notes = await _database.getAllNotes();
    _virtualAlbums = await _database.getVirtualAlbums();
    _dateOverrides = await _database.getDateOverrides();
    _rotationOverrides = await _database.getRotationOverrides();
    _trashItems = await _database.getTrashItems();
    if (!_isCurrent(generation)) return;
    if (isConfigured) {
      // Load cached photo list for instant UI, then rescan in background.
      final cached = await _database.loadPhotoCache();
      if (!_isCurrent(generation)) return;
      // Only trust cache rows that actually live under the current library
      // root — the cache is global, so stale rows from previous libraries
      // must not inflate the shown item count.
      final root = p.normalize(libraryPath!);
      final scoped = cached
          ?.where((photo) => p.isWithin(root, photo.path) ||
              p.equals(root, photo.path))
          .toList();
      if (scoped != null && scoped.isNotEmpty) {
        for (final photo in scoped) {
          photo.isFavorite = _favoritePaths.contains(photo.path);
          _applyDateOverride(photo);
        }
        _photos = scoped;
        _photoIndex = {for (final photo in scoped) photo.path: photo};
        _albums = _buildAlbums();
        _sectionsDirty = true;
        _visiblePhotosDirty = true;
        _favoritesCache = null;
        isConfigured = true;
        isLoading = true;
        DiagnosticLogService.instance.recordScanSummary(
          libraryPath: libraryPath!,
          scannedCount: scoped.length,
          cacheCount: cached?.length ?? 0,
          duplicateCount: cached!.length - scoped.length,
        );
        notifyListeners();
        // Load cached preview paths immediately so the grid fills in with
        // previews while the background rescan runs.
        unawaited(_loadExistingThumbnails(generation));
        // Fire-and-forget background rescan; it will notify when done.
        rescan();
      } else {
        await rescan();
      }
    }
    _startDriveWatcher();
    notifyListeners();
  }

  void _startDriveWatcher() {
    if (_disposed) return;
    _driveWatcher?.cancel();
    _driveWatcher = Timer.periodic(const Duration(seconds: 4), (_) async {
      final path = libraryPath;
      if (path == null || path.isEmpty) return;
      final present = Directory(path).existsSync();
      if (present != _lastDrivePresent) {
        _lastDrivePresent = present;
        if (present) {
          await rescan();
        } else {
          notifyListeners();
        }
      }
    });
  }

  Future<void> setLibraryPath(String path) async {
    await _config.saveLibraryPath(path);
    if (_disposed) return;
    libraryPath = path;
    isConfigured = _config.hasLibrary;
    await rescan();
  }

  Future<void> setShowHiddenFolders(bool value) async {
    await _config.saveShowHiddenFolders(value);
    notifyListeners();
    await rescan();
  }

  Future<void> rescan() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    final path = libraryPath;
    final showHidden = _config.showHiddenFolders;
    _thumbPending.clear();
    isLoading = true;
    notifyListeners();
    _scanTask = _scanTask.then((_) => _rescan(generation, path, showHidden));
    return _scanTask;
  }

  static Future<List<PhotoItem>> _scanPhotos(
      ({String path, bool showHidden}) request) {
    return PhotoService.scanDirectory(request.path,
        showHidden: request.showHidden);
  }

  static bool _sameFile(PhotoItem a, PhotoItem b) =>
      a.path == b.path &&
      a.sizeBytes == b.sizeBytes &&
      a.modifiedAt.millisecondsSinceEpoch == b.modifiedAt.millisecondsSinceEpoch;

  Future<void> _rescan(int generation, String? path, bool showHidden) async {
    if (!_isCurrent(generation)) return;
    try {
      if (path == null || path.isEmpty) {
        _photos = [];
        _photoIndex.clear();
        _albums = [];
        _thumbPaths.clear();
        _thumbFailed.clear();
        _aspectRatios.clear();
        _sectionsDirty = true;
        _visiblePhotosDirty = true;
        _favoritesCache = null;
        isConfigured = false;
        return;
      }

      // Drive not mounted: keep previous listing so the UI stays usable and
      // show a "waiting for drive" state instead of wiping the library.
      if (!Directory(path).existsSync()) {
        _lastDrivePresent = false;
        isConfigured = _config.hasLibrary;
        return;
      }
      _lastDrivePresent = true;
      final scanned = await compute(
          _scanPhotos, (path: path, showHidden: showHidden));
      if (!_isCurrent(generation)) return;

      final unchanged = <String>{};
      var ratiosChanged = false;
      for (final photo in scanned) {
        photo.isFavorite = _favoritePaths.contains(photo.path);
        final old = _photoIndex[photo.path];
        if (old != null && _sameFile(old, photo)) {
          unchanged.add(photo.path);
          photo.dateTaken = old.dateTaken;
          // Scanned images carry their real ratio from the file header.
          // Videos (and files whose header could not be read) keep the
          // ratio learned from their thumbnail.
          if (photo.isVideo || photo.aspectRatio == 1.0) {
            photo.aspectRatio = rawAspectRatio(old);
          }
        } else if (old != null && getAspectRatio(old) != photo.aspectRatio) {
          ratiosChanged = true;
        }
        _applyDateOverride(photo);
      }
      _thumbPaths.removeWhere((path, _) => !unchanged.contains(path));
      _thumbFailed.removeWhere((path) => !unchanged.contains(path));
      _aspectRatios.removeWhere((path, _) => !unchanged.contains(path));
      if (ratiosChanged) layoutVersion++;
      _photos = scanned;
      _photoIndex = {for (final photo in scanned) photo.path: photo};
      _albums = _buildAlbums();
      _sectionsDirty = true;
      _visiblePhotosDirty = true;
      _favoritesCache = null;
      isConfigured = true;
      DiagnosticLogService.instance.recordScanSummary(
        libraryPath: path,
        scannedCount: scanned.length,
        cacheCount: _photos.length,
        duplicateCount: 0,
      );
      // Persist scanned photos so next startup is instant.
      try {
        await _database.savePhotoCache(scanned);
      } catch (_) {}
      if (!_isCurrent(generation)) return;
      try {
        await _loadExistingThumbnails(generation);
      } catch (_) {}
      if (!_isCurrent(generation)) return;
      _exifTask = _exifTask.then((_) => _enrichHeaders(generation));
    } catch (_) {
    } finally {
      if (_isCurrent(generation)) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Reads EXIF dates and display dimensions in a single pass so each file
  /// header is read once instead of twice. This roughly halves first-load
  /// indexing traffic.
  Future<void> _enrichHeaders(int generation) async {
    if (!_isCurrent(generation)) return;
    try {
      final candidates = _photos
          .where((photo) =>
              !photo.isVideo &&
              !PhotoService.isRawPath(photo.path) &&
              (photo.dateTaken == null || photo.aspectRatio == 1.0))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (candidates.isEmpty) return;
      isIndexing = true;
      notifyListeners();
      const chunkSize = 500;
      for (var i = 0; i < candidates.length; i += chunkSize) {
        if (!_isCurrent(generation)) return;
        final chunk = candidates.sublist(
            i,
            i + chunkSize > candidates.length
                ? candidates.length
                : i + chunkSize);
        final result = await compute(PhotoService.readHeadersBatch,
            chunk.map((photo) => photo.path).toList());
        if (!_isCurrent(generation)) return;
        var ratiosChanged = false;
        var datesChanged = false;
        for (final (path, date, width, height) in result) {
          final photo = _photoIndex[path];
          if (photo == null || !identical(photo, _photoIndex[path])) continue;
          if (date != null && photo.dateTaken == null) {
            photo.dateTaken = date;
            datesChanged = true;
          }
          if (width != null && height != null && width > 0 && height > 0) {
            final ratio = width / height;
            if (ratio.isFinite && ratio > 0 && _setAspectRatio(photo, ratio)) {
              ratiosChanged = true;
            }
          }
        }
        if (datesChanged) {
          _sectionsDirty = true;
          _visiblePhotosDirty = true;
        }
        if (ratiosChanged || datesChanged) {
          notifyListeners();
        }
        await Future<void>.delayed(Duration.zero);
      }
      try {
        await _database.savePhotoCache(_photos);
      } catch (_) {}
    } catch (_) {
    } finally {
      if (isIndexing) {
        isIndexing = false;
        notifyListeners();
      }
    }
  }

  static Future<(Map<String, String>, Map<String, double>)> _readCachedThumbnails(
      ({String directory, List<({String path, String key})> entries}) request) async {
    final paths = <String, String>{};
    final ratios = <String, double>{};
    const batchSize = 24;
    final entries = request.entries;
    for (var i = 0; i < entries.length; i += batchSize) {
      final batch = entries.sublist(
          i, i + batchSize > entries.length ? entries.length : i + batchSize);
      await Future.wait(batch.map((entry) async {
        final candidate = p.join(request.directory, '${entry.key}.jpg');
        try {
          final stat = await File(candidate).stat();
          if (stat.type == FileSystemEntityType.file && stat.size > 0) {
            final dims = PhotoService.readDimensions(candidate);
            if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
              final thumbRatio = dims.$1 / dims.$2;
              // Older builds produced cropped, rotated, or squished
              // thumbnails. Compare each cached thumbnail against the
              // original's orientation-aware dimensions and regenerate any
              // that do not match its aspect ratio.
              final original = PhotoService.readDimensions(entry.path);
              if (original != null && original.$1 > 0 && original.$2 > 0) {
                final originalRatio = original.$1 / original.$2;
                final relative =
                    (thumbRatio - originalRatio).abs() / originalRatio;
                if (relative > 0.05) return;
              }
              // Rotations of 180°/flips keep the same aspect ratio, so they
              // cannot be detected from dimensions. Regenerate cached
              // thumbnails whose original carries one of those orientations.
              final orientation =
                  await PhotoService.readExifOrientation(entry.path);
              if (orientation == 2 ||
                  orientation == 3 ||
                  orientation == 4 ||
                  orientation == 5 ||
                  orientation == 7) {
                return;
              }
              paths[entry.path] = candidate;
              ratios[entry.path] = thumbRatio;
            }
          }
        } catch (_) {}
      }));
    }
    return (paths, ratios);
  }

  Future<void> _loadExistingThumbnails(int generation) async {
    final snapshot = List<PhotoItem>.of(_photos);
    final dir = await ThumbnailService.cacheDir();
    if (!_isCurrent(generation)) return;
    final entries = [
      for (final photo in snapshot)
        (path: photo.path, key: ThumbnailService.key(photo)),
    ];
    final (paths, ratios) = await compute(
        _readCachedThumbnails, (directory: dir.path, entries: entries));
    if (!_isCurrent(generation)) return;
    var changed = false;
    for (final photo in snapshot) {
      if (!identical(_photoIndex[photo.path], photo)) continue;
      final target = paths[photo.path];
      if (target == null || _thumbPaths.containsKey(photo.path)) continue;
      _thumbPaths[photo.path] = target;
      _thumbFailed.remove(photo.path);
      changed = true;
      final ratio = ratios[photo.path];
      if (ratio != null) _setAspectRatio(photo, ratio);
    }
    if (changed) notifyListeners();
  }

  bool _setAspectRatio(PhotoItem photo, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return false;
    if (rawAspectRatio(photo) == ratio) return false;
    layoutVersion++;
    _aspectRatios[photo.path] = ratio;
    photo.aspectRatio = ratio;
    return true;
  }

  void requestThumbnails(List<PhotoItem> photos) {
    if (_disposed) return;
    var added = false;
    for (final photo in photos) {
      final current = _photoIndex[photo.path];
      if (current == null || !_sameFile(current, photo)) continue;
      if (_thumbPaths.containsKey(photo.path)) continue;
      if (_thumbFailed.contains(photo.path)) continue;
      if (_thumbPending.contains(photo.path)) continue;
      if (_thumbInFlight.contains(photo.path)) continue;
      _thumbPending.add(photo.path);
      added = true;
    }
    if (added) _drainThumbQueue();
  }

  Future<void> _drainThumbQueue() async {
    if (_thumbing || _disposed) return;
    _thumbing = true;
    var changed = 0;
    try {
      while (!_disposed && _thumbPending.isNotEmpty) {
        final generation = _generation;
        final batch = <PhotoItem>[];
        // Process pending paths in sorted order so files in the same folder
        // are read together — much friendlier to spinning disks.
        final ordered = _thumbPending.toList()..sort();
        for (final path in ordered) {
          if (batch.length >= 3) break;
          _thumbPending.remove(path);
          final photo = _photoIndex[path];
          if (photo == null || _thumbPaths.containsKey(path) ||
              _thumbFailed.contains(path)) {
            continue;
          }
          _thumbInFlight.add(path);
          batch.add(photo);
        }
        await Future.wait(batch.map((photo) async {
          final path = photo.path;
          String? target;
          double? ratio;
          try {
            if (await ThumbnailService.generate(photo)) {
              final candidate = await ThumbnailService.expectedPath(photo);
              final dims = PhotoService.readDimensions(candidate);
              if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
                target = candidate;
                ratio = dims.$1 / dims.$2;
              }
            }
          } catch (_) {
          } finally {
            _thumbInFlight.remove(path);
          }
          if (!_isCurrent(generation) || !identical(_photoIndex[path], photo)) {
            return;
          }
          if (target == null) {
            _thumbFailed.add(path);
          } else {
            _thumbPaths[path] = target;
            if (ratio != null) _setAspectRatio(photo, ratio);
            changed++;
          }
        }));
        // Batch notifications to avoid re-laying out the grid on every thumbnail.
        if (changed >= 12) {
          notifyListeners();
          changed = 0;
        }
      }
    } finally {
      _thumbing = false;
      notifyListeners();
    }
  }

  List<Album> _buildAlbums() {
    final map = <String, List<PhotoItem>>{};
    for (final photo in _photos) {
      map.putIfAbsent(photo.album, () => []).add(photo);
    }

    final libPath = libraryPath;
    if (libPath != null) {
      try {
        for (final entity in Directory(libPath).listSync(followLinks: false)) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (!showHiddenFolders && name.startsWith('.')) continue;
            map.putIfAbsent(name, () => []);
          }
        }
      } catch (_) {}
    }

    final albums = <Album>[];
    for (final entry in map.entries) {
      final name = entry.key.isEmpty ? 'Photos' : entry.key;
      albums.add(Album(
        name: name,
        path: entry.key,
        coverPath: entry.value.isEmpty ? '' : entry.value.first.path,
        photoCount: entry.value.length,
      ));
    }

    albums.sort((a, b) => a.name.compareTo(b.name));
    return albums;
  }

  List<PhotoItem> getPhotosForAlbum(String albumPath) {
    if (albumPath.isEmpty) {
      return _photos.where((p) => p.album.isEmpty).toList();
    }
    return _photos.where((p) => p.album == albumPath).toList();
  }

  List<PhotoItem> get visiblePhotos {
    if (_visiblePhotosDirty || _visiblePhotosCache == null) {
      final source = showFavoritesOnly ? favorites : _photos;
      _visiblePhotosCache = _applySort(_applySearch(source));
      _visiblePhotosDirty = false;
    }
    return _visiblePhotosCache!;
  }

  List<PhotoItem> _applySearch(List<PhotoItem> input) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return input;
    return input.where((p) {
      if (p.name.toLowerCase().contains(query)) return true;
      final notes = _notes[p.path];
      if (notes == null) return false;
      if (notes.comment.toLowerCase().contains(query)) return true;
      return notes.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  List<PhotoItem> _applySort(List<PhotoItem> input) {
    final list = List<PhotoItem>.from(input);
    list.sort((a, b) {
      final compare = switch (sortMode.field) {
        SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortField.dateModified => a.modifiedAt.compareTo(b.modifiedAt),
        SortField.dateTaken =>
          (a.dateTaken ?? a.modifiedAt).compareTo(b.dateTaken ?? b.modifiedAt),
        SortField.size => a.sizeBytes.compareTo(b.sizeBytes),
      };
      return sortMode.order == SortOrder.ascending ? compare : -compare;
    });
    return list;
  }

  void setSort(SortField field, SortOrder order) {
    sortMode = SortMode(field: field, order: order);
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    notifyListeners();
  }

  void toggleFavoritesOnly(bool value) {
    showFavoritesOnly = value;
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    _favoritesCache = null;
    notifyListeners();
  }

  void setZoom(int level) {
    final clamped = level.clamp(0, 3);
    if (clamped == _zoomLevel) return;
    _zoomLevel = clamped;
    _sectionsDirty = true;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    notifyListeners();
  }

  double rawAspectRatio(PhotoItem photo) =>
      _aspectRatios[photo.path] ?? photo.aspectRatio;

  double getAspectRatio(PhotoItem photo) {
    final raw = rawAspectRatio(photo);
    final turns = rotationOf(photo.path);
    if ((turns == 1 || turns == 3) && raw > 0) return 1 / raw;
    return raw;
  }

  Future<void> setRotation(PhotoItem photo, int quarterTurns) async {
    final turns = quarterTurns % 4;
    if (turns == 0) {
      _rotationOverrides.remove(photo.path);
    } else {
      _rotationOverrides[photo.path] = turns;
    }
    await _database.setRotationOverride(photo.path, turns);
    layoutVersion++;
    _sectionsDirty = true;
    notifyListeners();
  }

  List<({String header, List<PhotoItem> photos})> get dateSections {
    if (_sectionsDirty || _sectionsCache == null) {
      _sectionsCache = buildDateSections(visiblePhotos);
      _sectionsDirty = false;
    }
    return _sectionsCache!;
  }

  List<({String header, List<PhotoItem> photos})>? _sectionsCache;
  bool _sectionsDirty = true;

  List<({String header, List<PhotoItem> photos})> buildDateSections(
      List<PhotoItem> list) {
    if (list.isEmpty) return [];

    final groups = <String, List<PhotoItem>>{};
    for (final photo in list) {
      final key = dateKey(sortMode.field == SortField.dateTaken
          ? photo.dateTaken ?? photo.modifiedAt
          : photo.modifiedAt);
      groups.putIfAbsent(key, () => []).add(photo);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => sortMode.order == SortOrder.ascending
          ? a.key.compareTo(b.key)
          : b.key.compareTo(a.key));

    return entries
        .map((e) => (header: _sectionLabel(e.key), photos: e.value))
        .toList();
  }

  String dateKey(DateTime dt) {
    if (_zoomLevel <= 0) return '${dt.year}';
    if (_zoomLevel == 1) return '${dt.year}-${_pad(dt.month)}';
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  String _sectionLabel(String key) {
    final parts = key.split('-');
    if (parts.length == 1) return parts[0];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return key;
    if (parts.length == 2) return monthYearLabel(year, month);
    final day = int.tryParse(parts[2]);
    if (day == null) return key;
    return daySectionLabel(year, month, day);
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Target row height for the justified grid at each zoom level.
  /// Strictly increasing: zoom 0 = most zoomed out, 3 = most zoomed in.
  /// Narrow (portrait phone) screens scale the rows down further so more
  /// photos fit per row.
  double rowHeightForZoom(double screenWidth) {
    final base = switch (_zoomLevel) {
      0 => 56.0,
      1 => 72.0,
      2 => 112.0,
      _ => 170.0,
    };
    if (screenWidth < 600) return base * 0.7;
    if (screenWidth < 900) return base * 0.85;
    return base;
  }

  Future<void> toggleFavorite(PhotoItem photo) async {
    final path = photo.path;
    if (_favoritePaths.contains(path)) {
      await _database.removeFavorite(path);
      _favoritePaths.remove(path);
      photo.isFavorite = false;
    } else {
      await _database.addFavorite(path);
      _favoritePaths.add(path);
      photo.isFavorite = true;
    }
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    _favoritesCache = null;
    notifyListeners();
  }

  Future<void> setFavorites(List<PhotoItem> photos, bool favorite) async {
    for (final photo in photos) {
      photo.isFavorite = favorite;
      if (favorite) {
        await _database.addFavorite(photo.path);
        _favoritePaths.add(photo.path);
      } else {
        await _database.removeFavorite(photo.path);
        _favoritePaths.remove(photo.path);
      }
    }
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    _favoritesCache = null;
    notifyListeners();
  }

  Future<void> saveNotes(String path, List<String> tags, String comment) async {
    final trimmedTags =
        tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final notes = PhotoNotes(tags: trimmedTags, comment: comment.trim());
    _notes[path] = notes;
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    await _database.saveNotes(path, trimmedTags, comment);
    notifyListeners();
  }

  Future<void> importPhotos(List<String> filePaths, {String? subFolder}) async {
    final path = libraryPath;
    if (path == null) return;

    var imported = 0;
    for (final file in filePaths) {
      if (!PhotoService.isSupported(file)) continue;
      try {
        await PhotoService.importFile(file, path, subFolder: subFolder);
        imported++;
      } catch (_) {
        continue;
      }
    }

    if (imported > 0) {
      await rescan();
    }
    notifyListeners();
  }

  Future<String?> exportPhoto(PhotoItem photo, String targetPath,
      {bool overwrite = true}) async {
    try {
      if (overwrite && File(targetPath).existsSync()) {
        await File(targetPath).delete();
      }
      await PhotoService.exportFile(photo.path, targetPath);
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  Future<int> exportPhotos(List<PhotoItem> photos) async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    if (dir == null) return 0;

    var count = 0;
    for (final photo in photos) {
      final target = p.join(dir.path, photo.name);
      if (await exportPhoto(photo, target, overwrite: true) != null) {
        count++;
      }
    }
    return count;
  }

  void _applyDateOverride(PhotoItem photo) {
    final override = _dateOverrides[photo.path];
    if (override != null) photo.dateTaken = override;
  }

  Future<void> setDateTaken(PhotoItem photo, DateTime? date) async {
    if (date == null) {
      _dateOverrides.remove(photo.path);
      final exif = await PhotoService.readExifDateQuick(photo.path);
      photo.dateTaken = exif;
    } else {
      _dateOverrides[photo.path] = date;
      photo.dateTaken = date;
    }
    await _database.setDateOverride(photo.path, date);
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    notifyListeners();
  }

  Future<void> deletePhoto(PhotoItem photo) => moveToTrash([photo]);

  Future<void> deletePhotos(List<PhotoItem> photos) => moveToTrash(photos);

  Directory? _trashDirectory() {
    final path = libraryPath;
    if (path == null || path.isEmpty) return null;
    return Directory(p.join(path, '.trash'));
  }

  Future<String?> _uniqueTrashPath(String name) async {
    final dir = _trashDirectory();
    if (dir == null) return null;
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var candidate = p.join(dir.path, '${stamp}_$name');
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir.path, '${stamp}_${counter}_$name');
      counter++;
    }
    return candidate;
  }

  Future<int> rebuildThumbnails() async {
    final removed = await ThumbnailService.clearCache();
    _thumbPaths.clear();
    _thumbFailed.clear();
    _thumbPending.clear();
    _thumbInFlight.clear();
    notifyListeners();
    return removed;
  }

  Future<int> moveToTrash(List<PhotoItem> photos) async {
    final dir = _trashDirectory();
    if (dir == null || photos.isEmpty) return 0;
    final items = <TrashItem>[];
    final moved = <String>[];
    for (final photo in photos) {
      try {
        final target = await _uniqueTrashPath(photo.name);
        if (target == null) continue;
        final file = File(photo.path);
        if (await file.exists()) {
          await file.rename(target);
        }
        items.add(TrashItem(
          trashedPath: target,
          originalPath: photo.path,
          deletedAt: DateTime.now(),
        ));
        moved.add(photo.path);
      } catch (_) {}
    }
    if (items.isEmpty) return 0;
    await _database.addTrashItems(items);
    _trashItems = await _database.getTrashItems();
    for (final path in moved) {
      _photos.removeWhere((photo) => photo.path == path);
      _photoIndex.remove(path);
      _thumbPaths.remove(path);
      _thumbFailed.remove(path);
    }
    _albums = _buildAlbums();
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    _favoritesCache = null;
    notifyListeners();
    return items.length;
  }

  Future<int> restoreTrash(List<TrashItem> items) async {
    var restored = 0;
    final done = <String>[];
    for (final item in items) {
      try {
        final source = File(item.trashedPath);
        if (!await source.exists()) continue;
        final targetDir = Directory(p.dirname(item.originalPath));
        if (!await targetDir.exists()) await targetDir.create(recursive: true);
        final target = PhotoService.uniqueTargetPath(
            targetDir.path, p.basename(item.originalPath));
        await source.rename(target);
        done.add(item.trashedPath);
        restored++;
      } catch (_) {}
    }
    if (done.isNotEmpty) {
      await _database.removeTrashItems(done);
      _trashItems = await _database.getTrashItems();
      await rescan();
    }
    return restored;
  }

  Future<int> emptyTrash() async {
    var deleted = 0;
    final done = <String>[];
    final originals = <String>[];
    for (final item in List<TrashItem>.of(_trashItems)) {
      try {
        final file = File(item.trashedPath);
        if (await file.exists()) await file.delete();
        done.add(item.trashedPath);
        originals.add(item.originalPath);
        deleted++;
      } catch (_) {}
    }
    if (done.isNotEmpty) {
      await _database.removeTrashItems(done);
      await _database.removeMissingPaths(originals);
      _trashItems = await _database.getTrashItems();
      _favoritePaths = await _database.getFavoritePaths();
      _notes = await _database.getAllNotes();
      for (final path in originals) {
        _dateOverrides.remove(path);
      }
      notifyListeners();
    }
    final dir = _trashDirectory();
    try {
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
    return deleted;
  }

  Future<bool> renameAlbum(String albumPath, String newName) async {
    final library = libraryPath;
    if (library == null || albumPath.isEmpty || newName.trim().isEmpty) {
      return false;
    }
    try {
      final source = Directory(p.join(library, albumPath));
      final target = Directory(p.join(library, newName.trim()));
      if (!await source.exists() || await target.exists()) return false;
      await source.rename(target.path);
      await rescan();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> dissolveAlbum(String albumPath) async {
    final library = libraryPath;
    if (library == null || albumPath.isEmpty) return 0;
    final dir = Directory(p.join(library, albumPath));
    var moved = 0;
    try {
      if (!await dir.exists()) return 0;
      final entries = await dir.list(followLinks: false).toList();
      for (final entry in entries) {
        if (entry is! File) continue;
        try {
          final target =
              PhotoService.uniqueTargetPath(library, p.basename(entry.path));
          await entry.rename(target);
          moved++;
        } catch (_) {}
      }
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      await rescan();
    } catch (_) {}
    return moved;
  }

  Future<int> deleteAlbum(String albumPath) async {
    final library = libraryPath;
    if (library == null || albumPath.isEmpty) return 0;
    final dir = Directory(p.join(library, albumPath));
    try {
      if (!await dir.exists()) return 0;
      final photos =
          _photos.where((photo) => photo.album == albumPath).toList();
      final moved = await moveToTrash(photos);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      await rescan();
      return moved;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> renamePhoto(PhotoItem photo, String newName) async {
    if (newName.trim().isEmpty) return false;
    final dir = p.dirname(photo.path);
    final ext = p.extension(photo.path);
    final target = p.join(dir, '${newName.trim()}$ext');
    if (target == photo.path) return true;

    try {
      final file = File(photo.path);
      if (await file.exists()) {
        await file.rename(target);
      }
      _photos.removeWhere((x) => x.path == photo.path);
      _photoIndex.remove(photo.path);
      _albums = _buildAlbums();
      _sectionsDirty = true;
      _visiblePhotosDirty = true;
      _favoritesCache = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createAlbum(String name) async {
    final path = libraryPath;
    if (path == null || name.trim().isEmpty) return false;
    try {
      final dir = Directory(p.join(path, name.trim()));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _virtualAlbums = [];

  List<Map<String, dynamic>> get virtualAlbums => _virtualAlbums;

  Future<void> loadVirtualAlbums() async {
    _virtualAlbums = await _database.getVirtualAlbums();
    notifyListeners();
  }

  Future<int> createVirtualAlbum(String name) async {
    if (name.trim().isEmpty) return -1;
    final id = await _database.createVirtualAlbum(name.trim());
    await loadVirtualAlbums();
    return id;
  }

  Future<void> renameVirtualAlbum(int id, String name) async {
    await _database.renameVirtualAlbum(id, name.trim());
    await loadVirtualAlbums();
  }

  Future<void> deleteVirtualAlbum(int id) async {
    await _database.deleteVirtualAlbum(id);
    await loadVirtualAlbums();
  }

  Future<void> addToVirtualAlbum(int albumId, List<PhotoItem> photos) async {
    await _database.addToVirtualAlbum(
        albumId, photos.map((p) => p.path).toList());
    await loadVirtualAlbums();
  }

  Future<void> removeFromVirtualAlbum(int albumId, List<PhotoItem> photos) async {
    await _database.removeFromVirtualAlbum(
        albumId, photos.map((p) => p.path).toList());
    await loadVirtualAlbums();
  }

  Future<Set<String>> getVirtualAlbumItems(int albumId) async {
    return _database.getVirtualAlbumItems(albumId);
  }

  Future<int> movePhotosToAlbum(List<PhotoItem> photos, String albumPath) async {
    final path = libraryPath;
    if (path == null) return 0;

    var moved = 0;
    for (final photo in photos) {
      final targetDir = p.join(path, albumPath);
      try {
        await Directory(targetDir).create(recursive: true);
        final unique = PhotoService.uniqueTargetPath(targetDir, photo.name,
            excludePath: photo.path);
        await File(photo.path).rename(unique);
        moved++;
      } catch (_) {}
    }

    if (moved > 0) {
      await rescan();
    }
    notifyListeners();
    return moved;
  }
}