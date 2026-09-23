import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> _app1WithOrientation(int orientation) {
  final tiff = <int>[
    0x49, 0x49, // II
    ..._u16le(0x002A),
    ..._u32le(8), // IFD0 offset
    ..._u16le(1), // one IFD0 entry
    ..._u16le(0x0112), ..._u16le(3), ..._u32le(1), ..._u16le(orientation),
    0, 0, // inline value padding
    ..._u32le(0), // no next IFD
  ];
  final body = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  return [0xFF, 0xE1, ..._u16be(body.length + 2), ...body];
}

List<int> _sof0(int width, int height) => [
      0xFF, 0xC0, 0x00, 0x11, 0x08,
      (height >> 8) & 0xFF, height & 0xFF,
      (width >> 8) & 0xFF, width & 0xFF,
      0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    ];

List<int> _jpeg(int orientation, int width, int height) => [
      0xFF, 0xD8,
      ..._app1WithOrientation(orientation),
      ..._sof0(width, height),
      0xFF, 0xD9,
    ];

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('orientation_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('readDimensions applies EXIF orientation to JPEG dimensions', () {
    final normal = File(p.join(root.path, 'normal.jpg'))
      ..writeAsBytesSync(_jpeg(1, 80, 40));
    expect(PhotoService.readDimensions(normal.path), (80, 40));

    final rotate180 = File(p.join(root.path, 'r180.jpg'))
      ..writeAsBytesSync(_jpeg(3, 80, 40));
    expect(PhotoService.readDimensions(rotate180.path), (80, 40));

    final rotate90 = File(p.join(root.path, 'r90.jpg'))
      ..writeAsBytesSync(_jpeg(6, 80, 40));
    expect(PhotoService.readDimensions(rotate90.path), (40, 80));

    final rotate270 = File(p.join(root.path, 'r270.jpg'))
      ..writeAsBytesSync(_jpeg(8, 80, 40));
    expect(PhotoService.readDimensions(rotate270.path), (40, 80));
  });
}