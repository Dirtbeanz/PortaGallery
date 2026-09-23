import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<int> _u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

Uint8List _jpegWithOrientation(int orientation) {
  final image = img.Image(width: 80, height: 40);
  img.fill(image, color: img.ColorRgb8(10, 120, 200));
  final plain = img.encodeJpg(image, quality: 90);

  final tiff = <int>[
    0x49, 0x49,
    ..._u16le(0x002A),
    ..._u32le(8),
    ..._u16le(1),
    ..._u16le(0x0112), ..._u16le(3), ..._u32le(1), ..._u16le(orientation), 0, 0,
    ..._u32le(0),
  ];
  final exifBody = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  final app1 = <int>[0xFF, 0xE1, ..._u16be(exifBody.length + 2), ...exifBody];

  return Uint8List.fromList([
    plain[0], plain[1], // SOI
    ...app1,
    ...plain.sublist(2),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter decoder applies EXIF orientation', () async {
    final normal = _jpegWithOrientation(1);
    final codecNormal = await ui.instantiateImageCodec(normal);
    final frameNormal = await codecNormal.getNextFrame();
    expect(frameNormal.image.width, 80);
    expect(frameNormal.image.height, 40);
    frameNormal.image.dispose();
    codecNormal.dispose();

    for (final orientation in [6, 8]) {
      final bytes = _jpegWithOrientation(orientation);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 40,
          reason: 'orientation $orientation should be rotated');
      expect(frame.image.height, 80,
          reason: 'orientation $orientation should be rotated');
      frame.image.dispose();
      codec.dispose();
    }
  });
}