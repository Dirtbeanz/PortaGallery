import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../models/trash_item.dart';

class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'photo_gallery.db');

    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE favorites (
              path TEXT PRIMARY KEY,
              added_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE notes (
              path TEXT PRIMARY KEY,
              tags TEXT NOT NULL DEFAULT '',
              comment TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE virtual_albums (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE virtual_album_items (
              album_id INTEGER NOT NULL,
              path TEXT NOT NULL,
              PRIMARY KEY (album_id, path)
            )
          ''');
          await db.execute('''
            CREATE TABLE photo_cache (
              path TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              album TEXT NOT NULL,
              size_bytes INTEGER NOT NULL,
              modified_at INTEGER NOT NULL,
              is_video INTEGER NOT NULL,
              aspect_ratio REAL NOT NULL DEFAULT 1.0,
              date_taken INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE date_overrides (
              path TEXT PRIMARY KEY,
              date_taken INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE trash (
              trashed_path TEXT PRIMARY KEY,
              original_path TEXT NOT NULL,
              deleted_at INTEGER NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS notes (
                path TEXT PRIMARY KEY,
                tags TEXT NOT NULL DEFAULT '',
                comment TEXT NOT NULL DEFAULT ''
              )
            ''');
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS virtual_albums (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS virtual_album_items (
                album_id INTEGER NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (album_id, path)
              )
            ''');
          }
          if (oldVersion < 4) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS photo_cache (
                path TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                album TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                modified_at INTEGER NOT NULL,
                is_video INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 5) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS date_overrides (
                path TEXT PRIMARY KEY,
                date_taken INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS trash (
                trashed_path TEXT PRIMARY KEY,
                original_path TEXT NOT NULL,
                deleted_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 6) {
            await db.execute(
                'ALTER TABLE photo_cache ADD COLUMN aspect_ratio REAL NOT NULL DEFAULT 1.0');
            await db.execute(
                'ALTER TABLE photo_cache ADD COLUMN date_taken INTEGER');
          }
        },
      ),
    );
    return _db!;
  }

  Future<void> addFavorite(String path) async {
    final db = await database;
    await db.insert(
      'favorites',
      {'path': path, 'added_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String path) async {
    final db = await database;
    await db.delete('favorites', where: 'path = ?', whereArgs: [path]);
  }

  Future<Set<String>> getFavoritePaths() async {
    final db = await database;
    final rows = await db.query('favorites', columns: ['path']);
    return rows.map((r) => r['path'] as String).toSet();
  }

  Future<void> saveNotes(String path, List<String> tags, String comment) async {
    final db = await database;
    await db.insert(
      'notes',
      {
        'path': path,
        'tags': tags.join(','),
        'comment': comment.trim(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, PhotoNotes>> getAllNotes() async {
    final db = await database;
    final rows = await db.query('notes');
    final map = <String, PhotoNotes>{};
    for (final row in rows) {
      map[row['path'] as String] = PhotoNotes.fromMap(row);
    }
    return map;
  }

  Future<void> removeNotes(String path) async {
    final db = await database;
    await db.delete('notes', where: 'path = ?', whereArgs: [path]);
  }

  Future<int> createVirtualAlbum(String name) async {
    final db = await database;
    return db.insert('virtual_albums', {'name': name});
  }

  Future<void> renameVirtualAlbum(int id, String name) async {
    final db = await database;
    await db.update('virtual_albums', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteVirtualAlbum(int id) async {
    final db = await database;
    await db.delete('virtual_album_items',
        where: 'album_id = ?', whereArgs: [id]);
    await db.delete('virtual_albums', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToVirtualAlbum(int albumId, List<String> paths) async {
    final db = await database;
    final batch = db.batch();
    for (final path in paths) {
      batch.insert(
        'virtual_album_items',
        {'album_id': albumId, 'path': path},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeFromVirtualAlbum(int albumId, List<String> paths) async {
    final db = await database;
    final batch = db.batch();
    for (final path in paths) {
      batch.delete('virtual_album_items',
          where: 'album_id = ? AND path = ?', whereArgs: [albumId, path]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getVirtualAlbums() async {
    final db = await database;
    final rows = await db.query('virtual_albums');
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM virtual_album_items WHERE album_id = ?',
            [row['id']],
          )) ??
          0;
      result.add({
        'id': row['id'] as int,
        'name': row['name'] as String,
        'count': count,
      });
    }
    return result;
  }

  Future<Set<String>> getVirtualAlbumItems(int albumId) async {
    final db = await database;
    final rows = await db.query('virtual_album_items',
        columns: ['path'], where: 'album_id = ?', whereArgs: [albumId]);
    return rows.map((r) => r['path'] as String).toSet();
  }

  Future<void> removeMissingPaths(List<String> missingPaths) async {
    final db = await database;
    final batch = db.batch();
    for (final path in missingPaths) {
      batch.delete('favorites', where: 'path = ?', whereArgs: [path]);
      batch.delete('notes', where: 'path = ?', whereArgs: [path]);
      batch.delete('date_overrides', where: 'path = ?', whereArgs: [path]);
      batch.delete('virtual_album_items',
          where: 'path = ?', whereArgs: [path]);
      batch.delete('photo_cache', where: 'path = ?', whereArgs: [path]);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, DateTime>> getDateOverrides() async {
    final db = await database;
    final rows = await db.query('date_overrides');
    final map = <String, DateTime>{};
    for (final row in rows) {
      map[row['path'] as String] =
          DateTime.fromMillisecondsSinceEpoch(row['date_taken'] as int);
    }
    return map;
  }

  Future<void> setDateOverride(String path, DateTime? date) async {
    final db = await database;
    if (date == null) {
      await db.delete('date_overrides', where: 'path = ?', whereArgs: [path]);
      return;
    }
    await db.insert(
      'date_overrides',
      {'path': path, 'date_taken': date.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TrashItem>> getTrashItems() async {
    final db = await database;
    final rows = await db.query('trash', orderBy: 'deleted_at DESC');
    return rows.map(TrashItem.fromMap).toList();
  }

  Future<void> addTrashItems(List<TrashItem> items) async {
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'trash',
        {
          'trashed_path': item.trashedPath,
          'original_path': item.originalPath,
          'deleted_at': item.deletedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeTrashItems(List<String> trashedPaths) async {
    final db = await database;
    final batch = db.batch();
    for (final path in trashedPaths) {
      batch.delete('trash', where: 'trashed_path = ?', whereArgs: [path]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> savePhotoCache(List<PhotoItem> photos) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('photo_cache');
      final batch = txn.batch();
      for (final photo in photos) {
        batch.insert('photo_cache', {
          'path': photo.path,
          'name': photo.name,
          'album': photo.album,
          'size_bytes': photo.sizeBytes,
          'modified_at': photo.modifiedAt.millisecondsSinceEpoch,
          'is_video': photo.isVideo ? 1 : 0,
          'aspect_ratio': photo.aspectRatio,
          'date_taken': photo.dateTaken?.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PhotoItem>?> loadPhotoCache() async {
    final db = await database;
    final rows = await db.query('photo_cache');
    if (rows.isEmpty) return null;
    return rows.map((r) {
      final ratioRaw = r['aspect_ratio'];
      final ratio = ratioRaw is num && ratioRaw > 0
          ? ratioRaw.toDouble()
          : 1.0;
      final dateRaw = r['date_taken'];
      final dateTaken = dateRaw is int && dateRaw > 0
          ? DateTime.fromMillisecondsSinceEpoch(dateRaw)
          : null;
      return PhotoItem(
        path: r['path'] as String,
        name: r['name'] as String,
        album: r['album'] as String,
        sizeBytes: r['size_bytes'] as int,
        modifiedAt:
            DateTime.fromMillisecondsSinceEpoch(r['modified_at'] as int),
        dateTaken: dateTaken,
        isVideo: (r['is_video'] as int) == 1,
        aspectRatio: ratio,
      );
    }).toList();
  }
}