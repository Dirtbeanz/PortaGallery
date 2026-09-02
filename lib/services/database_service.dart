import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: unnecessary_import
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/photo_notes.dart';

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
        version: 2,
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

  Future<void> clearFavorites() async {
    final db = await database;
    await db.delete('favorites');
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
}