import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/photo_item.dart';


class ThumbnailService {
  static Directory? _dir;

  static Future<Directory> cacheDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  static String key(PhotoItem photo) {
    final raw =
        '${photo.path}|${photo.sizeBytes}|${photo.modifiedAt.millisecondsSinceEpoch}';
    var h = 0x811c9dc5;
    for (final c in raw.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  static Future<String> expectedPath(PhotoItem photo) async {
    final dir = await cacheDir();
    return p.join(dir.path, '${key(photo)}.jpg');
  }

  static Future<bool> generate(PhotoItem photo) async {
    final target = await expectedPath(photo);
    if (await File(target).exists()) return true;
    try {
      if (photo.isVideo) {
        return _videoFrame(photo, target);
      } else {
        return _imageThumb(photo, target);
      }
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _imageThumb(PhotoItem photo, String target) async {
    try {
      final bytes = await File(photo.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 320,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        final w = frame.image.width;
        final h = frame.image.height;
        final rgba = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        frame.image.dispose();
        if (rgba == null) return false;
        final buf = rgba.buffer;

        // Flutter's codec already applies EXIF orientation — the decoded
        // RGBA pixels have the correct display orientation, so no manual
        // rotation is needed.
        final encoded = await Isolate.run(() {
          final decoded = img.Image.fromBytes(
            width: w,
            height: h,
            bytes: buf,
            order: img.ChannelOrder.rgba,
          );
          return Uint8List.fromList(img.encodeJpg(decoded, quality: 70));
        });

        await File(target).writeAsBytes(encoded, flush: true);
        return true;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Flutter's codec can't decode RAW/HEIC; fall back to platform codecs
      // or system tools.
      if (!kIsWeb && Platform.isAndroid) {
        final ok = await _compressPlatform(photo.path, target);
        if (ok) return true;
      }
      return _magickThumb(photo.path, target);
    }
  }

  static Future<bool> _compressPlatform(String source, String target) async {
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        source,
        target,
        format: CompressFormat.jpeg,
        quality: 70,
        minWidth: 320,
        minHeight: 320,
      );
      if (result != null && await File(result.path).exists()) return true;
    } catch (_) {}
    return false;
  }

  static Future<bool> _magickThumb(String source, String target) async {
    if (kIsWeb) return false;
    try {
      for (final exe in ['magick', 'convert', 'heif-convert']) {
        final args = exe == 'heif-convert'
            ? [source, target]
            : [
                '$source[0]',
                '-auto-orient',
                '-thumbnail',
                '320x320>',
                '-quality',
                '70',
                target,
              ];
        final result = await Process.run(exe, args);
        if (result.exitCode == 0 && await File(target).exists()) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _videoFrame(PhotoItem photo, String target) async {
    if (!kIsWeb && Platform.isAndroid) {
      final data = await VideoThumbnail.thumbnailData(
        video: photo.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 70,
        timeMs: 1000,
      );
      if (data == null || data.isEmpty) return false;
      await File(target).writeAsBytes(data, flush: true);
      return true;
    }

    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      final result = await Process.run('ffmpeg', [
        '-ss', '1',
        '-i', photo.path,
        '-frames:v', '1',
        '-vf', 'scale=320:-2',
        '-q:v', '5',
        '-y',
        target,
      ]);
      return result.exitCode == 0 && await File(target).exists();
    }

    return false;
  }
}
