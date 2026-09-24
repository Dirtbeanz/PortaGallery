import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:photo_gallery/models/photo_item.dart';
import 'package:photo_gallery/providers/gallery_provider.dart';
import 'package:photo_gallery/screens/photo_grid.dart';

class _NoThumbProvider extends GalleryProvider {
  @override
  void requestThumbnails(List<PhotoItem> photos) {}

  @override
  String? thumbPathOrNull(PhotoItem photo) => null;

  @override
  double getAspectRatio(PhotoItem photo) => photo.aspectRatio;
}

void main() {
  testWidgets('zooming keeps the same region of the timeline visible',
      (tester) async {
    final provider = _NoThumbProvider();
    bool first = true;
    final sections = List.generate(100, (s) {
      if (first) {
        first = false;
      }
      return (
        header: 'Day $s',
        photos: [
          PhotoItem(
            path: '/fixture/$s.jpg',
            name: '$s.jpg',
            album: '',
            sizeBytes: 1,
            modifiedAt: DateTime(2026),
            isVideo: true,
            aspectRatio: 1.0,
          ),
        ],
      );
    });

    Future<void> pumpGrid(double rowHeight) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<GalleryProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: PhotoGrid(
                sections: sections,
                targetRowHeight: rowHeight,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    try {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await pumpGrid(200);

      final scrollView =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView));
      final controller = scrollView.controller!;
      // Scroll so section 50's header sits just above the viewport top.
      controller.jumpTo(50 * (46 + 200 + 2) + 150);
      await tester.pump();

      final before = tester.getTopLeft(find.text('Day 50').first).dy;

      // Zoom in: rows get smaller.
      await pumpGrid(80);
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.text('Day 50').first).dy;
      // The anchored photo should stay near where it was, rather than the
      // list jumping to the top.
      expect((after - before).abs(), lessThan(120));
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      provider.dispose();
    }
  });
}