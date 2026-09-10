import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../widgets/zoom_slider.dart';
import 'photo_grid.dart';
import 'photo_viewer_screen.dart';

class PhotosView extends StatefulWidget {
  const PhotosView({super.key});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  final Set<String> _selected = {};
  bool _selectionMode = false;

  List<PhotoItem> get _selectedPhotos {
    final provider = context.read<GalleryProvider>();
    return provider.photos.where((p) => _selected.contains(p.path)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    final sections = provider.dateSections;
    final columns = provider.columnsForZoom(
        MediaQuery.of(context).size.width);
    final squareTiles = provider.useSquareTiles;

    return Column(
      children: [
        if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
        _Toolbar(
          provider: provider,
          selectionMode: _selectionMode,
          onToggleSelection: _toggleSelectionMode,
          onRefresh: () => _refresh(context, provider),
        ),
        Expanded(
          child: PhotoGrid(
            sections: sections,
            columns: columns,
            squareTiles: squareTiles,
            selectedPaths: _selected,
            onPhotoTap: _selectionMode ? _toggleSelect : _openViewer,
            onPhotoLongPress: _enterSelection,
            viewerPhotos: provider.visiblePhotos,
          ),
        ),
        if (_selectionMode) _buildSelectionBar(context, provider),
      ],
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selected.clear();
    });
  }

  Future<void> _refresh(
      BuildContext context, GalleryProvider provider) async {
    await provider.rescan();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Library refreshed — ${provider.photos.length} items')),
    );
  }

  void _selectAll(GalleryProvider provider) {
    setState(() {
      if (_selected.length == provider.visiblePhotos.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(provider.visiblePhotos.map((p) => p.path));
      }
    });
  }

  void _enterSelection(PhotoItem photo) {
    setState(() {
      _selectionMode = true;
      _selected.add(photo.path);
    });
  }

  void _toggleSelect(PhotoItem photo) {
    setState(() {
      if (_selected.contains(photo.path)) {
        _selected.remove(photo.path);
      } else {
        _selected.add(photo.path);
      }
    });
  }

  void _openViewer(PhotoItem photo) {
    final provider = context.read<GalleryProvider>();
    final source = provider.visiblePhotos;
    final index = source.indexWhere((p) => p.path == photo.path);
    if (index < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photos: source, initialIndex: index),
      ),
    );
  }

  void _clearSelection() => setState(() {
        _selected.clear();
        _selectionMode = false;
      });

  Widget _buildSelectionBar(BuildContext context, GalleryProvider provider) {
    final allFavorite = _selectedPhotos.isNotEmpty &&
        _selectedPhotos.every((p) => p.isFavorite);

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.close),
                label: Text('${_selected.length}'),
                onPressed: _clearSelection,
              ),
              TextButton(
                onPressed: () => _selectAll(provider),
                child: Text(
                  _selected.length == provider.visiblePhotos.length
                      ? 'Deselect all'
                      : 'Select all',
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                    allFavorite ? Icons.favorite : Icons.favorite_border),
                color: allFavorite ? Colors.redAccent : null,
                tooltip: 'Toggle favorite',
                onPressed: () async {
                  await provider.setFavorites(_selectedPhotos, !allFavorite);
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download copies',
                onPressed: () => _downloadSelected(context, provider),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_move_outline),
                tooltip: 'Move to album',
                onPressed: () => _moveToAlbum(context, provider),
              ),
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: 'Add to collection',
                onPressed: () => _addToVirtualAlbum(context, provider),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share',
                onPressed: () => _shareSelected(),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _deleteSelected(context, provider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToVirtualAlbum(
      BuildContext context, GalleryProvider provider) async {
    final photos = _selectedPhotos;
    if (photos.isEmpty) return;
    final albums = provider.virtualAlbums;

    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Add to collection'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('New collection…'),
                onTap: () => Navigator.of(context).pop('__new__'),
              ),
              for (final album in albums)
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text('${album['name']} (${album['count']})'),
                  onTap: () => Navigator.of(context).pop(album['id']),
                ),
            ],
          ),
        );
      },
    );

    if (choice == null || !context.mounted) return;

    if (choice == '__new__') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('New collection'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Collection name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) return;
      final id = await provider.createVirtualAlbum(name);
      if (id < 0) return;
      await provider.addToVirtualAlbum(id, photos);
    } else {
      await provider.addToVirtualAlbum(choice as int, photos);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to collection')),
      );
    }
  }

  Future<void> _downloadSelected(
      BuildContext context, GalleryProvider provider) async {
    if (_selectedPhotos.isEmpty) return;
    final count = await provider.exportPhotos(_selectedPhotos);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded $count file(s) to Downloads')),
    );
  }

  Future<void> _shareSelected() async {
    final files = _selectedPhotos.map((p) => XFile(p.path)).toList();
    try {
      await Share.shareXFiles(files);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing is not available here')),
        );
      }
    }
  }

  Future<void> _deleteSelected(
      BuildContext context, GalleryProvider provider) async {
    final count = _selectedPhotos.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete photos?'),
          content: Text('This will permanently delete $count photo(s).'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await provider.deletePhotos(_selectedPhotos);
    _clearSelection();
  }

  Future<void> _moveToAlbum(
      BuildContext context, GalleryProvider provider) async {
    final albums = provider.albums.map((a) => a.path).toList();

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('New album'),
                onTap: () => Navigator.of(context).pop('__new__'),
              ),
              const Divider(height: 1),
              for (final album in albums)
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(album.isEmpty ? 'Photos' : album),
                  onTap: () => Navigator.of(context).pop(album),
                ),
            ],
          ),
        );
      },
    );

    if (choice == null) return;
    if (!context.mounted) return;

    String target = choice;
    if (choice == '__new__') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('New album'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Album name'),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) return;
      target = name.trim();
    }

    final moved = await provider.movePhotosToAlbum(_selectedPhotos, target);
    _clearSelection();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved $moved photo(s)')),
      );
    }
  }
}

class _Toolbar extends StatelessWidget {
  final GalleryProvider provider;
  final bool selectionMode;
  final VoidCallback onToggleSelection;
  final VoidCallback onRefresh;
  const _Toolbar({
    required this.provider,
    required this.selectionMode,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          if (screenW > 500)
            Text(
              '${provider.visiblePhotos.length} items',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Spacer(),
          ZoomSlider(provider: provider),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Rescan for new files',
            onPressed: onRefresh,
          ),
          IconButton(
            icon: Icon(
              selectionMode ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
            ),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: selectionMode ? 'Exit selection' : 'Select',
            onPressed: onToggleSelection,
          ),
          const SizedBox(width: 2),
          _filterChip(
            context,
            label: 'Favorites',
            icon: Icons.favorite,
            selected: provider.showFavoritesOnly,
            onSelected: (v) => provider.toggleFavoritesOnly(v),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<SortField>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: 'Sort',
            onSelected: (field) {
              final order = provider.sortMode.field == field &&
                      provider.sortMode.order == SortOrder.descending
                  ? SortOrder.ascending
                  : SortOrder.descending;
              provider.setSort(field, order);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: SortField.dateModified,
                child: Text('Date modified'),
              ),
              const PopupMenuItem(
                value: SortField.name,
                child: Text('Name'),
              ),
              const PopupMenuItem(
                value: SortField.size,
                child: Text('Size'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      padding: EdgeInsets.zero,
      avatar: Icon(icon, size: 16, color: selected ? Colors.redAccent : null),
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}