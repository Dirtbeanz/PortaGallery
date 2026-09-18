import 'dart:io';

import 'package:path/path.dart' as p;

class ExternalDriveService {
  static const Set<String> _systemVolumeNames = {
    'emulated',
    'self',
    'enc_emulated',
  };

  static Future<bool> isReadable(String path) async {
    try {
      final dir = Directory(path);
      await dir.list(followLinks: false).take(1).toList().timeout(
            const Duration(seconds: 3),
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> androidVolumes() async {
    final results = <String>[];
    final seen = <String>{};
    for (final base in const ['/storage', '/mnt/media_rw']) {
      final dir = Directory(base);
      if (!await dir.exists()) continue;
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (_systemVolumeNames.contains(name)) continue;
        if (!(entry is Directory || entry is Link)) continue;
        if (seen.contains(entry.path)) continue;
        if (await isReadable(entry.path)) {
          seen.add(entry.path);
          results.add(entry.path);
        }
      }
    }
    results.sort();
    return results;
  }

  static Future<List<String>> subfolders(String path) async {
    try {
      final entries = await Directory(path).list(followLinks: false).toList();
      final folders = entries
          .whereType<Directory>()
          .map((dir) => dir.path)
          .where((folder) {
            final name = p.basename(folder);
            return !name.startsWith('.') && name != 'Android';
          })
          .toList()
        ..sort((a, b) => p
            .basename(a)
            .toLowerCase()
            .compareTo(p.basename(b).toLowerCase()));
      return folders;
    } catch (_) {
      return [];
    }
  }
}
