import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import 'photo_viewer_screen.dart';

class PhotoGrid extends StatelessWidget {
  final List<({String header, List<PhotoItem> photos})> sections;
  final Set<String> selectedPaths;
  final int columns;
  final bool squareTiles;
  final ValueChanged<PhotoItem>? onPhotoTap;
  final ValueChanged<PhotoItem>? onPhotoLongPress;

  const PhotoGrid({
    super.key,
    required this.sections,
    required this.columns,
    required this.squareTiles,
    this.selectedPaths = const {},
    this.onPhotoTap,
    this.onPhotoLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text('No photos here yet'),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 4.0;
        const hPadding = 4.0;
        final width = constraints.maxWidth;
        final colCount = math.max(1, columns);
        final tileWidth =
            (width - hPadding * 2 - (colCount - 1) * spacing) / colCount;

        return CustomScrollView(
          slivers: [
            for (final section in sections) ...[
              SliverToBoxAdapter(child: _DateHeader(label: section.header)),
              _buildSection(
                context,
                section.photos,
                tileWidth,
                colCount,
                spacing,
                hPadding,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    List<PhotoItem> photos,
    double tileWidth,
    int colCount,
    double spacing,
    double hPadding,
  ) {
    final provider = context.read<GalleryProvider>();
    final rows = <List<PhotoItem>>[];
    for (var i = 0; i < photos.length; i += colCount) {
      rows.add(photos.sublist(
          i, math.min(i + colCount, photos.length)));
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final row = rows[index];
            final children = <Widget>[];
            for (var j = 0; j < row.length; j++) {
              if (j > 0) children.add(const SizedBox(width: 4));
              final photo = row[j];
              final height =
                  squareTiles ? tileWidth : tileWidth / provider.getAspectRatio(photo);
              children.add(SizedBox(
                width: tileWidth,
                height: height,
                child: _PhotoTile(
                  photo: photo,
                  index: index * colCount + j,
                  selected: selectedPaths.contains(photo.path),
                  cacheWidth: squareTiles ? 400 : 1000,
                  onTap: onPhotoTap,
                  onLongPress: onPhotoLongPress,
                ),
              ));
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            );
          },
          childCount: rows.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final PhotoItem photo;
  final int index;
  final bool selected;
  final int cacheWidth;
  final ValueChanged<PhotoItem>? onTap;
  final ValueChanged<PhotoItem>? onLongPress;

  const _PhotoTile({
    required this.photo,
    required this.index,
    this.selected = false,
    this.cacheWidth = 400,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'photo_${photo.path}_$index',
      child: GestureDetector(
        onTap: () => onTap != null ? onTap!(photo) : _openViewer(context),
        onLongPress: () => onLongPress?.call(photo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Thumbnail(photo: photo, cacheWidth: cacheWidth),
              if (selected)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.25),
                  ),
                ),
              if (photo.isFavorite && !selected)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    final provider = context.read<GalleryProvider>();
    final source = provider.visiblePhotos;
    final startIndex = source.indexWhere((p) => p.path == photo.path);
    if (startIndex < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          photos: source,
          initialIndex: startIndex,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PhotoItem photo;
  final int cacheWidth;

  const _Thumbnail({required this.photo, this.cacheWidth = 400});

  @override
  Widget build(BuildContext context) {
    if (photo.isVideo) {
      return const ColoredBox(
        color: Color(0xFF1B1B1F),
        child: Center(
          child: Icon(Icons.play_circle_outline,
              color: Colors.white70, size: 24),
        ),
      );
    }

    return Image.file(
      File(photo.path),
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const ColoredBox(color: Color(0xFF2A2A2E));
      },
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: Color(0xFF333333),
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 32),
        ),
      ),
    );
  }
}