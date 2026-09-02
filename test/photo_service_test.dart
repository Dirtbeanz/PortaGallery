import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('photo_gallery_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('scans supported images and builds album grouping', () async {
    File(p.join(root.path, 'a.jpg')).createSync();
    File(p.join(root.path, 'b.png')).createSync();
    File(p.join(root.path, 'ignore.txt')).createSync();

    Directory(p.join(root.path, 'Vacation')).createSync();
    File(p.join(root.path, 'Vacation', 'beach.jpg')).createSync();

    Directory(p.join(root.path, '.hidden')).createSync();
    File(p.join(root.path, '.hidden', 'secret.jpg')).createSync();

    final photos = await PhotoService.scanDirectory(root.path);

    expect(photos.length, 3);
    expect(photos.any((p) => p.album == 'Vacation'), isTrue);
    expect(photos.any((p) => p.path.contains('ignore.txt')), isFalse);
    expect(photos.any((p) => p.path.contains('.hidden')), isFalse);
  });

  test('supports extensions and video detection', () {
    expect(PhotoService.isSupported('x.jpg'), isTrue);
    expect(PhotoService.isSupported('x.mp4'), isTrue);
    expect(PhotoService.isSupported('x.HEIC'), isTrue);
    expect(PhotoService.isSupported('x.pdf'), isFalse);
    expect(PhotoService.isVideoPath('x.mp4'), isTrue);
    expect(PhotoService.isVideoPath('x.jpg'), isFalse);
  });
}