import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import '../services/photo_service.dart';

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

  String? libraryPath;
  bool isConfigured = false;
  bool isLoading = false;
  bool showFavoritesOnly = false;
  String searchQuery = '';
  int _zoomLevel = 2;
  int get zoomLevel => _zoomLevel;
  final Map<String, double> _aspectRatios = {};
  Map<String, double> get aspectRatios => _aspectRatios;

  SortMode sortMode = SortMode();

  Future<void> initialize() async {
    await _config.load();
    libraryPath = _config.libraryPath;
    isConfigured = _config.isConfigured;
    _favoritePaths = await _database.getFavoritePaths();
    _notes = await _database.getAllNotes();
    if (isConfigured) {
      await rescan();
    }
    notifyListeners();
  }

  Future<void> setLibraryPath(String path) async {
    await _config.saveLibraryPath(path);
    libraryPath = path;
    isConfigured = _config.isConfigured;
    await rescan();
  }

  Future<void> rescan() async {
    final path = libraryPath;
    if (path == null || path.isEmpty || !Directory(path).existsSync()) {
      _photos = [];
      _albums = [];
      isConfigured = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final scanned = await Isolate.run(() => PhotoService.scanDirectory(path));
      for (final photo in scanned) {
        photo.isFavorite = _favoritePaths.contains(photo.path);
      }
      _photos = scanned;
      _albums = _buildAlbums();
      isConfigured = true;
    } finally {
      isLoading = false;
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
    notifyListeners();
  }

  void toggleFavoritesOnly(bool value) {
    showFavoritesOnly = value;
    notifyListeners();
  }

  void setZoom(int level) {
    _zoomLevel = level.clamp(0, 3);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
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
    final source = showFavoritesOnly ? favorites : _photos;
    final list = _applySort(_applySearch(source));
    if (list.isEmpty) return [];

    final groups = <String, List<PhotoItem>>{};
    for (final photo in list) {
      final key = _dateKey(photo.modifiedAt);
      groups.putIfAbsent(key, () => []).add(photo);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return entries
        .map((e) => (header: e.key, photos: e.value))
        .toList();
  }

  String _dateKey(DateTime dt) {
    switch (_zoomLevel) {
      case 0:
        return '${dt.year}';
      case 1:
        return '${dt.year}-${_pad(dt.month)}';
      default:
        return _formatDateHeader(dt);
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;

    final label = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
    if (diff == 0) return 'Today — $label';
    if (diff == 1) return 'Yesterday — $label';
    return label;
  }

  int columnsForZoom(double screenWidth) {
    int base;
    if (screenWidth > 1200) {
      base = 6;
    } else if (screenWidth > 800) {
      base = 5;
    } else if (screenWidth > 500) {
      base = 4;
    } else {
      base = 3;
    }

    switch (_zoomLevel) {
      case 0:
        return base + 2;
      case 1:
        return base + 1;
      case 2:
        return base;
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
      _photos.removeWhere((p) => p.path == photo.path);
      _albums = _buildAlbums();
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
        _photos.removeWhere((p) => p.path == photo.path);
      } catch (_) {}
    }
    _favoritePaths = await _database.getFavoritePaths();
    _albums = _buildAlbums();
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
      _albums = _buildAlbums();
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