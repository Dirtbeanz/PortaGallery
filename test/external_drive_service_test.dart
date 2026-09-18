import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/external_drive_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('drive_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('subfolders lists visible directories sorted and skips hidden', () async {
    Directory(p.join(root.path, 'zeta')).createSync();
    Directory(p.join(root.path, 'Alpha')).createSync();
    Directory(p.join(root.path, '.hidden')).createSync();
    Directory(p.join(root.path, 'Android')).createSync();
    File(p.join(root.path, 'photo.jpg')).createSync();

    final folders = await ExternalDriveService.subfolders(root.path);

    expect(folders, [
      p.join(root.path, 'Alpha'),
      p.join(root.path, 'zeta'),
    ]);
  });

  test('isReadable handles empty, populated, and missing paths', () async {
    final empty = Directory(p.join(root.path, 'empty'))..createSync();
    expect(await ExternalDriveService.isReadable(empty.path), isTrue);

    File(p.join(root.path, 'one.jpg')).createSync();
    expect(await ExternalDriveService.isReadable(root.path), isTrue);

    expect(
      await ExternalDriveService.isReadable(p.join(root.path, 'missing')),
      isFalse,
    );
  });
}
