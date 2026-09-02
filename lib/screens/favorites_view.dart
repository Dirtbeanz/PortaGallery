import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_provider.dart';
import 'photo_grid.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();
    final favorites = provider.favorites;

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_outline, size: 72, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No favorites yet'),
            const SizedBox(height: 8),
            Text(
              'Tap the heart icon on any photo to add it here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final sections = [
      (header: 'Favorites', photos: favorites),
    ];

    return PhotoGrid(
      sections: sections,
      columns: 4,
      squareTiles: true,
    );
  }
}