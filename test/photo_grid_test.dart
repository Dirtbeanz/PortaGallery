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
                columns: 4,
                squareTiles: true,
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
                columns: 4,
                squareTiles: true,
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
