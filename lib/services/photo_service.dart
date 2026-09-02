import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/photo_item.dart';

class PhotoService {
  static final Set<String> imageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp',
    '.heic', '.heif', '.avif', '.tif', '.tiff', '.jfif',
  };

  static final Set<String> videoExtensions = {
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.wmv',
  };

  static bool isSupported(String path) {
    final ext = p.extension(path).toLowerCase();
    return imageExtensions.contains(ext) || videoExtensions.contains(ext);
  }

  static bool isVideoPath(String path) =>
      videoExtensions.contains(p.extension(path).toLowerCase());

  static Future<List<PhotoItem>> scanDirectory(String rootPath) async {
    final photos = <PhotoItem>[];
    await _scan(Directory(rootPath), photos, rootPath);
    photos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return photos;
  }

  static Future<void> _scan(
      Directory dir, List<PhotoItem> out, String rootPath) async {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    final rootAbs = p.absolute(rootPath);
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;

      try {
        final type = await FileSystemEntity.type(entry.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await _scan(Directory(entry.path), out, rootAbs);
        } else if (type == FileSystemEntityType.file &&
            isSupported(entry.path)) {
          final stat = await entry.stat();
          final parent = p.dirname(entry.path);
          final relative = parent == rootAbs
              ? ''
              : p.relative(parent, from: rootAbs);

          out.add(PhotoItem(
            path: entry.path,
            name: name,
            album: relative,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            isVideo: isVideoPath(entry.path),
          ));
        }
      } catch (_) {
        continue;
      }
    }
  }

  static Future<void> importFile(String sourcePath, String libraryPath,
      {String? subFolder}) async {
    final fileName = p.basename(sourcePath);
    var targetDir = libraryPath;
    if (subFolder != null && subFolder.isNotEmpty) {
      targetDir = p.join(libraryPath, subFolder);
      await Directory(targetDir).create(recursive: true);
    }

    var targetPath = p.join(targetDir, fileName);
    var counter = 1;
    while (File(targetPath).existsSync()) {
      final ext = p.extension(fileName);
      final base = p.basenameWithoutExtension(fileName);
      targetPath = p.join(targetDir, '${base}_$counter$ext');
      counter++;
    }

    await File(sourcePath).copy(targetPath);
  }

  static Future<String> exportFile(String sourcePath, String targetPath) async {
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  static double readAspectRatio(String path) {
    try {
      final file = File(path);
      final raf = file.openSync();
      final header = raf.readSync(65536);
      raf.closeSync();
      final bytes = header;
      if (bytes.length < 24) return 1.0;

      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        var off = 2;
        while (off + 9 < bytes.length) {
          if (bytes[off] != 0xFF) { off++; continue; }
          final m = bytes[off + 1];
          if (m == 0xD8 || m == 0xD9) { off += 2; continue; }
          if (m >= 0xD0 && m <= 0xDA) { off += 2; continue; }
          final len = (bytes[off + 2] << 8) + bytes[off + 3];
          if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
            final h = (bytes[off + 5] << 8) + bytes[off + 6];
            final w = (bytes[off + 7] << 8) + bytes[off + 8];
            if (h > 0) return w / h;
            break;
          }
          off += 2 + len;
        }
        return 1.0;
      }

      if (bytes[0] == 0x89 && bytes[1] == 0x50) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (h > 0) return w / h;
      }

      if (bytes[0] == 0x47 && bytes[1] == 0x49) {
        final w = bytes[6] | (bytes[7] << 8);
        final h = bytes[8] | (bytes[9] << 8);
        if (h > 0) return w / h;
      }

      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        final w = bytes[18] | (bytes[19] << 8) | (bytes[20] << 16) | (bytes[21] << 24);
        final h = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24);
        if (h > 0) return w / h;
      }

      if (bytes.length >= 30 && bytes[0] == 0x52 && bytes[1] == 0x49 &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
        if (bytes.length >= 30 &&
            String.fromCharCodes(bytes.sublist(12, 16)) == 'VP8X') {
          final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
          final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
          if (h > 0) return w / h;
        }
      }
    } catch (_) {}

    return 1.0;
  }
}