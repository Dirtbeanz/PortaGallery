import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];

Uint8List _jpegWithExifThumb() {
  final thumb = <int>[
    0xFF, 0xD8,
    0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x10, 0x00, 0x10, 0x03,
    0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xFF, 0xFE, 0x00, 0x63,
    ...List<int>.filled(97, 0),
    0xFF, 0xD9,
  ];

  const ifd1 = 14;
  const thumbOffset = 44;
  final tiff = <int>[
    0x49, 0x49, // II
    ..._u16le(0x002A),
    ..._u32le(8), // IFD0 offset
    ..._u16le(0), // IFD0 entry count
    ..._u32le(ifd1), // next IFD (IFD1) offset
    ..._u16le(2), // IFD1 entry count
    ..._u16le(0x0201), ..._u16le(4), ..._u32le(1), ..._u32le(thumbOffset),
    ..._u16le(0x0202), ..._u16le(4), ..._u32le(1), ..._u32le(thumb.length),
    ..._u32le(0), // no next IFD
    ...thumb,
  ];

  final exifBody = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  return Uint8List.fromList([
    0xFF, 0xD8,
    0xFF, 0xE1, ..._u16be(exifBody.length + 2), ...exifBody,
    0xFF, 0xD9,
  ]);
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('exif_thumb_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('extracts the embedded EXIF thumbnail from a JPEG', () async {
    final file = File(p.join(root.path, 'withthumb.jpg'));
    file.writeAsBytesSync(_jpegWithExifThumb());

    final result = await PhotoService.readExifThumbnail(file.path);

    expect(result, isNotNull);
    final (bytes, width, height, orientation) = result!;
    expect(width, 16);
    expect(height, 16);
    expect(orientation, 1);
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
  });

  test('returns null when the JPEG has no embedded thumbnail', () async {
    final file = File(p.join(root.path, 'nothumb.jpg'));
    file.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    expect(await PhotoService.readExifThumbnail(file.path), isNull);
  });

  test('returns null for a missing file', () async {
    expect(
      await PhotoService.readExifThumbnail(p.join(root.path, 'missing.jpg')),
      isNull,
    );
  });
}