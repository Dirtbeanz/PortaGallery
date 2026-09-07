import 'dart:convert';
import 'dart:io';

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
      'title': 'Golden Gate',
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

  test('ignores json sidecars and missing ones', () async {
    File(p.join(root.path, 'plain.png')).createSync();
    File(p.join(root.path, 'broken.jpg.json')).writeAsStringSync('{nope');

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 1);
    expect(photos.first.dateTaken, isNull);
    expect(photos.first.takeoutDescription, isNull);
  });
}