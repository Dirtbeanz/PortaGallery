import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('photo_gallery_takeout_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('reads takeout sidecar date and description', () async {
    final media = File(p.join(root.path, 'PXL_20200101.jpg'));
    media.createSync();

    final sidecar = {
      'title': 'PXL_20200101.jpg',
      'description': 'Trip to San Francisco with friends',
      'photoTakenTime': {'timestamp': '1577836800', 'formatted': 'Jan 1, 2020'},
    };
    File('${media.path}.json').writeAsStringSync(jsonEncode(sidecar));

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 1);
    expect(photos.first.dateTaken, isNotNull);
    final utc = photos.first.dateTaken!.toUtc();
    expect(utc.year, 2020);
    expect(utc.month, 1);
    expect(utc.day, 1);
    expect(photos.first.takeoutDescription,
        'Trip to San Francisco with friends');
  });

  test('rejects a sidecar whose title does not match the file', () async {
    final media = File(p.join(root.path, 'PXL_20200101.jpg'));
    media.createSync();

    final sidecar = {
      'title': 'some_other_file.jpg',
      'photoTakenTime': {'timestamp': '1577836800'},
    };
    File('${media.path}.json').writeAsStringSync(jsonEncode(sidecar));

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 1);
    expect(photos.first.dateTaken, isNull);
  });

  test('prefers EXIF date over sidecar date', () async {
    // Minimal JPEG with an EXIF DateTimeOriginal header.
    final exif = _buildExifDateJpeg('2019:05:14 18:30:00');
    final media = File(p.join(root.path, 'photo.jpg'));
    media.writeAsBytesSync(exif);

    final sidecar = {
      'title': 'photo.jpg',
      'photoTakenTime': {'timestamp': '1577836800'},
    };
    File('${media.path}.json').writeAsStringSync(jsonEncode(sidecar));

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 1);
    final utc = photos.first.dateTaken!.toUtc();
    expect(utc.year, 2019);
  });

  test('ignores json sidecars and missing ones', () async {
    File(p.join(root.path, 'plain.png')).createSync();
    File(p.join(root.path, 'broken.jpg.json')).writeAsStringSync('{nope');

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 1);
    expect(photos.first.dateTaken, isNull);
    expect(photos.first.takeoutDescription, isNull);
  });
}

List<int> _buildExifDateJpeg(String dateTime) {
  // TIFF (little-endian) for IFD0 with one entry pointing to an Exif sub-IFD,
  // which holds DateTimeOriginal (0x9003, ASCII "YYYY:MM:DD HH:MM:SS").
  const ascii = 2; // ASCII
  const long = 4; // LONG

  // IFD0 entry: tag 0x8769 (ExifIFD pointer), type LONG, count 1.
  final ifd0Entries = Uint8List(12);
  putU16(ifd0Entries, 0, 0x8769, little: true);
  putU16(ifd0Entries, 2, long, little: true);
  putU32(ifd0Entries, 4, 1, little: true);
  // Offset (from TIFF header start) where Exif sub-IFD begins.
  final ifd0Size = 2 + 12 + 4; // count + 1 entry + next offset
  putU32(ifd0Entries, 8, 8 + ifd0Size, little: true);

  final dateBytes = asciiBytes(dateTime);
  // Value offsets in the `*_data` field are relative to the TIFF header start.
  final tiffHeaderSize = 8; // "II" + magic + IFD0 offset
  final exifIfdSize = 2 + 12 + 4; // count + 1 entry + next offset
  final dateDataOffset = tiffHeaderSize + ifd0Size + exifIfdSize;
  final exifEntry = Uint8List(12);
  putU16(exifEntry, 0, 0x9003, little: true);
  putU16(exifEntry, 2, ascii, little: true);
  putU32(exifEntry, 4, dateBytes.length, little: true);
  putU32(exifEntry, 8, dateDataOffset, little: true);

  final tiff = BytesBuilder();
  tiff.add(Uint8List.fromList([0x49, 0x49, 0x2A, 0x00])); // II, 42
  final ifd0Offset = Uint8List(4)..buffer.asByteData().setUint32(0, 8, Endian.little);
  tiff.add(ifd0Offset);
  // IFD0 @ offset 8: entry count
  tiff.add(Uint8List(2)..buffer.asByteData().setUint16(0, 1, Endian.little));
  tiff.add(ifd0Entries);
  tiff.add(Uint8List(4)); // next IFD offset = 0
  // ExifIFD @ tiffSize
  tiff.add(Uint8List(2)..buffer.asByteData().setUint16(0, 1, Endian.little));
  tiff.add(exifEntry);
  tiff.add(Uint8List(4)); // next IFD = 0
  tiff.add(dateBytes);
  tiff.add(Uint8List.fromList([0x00]));
  final tiffData = tiff.toBytes();

  // APP1 segment = 0xFFE1, len, "Exif\0\0", TIFF
  final app1 = BytesBuilder();
  app1.add(Uint8List.fromList([0xFF, 0xE1]));
  final payload = BytesBuilder();
  payload.add(asciiBytes('Exif'));
  payload.add(Uint8List.fromList([0x00, 0x00]));
  payload.add(tiffData);
  final payBytes = payload.toBytes();
  final lenBytes = Uint8List(2)
    ..buffer.asByteData().setUint16(0, payBytes.length + 2, Endian.big);
  app1.add(lenBytes);
  app1.add(payBytes);

  final jpeg = BytesBuilder();
  jpeg.add(Uint8List.fromList([0xFF, 0xD8])); // SOI
  jpeg.add(app1.toBytes());
  jpeg.add(Uint8List.fromList([0xFF, 0xD9])); // EOI
  return jpeg.toBytes();
}

void putU16(Uint8List b, int off, int v, {required bool little}) {
  if (little) {
    b[off] = v & 0xFF;
    b[off + 1] = (v >> 8) & 0xFF;
  } else {
    b[off] = (v >> 8) & 0xFF;
    b[off + 1] = v & 0xFF;
  }
}

void putU32(Uint8List b, int off, int v, {required bool little}) {
  for (var i = 0; i < 4; i++) {
    b[off + i] = little ? (v >> (8 * i)) & 0xFF : (v >> (8 * (3 - i))) & 0xFF;
  }
}

List<int> asciiBytes(String s) => s.codeUnits;