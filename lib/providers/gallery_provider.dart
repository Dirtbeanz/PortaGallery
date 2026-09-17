import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import '../services/diagnostic_log_service.dart';
import '../services/photo_service.dart';
import '../services/thumbnail_service.dart';

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

  final Map<String, String> _thumbPaths = {};
  String? thumbPathOrNull(PhotoItem photo) => _thumbPaths[photo.path];
  final Set<String> _thumbPending = {};
  final Set<String> _thumbInFlight = {};
  bool _thumbing = false;
  Map<String, PhotoItem> _photoIndex = {};

  String? libraryPath;
  bool isConfigured = false;
  bool isLoading = false;
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
          photo.aspectRatio = getAspectRatio(old);
        } else if (old != null && getAspectRatio(old) != photo.aspectRatio) {
          ratiosChanged = true;
        }
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
      _exifTask = _exifTask.then((_) => _enrichExifDates(generation));
    } catch (_) {
    } finally {
      if (_isCurrent(generation)) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _enrichExifDates(int generation) async {
    if (!_isCurrent(generation)) return;
    try {
      final candidates = _photos
          .where((photo) =>
              !photo.isVideo &&
              photo.dateTaken == null &&
              {'.jpg', '.jpeg', '.jpe', '.jfif'}.contains(
                  p.extension(photo.path).toLowerCase()))
          .toList();
      const chunkSize = 200;
      for (var i = 0; i < candidates.length; i += chunkSize) {
        if (!_isCurrent(generation)) return;
        final chunk = candidates.sublist(
            i, i + chunkSize > candidates.length ? candidates.length : i + chunkSize);
        final result = await compute(PhotoService.readExifDatesBulk,
            chunk.map((photo) => photo.path).toList());
        if (!_isCurrent(generation)) return;
        var changed = false;
        for (final photo in chunk) {
          if (!identical(_photoIndex[photo.path], photo)) continue;
          final date = result[photo.path];
          if (date != null && photo.dateTaken != date) {
            photo.dateTaken = date;
            changed = true;
          }
        }
        if (changed) {
          _sectionsDirty = true;
          _visiblePhotosDirty = true;
          if (sortMode.field == SortField.dateTaken) notifyListeners();
        }
      }
    } catch (_) {}
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
              paths[entry.path] = candidate;
              ratios[entry.path] = dims.$1 / dims.$2;
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
    for (final photo in snapshot) {
      if (!identical(_photoIndex[photo.path], photo)) continue;
      final target = paths[photo.path];
      if (target == null || _thumbPaths.containsKey(photo.path)) continue;
      _thumbPaths[photo.path] = target;
      _thumbFailed.remove(photo.path);
      final ratio = ratios[photo.path];
      if (ratio != null) _setAspectRatio(photo, ratio);
    }
  }

  void _setAspectRatio(PhotoItem photo, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return;
    if (getAspectRatio(photo) != ratio) layoutVersion++;
    _aspectRatios[photo.path] = ratio;
    photo.aspectRatio = ratio;
  }

  void requestThumbnails(List<PhotoItem> photos) {
    if (_disposed || isLoading) return;
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
      while (!_disposed && !isLoading && _thumbPending.isNotEmpty) {
        final generation = _generation;
        final batch = <PhotoItem>[];
        while (batch.length < 3 && _thumbPending.isNotEmpty) {
          final path = _thumbPending.first;
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
    _zoomLevel = level.clamp(0, 4);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    notifyListeners();
  }

  double getAspectRatio(PhotoItem photo) {
    final cached = _aspectRatios[photo.path];
    if (cached != null) return cached;
    return photo.aspectRatio;
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
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _sectionLabel(String key) {
    final parts = key.split('-');
    if (parts.length == 2) {
      final month = int.tryParse(parts[1]);
      if (month != null && month >= 1 && month <= 12) {
        return '${_monthNames[month - 1]} ${parts[0]}';
      }
    }
    if (parts.length == 3) {
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (month != null && day != null && month >= 1 && month <= 12) {
        return '${_monthNames[month - 1]} $day, ${parts[0]}';
      }
    }
    return key;
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Target row height for the justified grid at each zoom level.
  /// Strictly increasing: zoom 0 = most zoomed out, 4 = most zoomed in.
  double rowHeightForZoom() {
    switch (_zoomLevel) {
      case 0:
        return 80;
      case 1:
        return 120;
      case 2:
        return 160;
      case 3:
        return 200;
      default:
        return 260;
    }
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

  Future<void> deletePhoto(PhotoItem photo) async {
    try {
      final file = File(photo.path);
      if (await file.exists()) {
        await file.delete();
      }
      if (_favoritePaths.contains(photo.path)) {
        await _database.removeFavorite(photo.path);
        _favoritePaths.remove(photo.path);
      }
      if (_notes.containsKey(photo.path)) {
        await _database.removeNotes(photo.path);
        _notes.remove(photo.path);
      }
      await _database.removeMissingPaths([photo.path]);
      _photos.removeWhere((p) => p.path == photo.path);
      _photoIndex.remove(photo.path);
      _albums = _buildAlbums();
      _sectionsDirty = true;
      _visiblePhotosDirty = true;
      _favoritesCache = null;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> deletePhotos(List<PhotoItem> photos) async {
    for (final photo in photos) {
      try {
        final file = File(photo.path);
        if (await file.exists()) {
          await file.delete();
        }
        if (_favoritePaths.contains(photo.path)) {
          await _database.removeFavorite(photo.path);
        }
        if (_notes.containsKey(photo.path)) {
          await _database.removeNotes(photo.path);
          _notes.remove(photo.path);
        }
        await _database.removeMissingPaths([photo.path]);
        _photos.removeWhere((p) => p.path == photo.path);
        _photoIndex.remove(photo.path);
      } catch (_) {}
    }
    _favoritePaths = await _database.getFavoritePaths();
    _albums = _buildAlbums();
    _sectionsDirty = true;
    _visiblePhotosDirty = true;
    _favoritesCache = null;
    await loadVirtualAlbums();
    notifyListeners();
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
        final target = p.join(targetDir, photo.name);
        var unique = target;
        var counter = 1;
        while (File(unique).existsSync() && unique != photo.path) {
          final ext = p.extension(photo.name);
          final base = p.basenameWithoutExtension(photo.name);
          unique = p.join(targetDir, '${base}_$counter$ext');
          counter++;
        }
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