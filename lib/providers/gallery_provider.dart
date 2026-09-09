import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
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
  List<PhotoItem> get favorites =>
      _photos.where((p) => _favoritePaths.contains(p.path)).toList();

  Map<String, PhotoNotes> _notes = {};
  PhotoNotes getNotes(String path) => _notes[path] ?? const PhotoNotes();

  Map<String, String> _thumbPaths = {};
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
  int _zoomLevel = 2;
  int get zoomLevel => _zoomLevel;
  final Map<String, double> _aspectRatios = {};
  Map<String, double> get aspectRatios => _aspectRatios;

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
    await _config.load();
    libraryPath = _config.libraryPath;
    // Consider the app "configured" as long as a library path is set; the
    // drive-missing banner handles the disconnected state.
    isConfigured = _config.hasLibrary;
    _favoritePaths = await _database.getFavoritePaths();
    _notes = await _database.getAllNotes();
    _virtualAlbums = await _database.getVirtualAlbums();
    if (isConfigured) {
      await rescan();
    }
    _startDriveWatcher();
    notifyListeners();
  }

  void _startDriveWatcher() {
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
    libraryPath = path;
    isConfigured = _config.hasLibrary;
    await rescan();
  }

  Future<void> setShowHiddenFolders(bool value) async {
    await _config.saveShowHiddenFolders(value);
    notifyListeners();
    await rescan();
  }

  Future<void> rescan() async {
    final path = libraryPath;
    if (path == null || path.isEmpty) {
      _photos = [];
      _albums = [];
      isConfigured = false;
      notifyListeners();
      return;
    }

    // Drive not mounted: keep previous listing so the UI stays usable and
    // show a "waiting for drive" state instead of wiping the library.
    if (!Directory(path).existsSync()) {
      _lastDrivePresent = false;
      isConfigured = _config.hasLibrary;
      isLoading = false;
      notifyListeners();
      return;
    }
    _lastDrivePresent = true;

    isLoading = true;
    notifyListeners();

    try {
      final showHidden = _config.showHiddenFolders;

      final scanned = await Isolate.run(
          () => PhotoService.scanDirectory(path, showHidden: showHidden));

      for (final photo in scanned) {
        photo.isFavorite = _favoritePaths.contains(photo.path);
      }
      _photos = scanned;
      _photoIndex = {for (final photo in scanned) photo.path: photo};
      _albums = _buildAlbums();
      _sectionsDirty = true;
      isConfigured = true;
      await _loadExistingThumbnails();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadExistingThumbnails() async {
    final dir = await ThumbnailService.cacheDir();
    final map = <String, String>{};
    var i = 0;
    for (final photo in _photos) {
      final candidate =
          p.join(dir.path, '${ThumbnailService.key(photo)}.jpg');
      if (File(candidate).existsSync()) {
        map[photo.path] = candidate;
        final dims = PhotoService.readDimensions(candidate);
        if (dims != null && dims.$2 > 0) {
          final ratio = dims.$1 / dims.$2;
          _aspectRatios[photo.path] = ratio;
          photo.aspectRatio = ratio;
        }
      }
      if (++i % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    _thumbPaths = map;
    _thumbPending.clear();
  }

  void requestThumbnails(List<PhotoItem> photos) {
    var added = false;
    for (final photo in photos) {
      if (_thumbPaths.containsKey(photo.path)) continue;
      if (_thumbPending.contains(photo.path)) continue;
      if (_thumbInFlight.contains(photo.path)) continue;
      _thumbPending.add(photo.path);
      added = true;
    }
    if (added) {
      _drainThumbQueue();
    }
  }

  Future<void> _drainThumbQueue() async {
    if (_thumbing) return;
    _thumbing = true;
    var changed = 0;
    try {
      while (_thumbPending.isNotEmpty) {
        final path = _thumbPending.first;
        _thumbPending.remove(path);
        final photo = _photoIndex[path];
        if (photo == null) continue;
        _thumbInFlight.add(path);
        try {
          final ok = await ThumbnailService.generate(photo);
          if (ok) {
            final target = await ThumbnailService.expectedPath(photo);
            if (await File(target).exists()) {
              _thumbPaths[path] = target;
              final dims = PhotoService.readDimensions(target);
              if (dims != null && dims.$2 > 0) {
                final ratio = dims.$1 / dims.$2;
                _aspectRatios[path] = ratio;
                photo.aspectRatio = ratio;
              }
              changed++;
              // Batch notifications to avoid re-laying out the grid on
              // every single thumbnail.
              if (changed % 12 == 0) {
                notifyListeners();
                changed = 0;
              }
            }
          }
        } finally {
          _thumbInFlight.remove(path);
        }
      }
    } finally {
      _thumbing = false;
      if (changed > 0) notifyListeners();
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
            if (name.startsWith('.')) continue;
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
    final source = showFavoritesOnly ? favorites : _photos;
    return _applySort(_applySearch(source));
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
        SortField.size => a.sizeBytes.compareTo(b.sizeBytes),
      };
      return sortMode.order == SortOrder.ascending ? compare : -compare;
    });
    return list;
  }

  void setSort(SortField field, SortOrder order) {
    sortMode = SortMode(field: field, order: order);
    _sectionsDirty = true;
    notifyListeners();
  }

  void toggleFavoritesOnly(bool value) {
    showFavoritesOnly = value;
    _sectionsDirty = true;
    notifyListeners();
  }

  void setZoom(int level) {
    _zoomLevel = level.clamp(0, 3);
    _sectionsDirty = true;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _sectionsDirty = true;
    notifyListeners();
  }

  double getAspectRatio(PhotoItem photo) {
    final cached = _aspectRatios[photo.path];
    if (cached != null) return cached;
    final ratio = PhotoService.readAspectRatio(photo.path);
    _aspectRatios[photo.path] = ratio;
    photo.aspectRatio = ratio;
    return ratio;
  }

  List<({String header, List<PhotoItem> photos})> get dateSections {
    if (_sectionsDirty || _sectionsCache == null) {
      final source = showFavoritesOnly ? favorites : _photos;
      _sectionsCache = buildDateSections(_applySort(_applySearch(source)));
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
      final key = dateKey(photo.modifiedAt);
      groups.putIfAbsent(key, () => []).add(photo);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return entries
        .map((e) => (header: _sectionLabel(e.key), photos: e.value))
        .toList();
  }

  String dateKey(DateTime dt) {
    switch (_zoomLevel) {
      case 0:
      case 1:
        return '${dt.year}-${_pad(dt.month)}';
      default:
        return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
    }
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

  int columnsForZoom(double screenWidth) {
    switch (_zoomLevel) {
      case 0:
        return 8;
      case 1:
        return 5;
      case 2:
        return 4;
      default:
        if (screenWidth > 600) return 3;
        return 2;
    }
  }

  bool get useSquareTiles => _zoomLevel < 3;

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
    notifyListeners();
  }

  Future<void> saveNotes(String path, List<String> tags, String comment) async {
    final trimmedTags =
        tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final notes = PhotoNotes(tags: trimmedTags, comment: comment.trim());
    _notes[path] = notes;
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