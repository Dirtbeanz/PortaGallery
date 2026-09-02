import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/metadata_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('photo_gallery_meta_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('reads dimensions from a PNG without throwing', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    final file = File(p.join(root.path, 'one.png'));
    await file.writeAsBytes(png);

    final meta = await MetadataService.readMetadata(file.path);

    expect(meta.width, 1);
    expect(meta.height, 1);
  });

  test('returns an empty metadata object for a non-image file', () async {
    final file = File(p.join(root.path, 'note.txt'));
    await file.writeAsString('hello');

    final meta = await MetadataService.readMetadata(file.path);

    expect(meta, isNotNull);
    expect(meta.width, isNull);
    expect(meta.dateTaken, isNull);
  });
}