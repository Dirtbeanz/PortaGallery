import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_gallery/services/thumbnail_service.dart';

void main() {
  Uint8List landscapeJpeg() {
    final image = img.Image(width: 80, height: 40);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  test('orientation 6 rotates a landscape thumb to portrait', () {
    final rotated = ThumbnailService.rotateJpeg(landscapeJpeg(), 6);

    expect(rotated, isNotNull);
    final decoded = img.decodeJpg(rotated!)!;
    expect(decoded.width, 40);
    expect(decoded.height, 80);
  });

  test('orientation 8 rotates a landscape thumb to the other portrait', () {
    final rotated = ThumbnailService.rotateJpeg(landscapeJpeg(), 8);

    expect(rotated, isNotNull);
    final decoded = img.decodeJpg(rotated!)!;
    expect(decoded.width, 40);
    expect(decoded.height, 80);
  });

  test('orientation 3 keeps dimensions but rotates 180 degrees', () {
    final rotated = ThumbnailService.rotateJpeg(landscapeJpeg(), 3);

    expect(rotated, isNotNull);
    final decoded = img.decodeJpg(rotated!)!;
    expect(decoded.width, 80);
    expect(decoded.height, 40);
  });

  test('unsupported orientations return null so callers fall back', () {
    expect(ThumbnailService.rotateJpeg(landscapeJpeg(), 2), isNull);
    expect(ThumbnailService.rotateJpeg(landscapeJpeg(), 5), isNull);
    expect(ThumbnailService.rotateJpeg(landscapeJpeg(), 7), isNull);
  });
}