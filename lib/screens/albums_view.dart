import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import 'album_detail_screen.dart';
import 'virtual_album_screen.dart';

class AlbumsView extends StatelessWidget {
  const AlbumsView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final albums = provider.albums;
    final virtualAlbums = provider.virtualAlbums;

    if (albums.isEmpty && virtualAlbums.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (virtualAlbums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Collections',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: _columns(MediaQuery.of(context).size.width),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.4,
            children: [
              for (final album in virtualAlbums)
                _VirtualAlbumCard(album: album),
            ],
          ),
        ],
        if (albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('Folders',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _tileExtent(constraints.maxWidth),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.8,
                ),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return _AlbumCard(album: album);
                },
              );
            },
          ),
        ],
      ],
    );
  }

  int _columns(double width) {
    if (width > 1200) return 5;
    if (width > 800) return 4;
    if (width > 500) return 3;
    return 2;
  }

  double _tileExtent(double width) {
    if (width > 1200) return width / 5;
    if (width > 800) return width / 4;
    if (width > 500) return width / 3;
    return width / 2.2;
  }
}

class _VirtualAlbumCard extends StatelessWidget {
  final Map<String, dynamic> album;

  const _VirtualAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VirtualAlbumScreen(
              albumId: album['id'] as int,
              name: album['name'] as String,
            ),
          ),
        );
      },
      onLongPress: () => _menu(context),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: 10,
              left: 12,
              right: 8,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      album['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '${album['count']}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(Icons.collections_bookmark, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context) {
    final provider = context.read<GalleryProvider>();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.of(context).pop();
                  _rename(context, provider);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete collection'),
                onTap: () {
                  Navigator.of(context).pop();
                  provider.deleteVirtualAlbum(album['id'] as int);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _rename(BuildContext context, GalleryProvider provider) {
    final controller = TextEditingController(text: album['name'] as String);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename collection'),
          content: TextField(
            controller: controller,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                provider.renameVirtualAlbum(
                    album['id'] as int, controller.text);
                Navigator.of(context).pop();
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
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