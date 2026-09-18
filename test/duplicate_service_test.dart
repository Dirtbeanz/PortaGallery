import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/models/photo_item.dart';
import 'package:photo_gallery/services/duplicate_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dup_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  PhotoItem item(String name, int size) => PhotoItem(
        path: p.join(root.path, name),
        name: name,
        album: '',
        sizeBytes: size,
        modifiedAt: DateTime(2026),
        isVideo: false,
      );

  test('groups identical files and ignores unique ones', () async {
    final content = List<int>.generate(1000, (i) => i % 256);
    File(p.join(root.path, 'a.jpg')).writeAsBytesSync(content);
    File(p.join(root.path, 'b.jpg')).writeAsBytesSync(content);
    File(p.join(root.path, 'unique.jpg'))
        .writeAsBytesSync(List<int>.generate(1000, (i) => (i * 7) % 256));

    final groups = await DuplicateService.findDuplicates([
      item('a.jpg', 1000),
      item('b.jpg', 1000),
      item('unique.jpg', 1000),
    ]);

    expect(groups.length, 1);
    expect(groups.first.map((photo) => photo.name).toSet(), {'a.jpg', 'b.jpg'});
  });

  test('same size but different content is not a duplicate', () async {
    File(p.join(root.path, 'x.jpg'))
        .writeAsBytesSync(List<int>.filled(500, 1));
    File(p.join(root.path, 'y.jpg'))
        .writeAsBytesSync(List<int>.filled(500, 2));

    final groups = await DuplicateService.findDuplicates([
      item('x.jpg', 500),
      item('y.jpg', 500),
    ]);

    expect(groups, isEmpty);
  });

  test('reports no duplicates when all sizes differ', () async {
    File(p.join(root.path, 'one.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(root.path, 'two.jpg')).writeAsBytesSync([1, 2, 3, 4]);

    final groups = await DuplicateService.findDuplicates([
      item('one.jpg', 3),
      item('two.jpg', 4),
    ]);

    expect(groups, isEmpty);
  });
}
