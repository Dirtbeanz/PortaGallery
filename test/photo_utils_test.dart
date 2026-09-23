import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_gallery/services/photo_service.dart';
import 'package:photo_gallery/utils/date_labels.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utils_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('uniqueTargetPath avoids collisions and keeps free names', () {
    File(p.join(root.path, 'a.jpg')).createSync();
    File(p.join(root.path, 'a_1.jpg')).createSync();

    expect(
      p.basename(PhotoService.uniqueTargetPath(root.path, 'a.jpg')),
      'a_2.jpg',
    );
    expect(
      p.basename(PhotoService.uniqueTargetPath(root.path, 'b.jpg')),
      'b.jpg',
    );
  });

  test('uniqueTargetPath can exclude the source path', () {
    final existing = File(p.join(root.path, 'a.jpg'))..createSync();
    final target = PhotoService.uniqueTargetPath(root.path, 'a.jpg',
        excludePath: existing.path);
    expect(target, existing.path);
  });

  test('date labels include weekday and full month names', () {
    expect(monthYearLabel(2025, 9), 'September 2025');
    expect(daySectionLabel(2026, 9, 18), 'Friday, September 18, 2026');
    expect(formatDateTime(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
  });
}
