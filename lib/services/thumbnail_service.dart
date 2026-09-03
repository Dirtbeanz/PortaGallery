import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
        final ok = await _videoFrame(photo, target);
        if (!ok) return false;
      } else {
        final ok = await _imageThumb(photo, target);
        if (!ok) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _imageThumb(PhotoItem photo, String target) async {
    final bytes = await File(photo.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 640,
      targetHeight: 640,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      if (data == null) return false;

      final encoded = await Isolate.run(() {
        final img.Image decoded = img.Image.fromBytes(
          width: frame.image.width,
          height: frame.image.height,
          bytes: data.buffer,
          order: img.ChannelOrder.rgba,
        );
        return Uint8List.fromList(
            img.encodeJpg(decoded, quality: 82));
      });

      await File(target).writeAsBytes(encoded, flush: true);
      return true;
    } finally {
      codec.dispose();
    }
  }

  static Future<bool> _videoFrame(PhotoItem photo, String target) async {
    if (!kIsWeb && Platform.isAndroid) {
      final data = await VideoThumbnail.thumbnailData(
        video: photo.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 640,
        quality: 75,
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
        '-vf', 'scale=640:-2',
        '-q:v', '5',
        '-y',
        target,
      ]);
      return result.exitCode == 0 && await File(target).exists();
    }

    return false;
  }
}