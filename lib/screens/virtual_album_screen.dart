import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import 'photo_grid.dart';
import 'photo_viewer_screen.dart';

class VirtualAlbumScreen extends StatefulWidget {
  final int albumId;
  final String name;

  const VirtualAlbumScreen({
    super.key,
    required this.albumId,
    required this.name,
  });

  @override
  State<VirtualAlbumScreen> createState() => _VirtualAlbumScreenState();
}

class _VirtualAlbumScreenState extends State<VirtualAlbumScreen> {
  List<PhotoItem> _items = [];
  final Set<String> _selected = {};
  bool _selectionMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<GalleryProvider>();
    final paths = await provider.getVirtualAlbumItems(widget.albumId);
    final items = provider.photos
        .where((p) => paths.contains(p.path))
        .toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          if (!_selectionMode && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check_box_outline_blank),
              tooltip: 'Select',
              onPressed: () => setState(() => _selectionMode = true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('This collection is empty'))
              : PhotoGrid(
                  sections: [ (header: '', photos: _items) ],
                  columns: provider.columnsForZoom(
                      MediaQuery.of(context).size.width),
                  squareTiles: provider.useSquareTiles,
                  selectedPaths: _selected,
                  viewerPhotos: _items,
                  onPhotoTap: _selectionMode ? _toggle : _open,
                  onPhotoLongPress: (p) => setState(() {
                    _selectionMode = true;
                    _selected.add(p.path);
                  }),
                ),
      bottomNavigationBar: _selectionMode
          ? Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.close),
                        label: Text('${_selected.length}'),
                        onPressed: () => setState(() {
                          _selectionMode = false;
                          _selected.clear();
                        }),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remove from collection',
                        onPressed: () async {
                          final selected = _items
                              .where((p) => _selected.contains(p.path))
                              .toList();
                          await provider.removeFromVirtualAlbum(
                              widget.albumId, selected);
                          if (mounted) {
                            setState(() {
                              _selectionMode = false;
                              _selected.clear();
                            });
                          }
                          await _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  void _toggle(PhotoItem photo) {
    setState(() {
      if (_selected.contains(photo.path)) {
        _selected.remove(photo.path);
      } else {
        _selected.add(photo.path);
      }
    });
  }

  void _open(PhotoItem photo) {
    final index = _items.indexWhere((p) => p.path == photo.path);
    if (index < 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewerScreen(photos: _items, initialIndex: index),
      ),
    );
  }
}