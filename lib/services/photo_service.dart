import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/photo_item.dart';

class PhotoService {
  static final Set<String> imageExtensions = {
    '.jpg', '.jpeg', '.jpe', '.png', '.gif', '.bmp', '.webp',
    '.heic', '.heif', '.avif', '.tif', '.tiff', '.jfif',
    '.jp2', '.j2k', '.jxl', '.svg', '.ico', '.cur',
    '.psd', '.psb', '.mpo', '.insp',
    // Camera RAW formats (embedded preview used for thumbnails).
    '.raw', '.dng', '.cr2', '.cr3', '.crw', '.nef', '.nrw', '.arw',
    '.srf', '.sr2', '.orf', '.rw2', '.pef', '.raf', '.3fr', '.fff',
    '.mef', '.mos', '.mrw', '.x3f', '.erf', '.rwl', '.kdc', '.dcr',
    '.ari', '.srw', '.iiq', '.r3d', '.ptx', '.cap', '.rwz',
  };

  static final Set<String> videoExtensions = {
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.3gpp',
    '.wmv', '.flv', '.f4v', '.mpg', '.mpeg', '.m2ts', '.mts', '.ts',
    '.ogv', '.ogg', '.vob', '.asf', '.rm', '.rmvb',
  };

  static bool isSupported(String path) {
    final ext = p.extension(path).toLowerCase();
    return imageExtensions.contains(ext) || videoExtensions.contains(ext);
  }

  static bool isVideoPath(String path) =>
      videoExtensions.contains(p.extension(path).toLowerCase());

  static bool isRawPath(String path) {
    const raw = {
      '.raw', '.dng', '.cr2', '.cr3', '.crw', '.nef', '.nrw', '.arw',
      '.srf', '.sr2', '.orf', '.rw2', '.pef', '.raf', '.3fr', '.fff',
      '.mef', '.mos', '.mrw', '.x3f', '.erf', '.rwl', '.kdc', '.dcr',
      '.ari', '.srw', '.iiq', '.r3d', '.ptx', '.cap', '.rwz',
    };
    return raw.contains(p.extension(path).toLowerCase());
  }

  static Future<List<PhotoItem>> scanDirectory(String rootPath,
      {bool showHidden = false}) async {
    final photos = <PhotoItem>[];
    final directories = <Directory>[Directory(p.absolute(rootPath))];
    while (directories.isNotEmpty) {
      final dir = directories.removeLast();
      await _scan(dir, photos, rootPath, directories, showHidden: showHidden);
    }
    photos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return photos;
  }

  static Future<void> _scan(Directory dir, List<PhotoItem> out,
      String rootPath, List<Directory> subdirs, {bool showHidden = false}) async {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    if (!showHidden) {
      for (final entry in entries) {
        final name = p.basename(entry.path).toLowerCase();
        if (name == '.nomedia' && entry is File) {
          return;
        }
      }
    }

    final rootAbs = p.absolute(rootPath);
    final files = <File>[];

    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (!showHidden && name.startsWith('.')) continue;
      if (entry is Directory) {
        subdirs.add(entry);
      } else if (entry is File && isSupported(entry.path)) {
        files.add(entry);
      }
    }

    const batchSize = 24;
    for (var i = 0; i < files.length; i += batchSize) {
      final batch = files.sublist(
          i, i + batchSize > files.length ? files.length : i + batchSize);
      await Future.wait(batch.map((file) async {
        try {
          final stat = await file.stat();
          if (stat.type != FileSystemEntityType.file) return;
          final parent = p.dirname(file.path);
          final relative =
              parent == rootAbs ? '' : p.relative(parent, from: rootAbs);

          // EXIF date reading deferred to background enrichment.
          out.add(PhotoItem(
            path: file.path,
            name: p.basename(file.path),
            album: relative,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            isVideo: isVideoPath(file.path),
          ));
        } catch (_) {}
      }));
    }
  }

  /// Lightweight EXIF date reader — only reads first 64KB of the file.
  /// Much faster than the full `exif` package which reads the entire file.
  static Future<DateTime?> readExifDateQuick(String path) async {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      raf = await file.open();
      final header = await raf.read(65536);

      if (header.length < 12) return null;
      // Only works for JPEG (starts with FF D8).
      if (header[0] != 0xFF || header[1] != 0xD8) return null;

      var off = 2;
      while (off + 9 < header.length) {
        if (header[off] != 0xFF) { off++; continue; }
        final marker = header[off + 1];
        if (marker == 0xD8 || marker == 0xD9) { off += 2; continue; }
        if (marker >= 0xD0 && marker <= 0xDA) { off += 2; continue; }
        if (off + 3 >= header.length) break;
        final len = (header[off + 2] << 8) + header[off + 3];
        if (len < 2) break;

        // APP1 (EXIF) marker.
        if (marker == 0xE1) {
          final exifDate = _parseExifDate(header, off + 4, len - 2);
          if (exifDate != null) return exifDate;
        }
        off += 2 + len;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  static DateTime? _parseExifDate(List<int> data, int start, int length) {
    try {
      // Look for "DateTimeOriginal" (tag 0x9003) or "DateTime" (tag 0x0132)
      // in the EXIF IFD. We do a byte scan for the ASCII date pattern
      // "YYYY:MM:DD HH:MM:SS" which is always present in these tags.
      final end = start + length;
      for (var i = start; i < end - 19; i++) {
        // Check for "20" prefix (years 2000-2099) followed by ":MM:DD"
        if (data[i] == 0x32 && data[i + 1] == 0x30 && // "20"
            data[i + 4] == 0x3A && data[i + 7] == 0x3A && // "::"
            data[i + 10] == 0x20 && data[i + 13] == 0x3A && data[i + 16] == 0x3A) {
          final str = String.fromCharCodes(data.sublist(i, i + 19));
          final datePart = str.substring(0, 10).replaceAll(':', '-');
          final result = DateTime.tryParse('$datePart${str.substring(10)}');
          if (result != null && result.year > 1990 && result.year < 2100) {
            return result;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, DateTime>> readExifDatesBulk(
      List<String> paths) async {
    final out = <String, DateTime>{};
    for (final path in paths) {
      final d = await readExifDateQuick(path);
      if (d != null) out[path] = d;
    }
    return out;
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
    final dims = readDimensions(path);
    if (dims == null || dims.$1 <= 0 || dims.$2 <= 0) return 1.0;
    return dims.$1 / dims.$2;
  }

  static (int, int)? readDimensions(String path) {
    RandomAccessFile? raf;
    try {
      final file = File(path);
      raf = file.openSync();
      final header = raf.readSync(65536);
      final bytes = header;
      if (bytes.length < 24) return null;

      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        var off = 2;
        var orientation = 1;
        var w = 0;
        var h = 0;
        while (off + 9 < bytes.length) {
          if (bytes[off] != 0xFF) { off++; continue; }
          final m = bytes[off + 1];
          if (m == 0xD8 || m == 0xD9) { off += 2; continue; }
          if (m >= 0xD0 && m <= 0xDA) { off += 2; continue; }
          final len = (bytes[off + 2] << 8) + bytes[off + 3];
          if (m == 0xE1 && off + 2 + len <= bytes.length) {
            orientation = exifOrientation(bytes, off + 4, len - 2);
          }
          if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
            h = (bytes[off + 5] << 8) + bytes[off + 6];
            w = (bytes[off + 7] << 8) + bytes[off + 8];
            if (h > 0 && w > 0) {
              if (orientation >= 5 && orientation <= 8) {
                final t = w;
                w = h;
                h = t;
              }
              return (w, h);
            }
            break;
          }
          off += 2 + len;
        }
        return null;
      }

      if (bytes[0] == 0x89 && bytes[1] == 0x50) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (h > 0) return (w, h);
      }

      if (bytes[0] == 0x47 && bytes[1] == 0x49) {
        final w = bytes[6] | (bytes[7] << 8);
        final h = bytes[8] | (bytes[9] << 8);
        if (h > 0) return (w, h);
      }

      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        final w = bytes[18] | (bytes[19] << 8) | (bytes[20] << 16) | (bytes[21] << 24);
        final h = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24);
        if (h > 0) return (w, h);
      }

      if (bytes.length >= 30 && bytes[0] == 0x52 && bytes[1] == 0x49 &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
        if (bytes.length >= 30 &&
            String.fromCharCodes(bytes.sublist(12, 16)) == 'VP8X') {
          final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
          final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
          if (h > 0) return (w, h);
        }
      }
    } catch (_) {
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }

    return null;
  }

  static int exifOrientation(List<int> b, int start, int length) {
    try {
      if (start + 6 + 8 > b.length || length < 14) return 1;
      if (!(b[start] == 0x45 && b[start + 1] == 0x78 &&
          b[start + 2] == 0x69 && b[start + 3] == 0x66)) {
        return 1;
      }
      var p = start + 6;
      final little = b[p] == 0x49;
      p += 2;
      final tag = u16(b, p, little);
      p += 2;
      final entryCount = u16(b, p, little);
      p += 2;
      final isTiff = tag == 0x002A || tag == 0x2A00;
      if (!isTiff) return 1;
      final ifdOffset = u32(b, p, little);
      var ifd = start + 6 + ifdOffset;
      for (var i = 0; i < entryCount && ifd + 12 <= b.length; i++) {
        final eTag = u16(b, ifd, little);
        final eType = u16(b, ifd + 2, little);
        final eCount = u32(b, ifd + 4, little);
        if (eTag == 0x0112 && eType == 3 && eCount == 1) {
          return u16(b, ifd + 8, little);
        }
        ifd += 12;
      }
    } catch (_) {}
    return 1;
  }

  static int u16(List<int> b, int p, bool little) {
    if (little) return b[p] | (b[p + 1] << 8);
    return (b[p] << 8) | b[p + 1];
  }

  static int u32(List<int> b, int p, bool little) {
    if (little) {
      return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);
    }
    return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
  }
}