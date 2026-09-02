import 'dart:io';

import 'package:exif/exif.dart';

import '../models/photo_metadata.dart';

class MetadataService {
  static Future<PhotoMetadata> readMetadata(String path) async {
    PhotoMetadata meta = const PhotoMetadata();
    final exifMeta = await _readExif(path);
    meta = meta._merge(exifMeta);

    if (meta.width == null || meta.height == null) {
      final dims = await _readDimensions(path);
      meta = PhotoMetadata(
        width: meta.width ?? dims.$1,
        height: meta.height ?? dims.$2,
        dateTaken: meta.dateTaken,
        cameraMake: meta.cameraMake,
        cameraModel: meta.cameraModel,
        iso: meta.iso,
        aperture: meta.aperture,
        shutterSpeed: meta.shutterSpeed,
        focalLength: meta.focalLength,
        gpsLatitude: meta.gpsLatitude,
        gpsLongitude: meta.gpsLongitude,
      );
    }
    return meta;
  }

  static Future<PhotoMetadata> _readExif(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const PhotoMetadata();

      final tags = await readExifFromFile(file);

      return PhotoMetadata(
        width: _intTag(tags, 'Image ImageWidth',
            fallback: 'EXIF ExifImageWidth'),
        height: _intTag(tags, 'Image ImageLength',
            fallback: 'EXIF ExifImageHeight'),
        dateTaken: _dateTag(tags, 'EXIF DateTimeOriginal',
            fallback: 'Image DateTime'),
        cameraMake: _stringTag(tags, 'Image Make'),
        cameraModel: _stringTag(tags, 'Image Model'),
        iso: _stringTag(tags, 'EXIF ISOSpeedRatings',
            fallback: 'EXIF PhotographicSensitivityISO'),
        aperture: _stringTag(tags, 'EXIF FNumber'),
        shutterSpeed: _stringTag(tags, 'EXIF ExposureTime'),
        focalLength: _stringTag(tags, 'EXIF FocalLength'),
        gpsLatitude: _gpsTag(tags, 'GPS GPSLatitude', 'GPS GPSLatitudeRef'),
        gpsLongitude:
            _gpsTag(tags, 'GPS GPSLongitude', 'GPS GPSLongitudeRef'),
      );
    } catch (_) {
      return const PhotoMetadata();
    }
  }

  static int? _intTag(Map<String, IfdTag> tags, String key,
      {String? fallback}) {
    final tag = tags[key] ?? (fallback != null ? tags[fallback] : null);
    if (tag == null) return null;
    try {
      return tag.values.firstAsInt();
    } catch (_) {
      try {
        return int.tryParse(tag.printable);
      } catch (_) {
        return null;
      }
    }
  }

  static String? _stringTag(Map<String, IfdTag> tags, String key,
      {String? fallback}) {
    final tag = tags[key] ?? (fallback != null ? tags[fallback] : null);
    if (tag == null) return null;
    final value = tag.printable.trim();
    if (value.isEmpty || value == '0' || value == '0/0') return null;
    return value;
  }

  static DateTime? _dateTag(Map<String, IfdTag> tags, String key,
      {String? fallback}) {
    final value = _stringTag(tags, key, fallback: fallback);
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.length >= 10) {
      final datePart = trimmed.substring(0, 10).replaceAll(':', '-');
      final result = DateTime.tryParse('$datePart${trimmed.substring(10)}');
      if (result != null) return result;
    }
    return DateTime.tryParse(trimmed);
  }

  static double? _gpsTag(
      Map<String, IfdTag> tags, String key, String refKey) {
    final tag = tags[key];
    if (tag == null) return null;
    final list = tag.values.toList();
    if (list.length < 3) return null;

    try {
      double toDouble(dynamic v) {
        if (v is Ratio) return v.numerator / v.denominator;
        if (v is int) return v.toDouble();
        if (v is double) return v;
        return double.parse(v.toString());
      }

      final deg = toDouble(list[0]);
      final min = toDouble(list[1]);
      final sec = toDouble(list[2]);
      var decimal = deg + min / 60 + sec / 3600;

      final ref = tags[refKey]?.printable ?? '';
      if (ref.toUpperCase().startsWith('S') ||
          ref.toUpperCase().startsWith('W')) {
        decimal = -decimal;
      }
      return decimal;
    } catch (_) {
      return null;
    }
  }

  static Future<(int?, int?)> _readDimensions(String path) async {
    try {
      final file = File(path);
      final raf = await file.open();
      final header = await raf.read(24);
      await raf.close();

      final bytes = header;
      if (bytes.length < 24) return (null, null);

      if (bytes[0] == 0x89 && bytes[1] == 0x50) {
        final w = _readUint32BE(bytes, 16);
        final h = _readUint32BE(bytes, 20);
        return (w, h);
      }

      if (bytes[0] == 0x47 && bytes[1] == 0x49) {
        final w = _readUint16LE(bytes, 6);
        final h = _readUint16LE(bytes, 8);
        return (w, h);
      }

      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return (_readUint32LE(bytes, 18), _readUint32LE(bytes, 22));
      }

      final jpeg = await _readJpegDimensions(file);
      if (jpeg != (null, null)) return jpeg;

      return await _readWebpDimensions(file);
    } catch (_) {
      return (null, null);
    }
  }

  static Future<(int?, int?)> _readJpegDimensions(File file) async {
    try {
      final raf = await file.open();
      final data = await raf.read(65536);
      await raf.close();

      var offset = 2;
      while (offset + 9 < data.length) {
        if (data[offset] != 0xFF) {
          offset++;
          continue;
        }
        final marker = data[offset + 1];
        if (marker == 0xD8 || marker == 0xD9) {
          offset += 2;
          continue;
        }
        if (marker >= 0xD0 && marker <= 0xDA) {
          offset += 2;
          continue;
        }
        final length = (data[offset + 2] << 8) + data[offset + 3];
        if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 &&
            marker != 0xC8 && marker != 0xCC) {
          final h = (data[offset + 5] << 8) + data[offset + 6];
          final w = (data[offset + 7] << 8) + data[offset + 8];
          return (w, h);
        }
        offset += 2 + length;
      }
      return (null, null);
    } catch (_) {
      return (null, null);
    }
  }

  static Future<(int?, int?)> _readWebpDimensions(File file) async {
    try {
      final raf = await file.open();
      final data = await raf.read(40);
      await raf.close();
      if (data.length < 30) return (null, null);

      if (data.length >= 30 &&
          String.fromCharCodes(data.sublist(12, 16)) == 'VP8X') {
        final w = 1 + (data[24] | (data[25] << 8) | (data[26] << 16));
        final h = 1 + (data[27] | (data[28] << 8) | (data[29] << 16));
        return (w, h);
      }
      if (String.fromCharCodes(data.sublist(12, 16)) == 'VP8L' &&
          data[20] == 0x2F) {
        final w = 1 + (((data[21] & 0x3F) << 8) | data[22]);
        final h = 1 + (((data[23] & 0x0F) << 10) | (data[24] << 2) |
            ((data[25] & 0xC0) >> 6));
        return (w, h);
      }
      return (null, null);
    } catch (_) {
      return (null, null);
    }
  }

  static int _readUint16LE(List<int> b, int off) => b[off] | (b[off + 1] << 8);
  static int _readUint32LE(List<int> b, int off) =>
      b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
  static int _readUint32BE(List<int> b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
}

extension on PhotoMetadata {
  PhotoMetadata _merge(PhotoMetadata other) {
    return PhotoMetadata(
      width: width ?? other.width,
      height: height ?? other.height,
      dateTaken: dateTaken ?? other.dateTaken,
      cameraMake: cameraMake ?? other.cameraMake,
      cameraModel: cameraModel ?? other.cameraModel,
      iso: iso ?? other.iso,
      aperture: aperture ?? other.aperture,
      shutterSpeed: shutterSpeed ?? other.shutterSpeed,
      focalLength: focalLength ?? other.focalLength,
      gpsLatitude: gpsLatitude ?? other.gpsLatitude,
      gpsLongitude: gpsLongitude ?? other.gpsLongitude,
    );
  }
}