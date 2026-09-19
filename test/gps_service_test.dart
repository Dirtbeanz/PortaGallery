import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _u16be(int v) => [(v >> 8) & 0xFF, v & 0xFF];

Uint8List _exifJpegWithGps() {
  const gpsIfd = 26;
  const ratStart = 80;

  final tiff = <int>[
    0x49, 0x49, // "II" little-endian
    ..._u16le(0x002A),
    ..._u32le(8), // IFD0 offset
    ..._u16le(1), // IFD0 entry count
    ..._u16le(0x8825), // GPS IFD pointer
    ..._u16le(4), // LONG
    ..._u32le(1),
    ..._u32le(gpsIfd),
    ..._u32le(0), // no next IFD
    ..._u16le(4), // GPS entry count
    ..._u16le(0x0001), ..._u16le(2), ..._u32le(2), 0x4E, 0, 0, 0, // N
    ..._u16le(0x0002), ..._u16le(5), ..._u32le(3), ..._u32le(ratStart),
    ..._u16le(0x0003), ..._u16le(2), ..._u32le(2), 0x57, 0, 0, 0, // W
    ..._u16le(0x0004), ..._u16le(5), ..._u32le(3), ..._u32le(ratStart + 24),
    ..._u32le(0),
    ..._u32le(37), ..._u32le(1),
    ..._u32le(48), ..._u32le(1),
    ..._u32le(0), ..._u32le(1),
    ..._u32le(122), ..._u32le(1),
    ..._u32le(25), ..._u32le(1),
    ..._u32le(0), ..._u32le(1),
  ];

  final exifBody = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, ..._u16be(exifBody.length + 2), ...exifBody,
    0xFF, 0xD9, // EOI
  ]);
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gps_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('parses GPS coordinates from an EXIF JPEG header', () async {
    final file = File(p.join(root.path, 'geo.jpg'));
    file.writeAsBytesSync(_exifJpegWithGps());

    final gps = await PhotoService.readGpsQuick(file.path);

    expect(gps, isNotNull);
    expect(gps!.$1, closeTo(37.8, 0.0001));
    expect(gps.$2, closeTo(-122.416666, 0.0001));
  });

  test('returns null for a JPEG without EXIF and for missing files', () async {
    final plain = File(p.join(root.path, 'plain.jpg'));
    plain.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    expect(await PhotoService.readGpsQuick(plain.path), isNull);
    expect(
      await PhotoService.readGpsQuick(p.join(root.path, 'missing.jpg')),
      isNull,
    );
  });
}
