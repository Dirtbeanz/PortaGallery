import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:photo_gallery/models/photo_item.dart';
import 'package:photo_gallery/providers/gallery_provider.dart';
import 'package:photo_gallery/screens/photo_grid.dart';

class RecordingGalleryProvider extends GalleryProvider {
  final requestedPaths = <String>{};

  @override
  void requestThumbnails(List<PhotoItem> photos) {
    requestedPaths.addAll(photos.map((photo) => photo.path));
  }

  @override
  String? thumbPathOrNull(PhotoItem photo) => null;

  @override
  double getAspectRatio(PhotoItem photo) => photo.aspectRatio;
}

void main() {
  testWidgets('all zooms keep equal row heights and natural tile ratios',
      (tester) async {
    final provider = RecordingGalleryProvider();
    final photos = List.generate(12, (index) => PhotoItem(
      path: '/fixture/$index.mp4', name: '$index.mp4', album: '',
      sizeBytes: 1, modifiedAt: DateTime(2026), isVideo: true,
      aspectRatio: index.isEven ? 1.5 : 0.5,
    ));
    var previousHeight = 0.0;
    try {
      for (final width in [400.0, 1000.0]) {
        await tester.binding.setSurfaceSize(Size(width, 700));
        previousHeight = 0;
        for (var zoom = 0; zoom < 4; zoom++) {
          provider.setZoom(zoom);
          final height = provider.rowHeightForZoom();
          expect(height, greaterThan(previousHeight));
          previousHeight = height;
          await tester.pumpWidget(ChangeNotifierProvider<GalleryProvider>.value(
            value: provider,
            child: MaterialApp(home: Scaffold(body: PhotoGrid(
              sections: [(header: 'Photos', photos: photos)],
              targetRowHeight: height,
            ))),
          ));
          await tester.pump();
          final tiles = tester.widgetList<SizedBox>(find.byType(SizedBox))
              .where((box) => box.child is RepaintBoundary && box.width != null);
          expect(tiles, isNotEmpty);
          final available = width - 4;
          final wide = math.min(1.5 * height, available);
          final narrow = math.min(0.5 * height, available);
          for (final tile in tiles) {
            expect(tile.height, height);
            expect(
              tile.width,
              anyOf(closeTo(wide, 0.001), closeTo(narrow, 0.001)),
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      provider.dispose();
    }
  });
  testWidgets('missing image thumbnails never decode originals', (tester) async {
    final provider = RecordingGalleryProvider();
    final photo = PhotoItem(
      path: '/fixture/original.jpg',
      name: 'original.jpg',
      album: '',
      sizeBytes: 25000000,
      modifiedAt: DateTime(2026),
      isVideo: false,
    );
    PhotoItem? tapped;
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider<GalleryProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: PhotoGrid(
                sections: [(header: 'Photos', photos: [photo])],
                targetRowHeight: 120,
                onPhotoTap: (photo) => tapped = photo,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(provider.requestedPaths, contains(photo.path));
      await tester.tap(find.byIcon(Icons.photo_outlined));
      expect(tapped, same(photo));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    }
  });

  testWidgets('large timeline only requests nearby thumbnails', (tester) async {
    final provider = RecordingGalleryProvider();
    final sections = List.generate(2000, (section) {
      return (
        header: 'Day $section',
        photos: List.generate(9, (index) => PhotoItem(
          path: '/fixture/$section/$index.mp4',
          name: '$index.mp4',
          album: '',
          sizeBytes: 1,
          modifiedAt: DateTime(2026, 1, 1).subtract(Duration(days: section)),
          isVideo: true,
        )),
      );
    });
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider<GalleryProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: PhotoGrid(
                sections: sections,
                targetRowHeight: 120,
                onPhotoTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(provider.requestedPaths, isNotEmpty);
      expect(provider.requestedPaths.length, lessThan(100));
      expect(provider.requestedPaths, isNot(contains('/fixture/1999/0.mp4')));

      final initial = Set<String>.of(provider.requestedPaths);
      provider.requestedPaths.clear();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(provider.requestedPaths.difference(initial), isNotEmpty);
      expect(provider.requestedPaths.length, lessThan(150));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    }
  });
}
