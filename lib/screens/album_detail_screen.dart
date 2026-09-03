import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../widgets/zoom_slider.dart';
import 'photo_grid.dart';

class AlbumDetailScreen extends StatelessWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();
    final photos = provider.getPhotosForAlbum(album.path);
    final sorted = List<PhotoItem>.from(photos)
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final sections = provider.buildDateSections(sorted);
    final columns = provider.columnsForZoom(MediaQuery.of(context).size.width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          album.name.split(Platform.pathSeparator).last.isEmpty
              ? 'Photos'
              : album.name.split(Platform.pathSeparator).last,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${sorted.length} items',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                ZoomSlider(provider: provider),
              ],
            ),
          ),
          Expanded(
            child: PhotoGrid(
              sections: sections,
              columns: columns,
              squareTiles: provider.useSquareTiles,
              viewerPhotos: sorted,
            ),
          ),
        ],
      ),
    );
  }
}