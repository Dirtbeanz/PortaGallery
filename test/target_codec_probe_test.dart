import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> _app1(int orientation) {
  final tiff = <int>[
    0x49, 0x49,
    ..._u16le(0x002A),
    ..._u32le(8),
    ..._u16le(1),
    ..._u16le(0x0112), ..._u16le(3), ..._u32le(1), ..._u16le(orientation),
    0, 0,
    ..._u32le(0),
  ];
  final body = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  return [0xFF, 0xE1, ..._u16be(body.length + 2), ...body];
}

List<int> _jpeg(int orientation, int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 80, 40));
  final plain = img.encodeJpg(image, quality: 90);
  return [
    plain[0], plain[1],
    ..._app1(orientation),
    ...plain.sublist(2),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('descriptor and targeted codec dimensions vs EXIF orientation', () async {
    for (final orientation in [1, 6, 8]) {
      final bytes = Uint8List.fromList(_jpeg(orientation, 80, 40));
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      // ignore: avoid_print
      print('orientation $orientation: descriptor '
          '${descriptor.width}x${descriptor.height}');

      // Same computation the thumbnail service uses.
      final w = descriptor.width;
      final h = descriptor.height;
      final longest = w > h ? w : h;
      final scale = longest > 40 ? 40 / longest : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round(),
        targetHeight: (h * scale).round(),
      );
      final frame = await codec.getNextFrame();
      // ignore: avoid_print
      print('orientation $orientation: targeted decode '
          '${frame.image.width}x${frame.image.height}');
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  });
}