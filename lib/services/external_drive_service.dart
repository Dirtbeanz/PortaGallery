import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'diagnostic_log_service.dart';

class AndroidVolume {
  final String? path;
  final String? uuid;
  final String description;
  final bool removable;
  final bool primary;
  final bool mounted;
  final String state;

  const AndroidVolume({
    required this.path,
    required this.uuid,
    required this.description,
    required this.removable,
    required this.primary,
    required this.mounted,
    required this.state,
  });

  factory AndroidVolume.fromMap(Map<Object?, Object?> map) {
    return AndroidVolume(
      path: map['path'] as String?,
      uuid: map['uuid'] as String?,
      description: (map['description'] as String?) ?? '',
      removable: (map['removable'] as bool?) ?? false,
      primary: (map['primary'] as bool?) ?? false,
      mounted: (map['mounted'] as bool?) ?? false,
      state: (map['state'] as String?) ?? '',
    );
  }
}

class ExternalDriveService {
  static const MethodChannel _channel = MethodChannel('portagallery/drives');

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

  static Future<List<AndroidVolume>> platformVolumes() async {
    try {
      final raw =
          await _channel.invokeListMethod<Map<Object?, Object?>>('listVolumes');
      if (raw == null) return [];
      return raw.map(AndroidVolume.fromMap).toList();
    } on MissingPluginException {
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<String>> androidVolumes() async {
    final results = <String>[];
    final seen = <String>{};

    final platform = await platformVolumes();
    DiagnosticLogService.instance.log(
        'DRIVES platform volumes: ${platform.map((v) => '${v.description}|'
            'path=${v.path}|removable=${v.removable}|mounted=${v.mounted}|'
            'state=${v.state}').join('; ')}');
    for (final volume in platform) {
      final path = volume.path;
      if (path == null || path.isEmpty) continue;
      if (_systemVolumeNames.contains(p.basename(path))) continue;
      if (!volume.mounted) continue;
      if (seen.contains(path)) continue;
      if (await isReadable(path)) {
        seen.add(path);
        results.add(path);
      }
    }

    if (results.isEmpty) {
      for (final base in const ['/storage', '/mnt/media_rw']) {
        final dir = Directory(base);
        if (!await dir.exists()) continue;
        List<FileSystemEntity> entries;
        try {
          entries = await dir.list(followLinks: false).toList();
        } catch (e) {
          DiagnosticLogService.instance.log('DRIVES cannot list $base: $e');
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
    }

    DiagnosticLogService.instance
        .log('DRIVES accessible volumes: ${results.join(', ')}');
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
