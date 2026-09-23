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
import 'photo_service.dart';

class ThumbnailService {
  /// Rotates a JPEG according to an EXIF orientation (3, 6, or 8) and
  /// re-encodes it without EXIF so viewers do not apply orientation again.
  @visibleForTesting
  static Uint8List? rotateJpeg(Uint8List bytes, int orientation) {
    try {
      var decoded = img.decodeJpg(bytes);
      if (decoded == null) return null;
      switch (orientation) {
        case 3:
          decoded = img.copyRotate(decoded, angle: 180);
          break;
        case 6:
          decoded = img.copyRotate(decoded, angle: 90);
          break;
        case 8:
          decoded = img.copyRotate(decoded, angle: 270);
          break;
        default:
          return null;
      }
      decoded.exif.clear();
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 80));
    } catch (_) {
      return null;
    }
  }

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
    Directory? temporary;
    try {
      final target = await expectedPath(photo);
      if (await File(target).exists()) return true;
      temporary = await Directory(p.dirname(target)).createTemp('thumb-');
      final output = p.join(temporary.path, 'thumbnail.jpg');
      final ok =
          photo.isVideo
              ? await _videoFrame(photo, output)
              : await _imageThumb(photo, output);
      if (!ok ||
          !await File(output).exists() ||
          await File(output).length() == 0) {
        return false;
      }
      await File(output).rename(target);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await temporary?.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<bool> _imageThumb(PhotoItem photo, String target) async {
    // Fast path: many JPEGs carry an embedded EXIF thumbnail. Reusing it
    // only reads the file header (256KB) instead of decoding the whole
    // original, which is a large win on slow HDDs. The embedded pixels are
    // stored unrotated, so the original's EXIF orientation is applied here.
    final embedded = await PhotoService.readExifThumbnail(photo.path);
    if (embedded != null) {
      final (bytes, width, height, orientation) = embedded;
      final longest = width > height ? width : height;
      if (longest >= 128 && bytes.length <= 2 * 1024 * 1024) {
        Uint8List? out = bytes;
        if (orientation == 3 || orientation == 6 || orientation == 8) {
          out = await Isolate.run<Uint8List?>(
              () => ThumbnailService.rotateJpeg(bytes, orientation));
        } else if (orientation != 1) {
          out = null;
        }
        if (out != null) {
          try {
            await File(target).writeAsBytes(out, flush: true);
            return true;
          } catch (_) {}
        }
      }
    }
    if (await _imageThumbFlutter(photo.path, target)) return true;
    if (!kIsWeb && Platform.isAndroid) {
      return await _compressPlatform(photo.path, target);
    }
    return await _magickThumb(photo.path, target);
  }

  static Future<bool> _imageThumbFlutter(String source, String target) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    late final ByteData rgba;
    late final int w;
    late final int h;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > 100000 ||
          height > 100000 ||
          width * height > 200000000) {
        return false;
      }
      final longest = width > height ? width : height;
      final scale = longest > 320 ? 320 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round().clamp(1, 320),
        targetHeight: (height * scale).round().clamp(1, 320),
      );
      image = (await codec.getNextFrame()).image;
      w = image.width;
      h = image.height;
      if (w <= 0 || h <= 0 || w > 320 || h > 320) return false;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      rgba = data;
    } catch (_) {
      return false;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
    try {
      final encoded = await Isolate.run(() {
        final decoded = img.Image.fromBytes(
          width: w,
          height: h,
          bytes: rgba.buffer,
          bytesOffset: rgba.offsetInBytes,
          order: img.ChannelOrder.rgba,
        );
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 70));
      });
      await File(target).writeAsBytes(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _compressPlatform(String source, String target) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final intermediate = File('$target.platform.jpg');
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        source,
        intermediate.path,
        format: CompressFormat.jpeg,
        quality: 70,
        minWidth: 320,
        minHeight: 320,
      );
      if (result != null) {
        return await _imageThumbFlutter(result.path, target);
      }
    } catch (_) {
      return false;
    } finally {
      try {
        if (await intermediate.exists()) await intermediate.delete();
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> _runCommand(String executable, List<String> args) async {
    Process? process;
    StreamSubscription<List<int>>? stdout;
    StreamSubscription<List<int>>? stderr;
    int? exitCode;
    try {
      process = await Process.start(executable, args);
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      stdout = process.stdout.listen(
        (_) {},
        onDone: stdoutDone.complete,
        onError: stdoutDone.completeError,
        cancelOnError: true,
      );
      stderr = process.stderr.listen(
        (_) {},
        onDone: stderrDone.complete,
        onError: stderrDone.completeError,
        cancelOnError: true,
      );
      await Future.wait([
        process.stdin.close(),
        process.exitCode.then((code) {
          exitCode = code;
        }),
        stdoutDone.future,
        stderrDone.future,
      ], eagerError: true).timeout(const Duration(seconds: 20));
      return exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      if (process != null && exitCode == null) {
        process.kill(
          Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigkill,
        );
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      await stdout?.cancel();
      await stderr?.cancel();
    }
  }

  static Future<bool> _magickThumb(String source, String target) async {
    if (kIsWeb || Platform.isAndroid) return false;
    for (final exe in ['magick', 'convert', 'heif-thumbnailer']) {
      final intermediate = File('$target.$exe.png');
      try {
        final args =
            exe == 'heif-thumbnailer'
                ? ['-s', '320', source, intermediate.path]
                : [
                  '-limit',
                  'thread',
                  '1',
                  '-limit',
                  'memory',
                  '128MiB',
                  '-limit',
                  'map',
                  '256MiB',
                  '$source[0]',
                  '-auto-orient',
                  '-thumbnail',
                  '320x320>',
                  '-quality',
                  '70',
                  intermediate.path,
                ];
        if (await _runCommand(exe, args) &&
            await _imageThumbFlutter(intermediate.path, target)) {
          return true;
        }
      } catch (_) {
      } finally {
        try {
          if (await intermediate.exists()) await intermediate.delete();
        } catch (_) {}
      }
    }
    return false;
  }

  static Future<bool> _videoFrame(PhotoItem photo, String target) async {
    if (!kIsWeb && Platform.isAndroid) {
      final data = await VideoThumbnail.thumbnailData(
        video: photo.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        maxHeight: 320,
        quality: 70,
        timeMs: 1000,
      );
      if (data == null || data.isEmpty) return false;
      await File(target).writeAsBytes(data, flush: true);
      return true;
    }

    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return await _runCommand('ffmpeg', [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-threads',
        '1',
        '-filter_threads',
        '1',
        '-filter_complex_threads',
        '1',
        '-ss',
        '1',
        '-i',
        photo.path,
        '-frames:v',
        '1',
        '-an',
        '-vf',
        "scale=w='min(320,iw)':h='min(320,ih)':force_original_aspect_ratio=decrease",
        '-threads',
        '1',
        '-q:v',
        '5',
        '-y',
        target,
      ]);
    }

    return false;
  }
}
