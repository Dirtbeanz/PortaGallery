import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import 'album_detail_screen.dart';

class AlbumsView extends StatelessWidget {
  const AlbumsView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final albums = provider.albums;
    if (albums.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text('No albums found'),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _tileExtent(constraints.maxWidth),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.8,
          ),
          padding: const EdgeInsets.all(8),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return _AlbumCard(album: album);
          },
        );
      },
    );
  }

  double _tileExtent(double width) {
    if (width > 1200) return width / 5;
    if (width > 800) return width / 4;
    if (width > 500) return width / 3;
    return width / 2.2;
  }
}

class _AlbumCard extends StatelessWidget {
  final Album album;

  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openAlbum(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            album.coverPath.isEmpty
                ? const ColoredBox(
                    color: Color(0xFF333333),
                    child: Center(
                      child:
                          Icon(Icons.folder, color: Colors.white54, size: 56),
                    ),
                  )
                : Image.file(
                    File(album.coverPath),
                    fit: BoxFit.cover,
                    cacheWidth: 500,
                    errorBuilder: (context, error, stack) => const ColoredBox(
                      color: Color(0xFF333333),
                      child: Center(
                        child: Icon(Icons.folder,
                            color: Colors.white54, size: 56),
                      ),
                    ),
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _albumTitle(album.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    album.photoCount == 0
                        ? 'Empty'
                        : '${album.photoCount} photos',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _albumTitle(String name) {
    final parts = name.split(Platform.pathSeparator);
    return parts.isEmpty ? name : parts.last;
  }

  void _openAlbum(BuildContext context) {
    if (album.photoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This album is empty')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(album: album),
      ),
    );
  }
}