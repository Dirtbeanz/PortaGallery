import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/photo_item.dart';
import '../models/photo_metadata.dart';
import '../providers/gallery_provider.dart';
import '../services/metadata_service.dart';
import '../widgets/notes_editor.dart';
import '../widgets/video_player_view.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<PhotoItem> photos;
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final List<PhotoItem> _photos = List.of(widget.photos);
  late int _index = widget.initialIndex;
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  PhotoItem get _current => _photos[_index];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    if (_photos.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${_photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _current.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _current.isFavorite ? Colors.redAccent : Colors.white,
            ),
            tooltip: 'Favorite',
            onPressed: () => provider.toggleFavorite(_current),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download a copy',
            onPressed: () => _download(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () => _share(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => _onMenu(v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'details', child: Text('Details')),
              PopupMenuItem(value: 'notes', child: Text('Tags & comment')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              pageController: _controller,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              builder: (context, index) {
                final photo = _photos[index];
                if (photo.isVideo) {
                  return PhotoViewGalleryPageOptions.customChild(
                    child: VideoPlayerView(file: File(photo.path)),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                  );
                }
                return PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(File(photo.path)),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  heroAttributes:
                      PhotoViewHeroAttributes(tag: 'photo_${photo.path}_$index'),
                  errorBuilder: (context, error, stack) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 64),
                  ),
                );
              },
            ),
            if (_index > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: _NavButton(
                  icon: Icons.chevron_left,
                  onPressed: () => _goTo(_index - 1),
                ),
              ),
            if (_index < _photos.length - 1)
              Align(
                alignment: Alignment.centerRight,
                child: _NavButton(
                  icon: Icons.chevron_right,
                  onPressed: () => _goTo(_index + 1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_index > 0) _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_index < _photos.length - 1) _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _goTo(int index) {
    if (index < 0 || index >= _photos.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _onMenu(String value) {
    switch (value) {
      case 'details':
        _showInfo(context);
        break;
      case 'notes':
        showNotesEditor(context, _current);
        break;
      case 'rename':
        _rename(context);
        break;
      case 'delete':
        _delete(context);
        break;
    }
  }

  Future<void> _download(BuildContext context) async {
    final provider = context.read<GalleryProvider>();

    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }

    final base = dir?.path ?? p.dirname(_current.path);
    final target = p.join(base, _current.name);

    final saved = await provider.exportPhoto(_current, target, overwrite: true);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved != null ? 'Saved to $saved' : 'Could not download file',
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      await Share.shareXFiles([XFile(_current.path)]);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing is not available here')),
      );
    }
  }

  Future<void> _rename(BuildContext context) async {
    final provider = context.read<GalleryProvider>();
    final controller = TextEditingController(text: p.basenameWithoutExtension(_current.name));

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              suffixText: _current.extension,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (newName == null) return;
    final ok = await provider.renamePhoto(_current, newName);
    if (ok) {
      _photos.removeAt(_index);
      if (_photos.isEmpty) {
        if (context.mounted) Navigator.of(context).pop();
      }
      if (_index >= _photos.length) _index = _photos.length - 1;
      setState(() {});
    }
  }

  Future<void> _delete(BuildContext context) async {
    final provider = context.read<GalleryProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete photo?'),
          content: Text('This will permanently delete "${_current.name}".'),
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

    await provider.deletePhoto(_current);
    _photos.removeAt(_index);

    if (_photos.isEmpty) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    if (_index >= _photos.length) _index = _photos.length - 1;
    if (mounted) setState(() {});
  }

  void _showInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MetadataSheet(photo: _current),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
  }
}

class _MetadataSheet extends StatefulWidget {
  final PhotoItem photo;

  const _MetadataSheet({required this.photo});

  @override
  State<_MetadataSheet> createState() => _MetadataSheetState();
}

class _MetadataSheetState extends State<_MetadataSheet> {
  Future<PhotoMetadata>? _future;

  @override
  void initState() {
    super.initState();
    _future = MetadataService.readMetadata(widget.photo.path);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(widget.photo.name,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(_sizeDateLine()),
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<PhotoMetadata>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final meta = snapshot.data ?? const PhotoMetadata();
                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _buildRows(context, meta),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _sizeDateLine() {
    return '${_formatDate(widget.photo.modifiedAt)} · ${widget.photo.sizeLabel}';
  }

  List<Widget> _buildRows(BuildContext context, PhotoMetadata meta) {
    final rows = <Widget>[
      _row(context, Icons.photo_size_select_large, 'Dimensions',
          meta.dimensionsLabel),
      _row(context, Icons.calendar_today, 'Modified',
          _formatDate(widget.photo.modifiedAt)),
    ];

    if (meta.dateTaken != null) {
      rows.add(_row(context, Icons.photo_camera, 'Date taken',
          _formatDate(meta.dateTaken!)));
    }
    if (meta.cameraMake != null || meta.cameraModel != null) {
      final camera = [meta.cameraMake, meta.cameraModel]
          .whereType<String>()
          .join(' ');
      rows.add(_row(context, Icons.camera_alt_outlined, 'Camera', camera));
    }
    if (meta.iso != null) {
      rows.add(_row(context, Icons.iso, 'ISO', meta.iso!));
    }
    if (meta.aperture != null) {
      rows.add(_row(context, Icons.camera, 'Aperture', meta.aperture!));
    }
    if (meta.shutterSpeed != null) {
      rows.add(_row(context, Icons.timer_outlined, 'Shutter', meta.shutterSpeed!));
    }
    if (meta.focalLength != null) {
      rows.add(_row(
          context, Icons.center_focus_strong, 'Focal length', meta.focalLength!));
    }
    if (meta.gpsLatitude != null && meta.gpsLongitude != null) {
      rows.add(_row(
        context,
        Icons.location_on,
        'Location',
        '${meta.gpsLatitude!.toStringAsFixed(5)}, '
            '${meta.gpsLongitude!.toStringAsFixed(5)}',
      ));
    }

    rows.add(_row(
        context, Icons.folder, 'Album', widget.photo.album.isEmpty ? 'Photos' : widget.photo.album));

    final notes = context.read<GalleryProvider>().getNotes(widget.photo.path);
    if (notes.tags.isNotEmpty) {
      rows.add(_tagsRow(context, notes.tags));
    }
    if (notes.comment.isNotEmpty) {
      rows.add(_row(context, Icons.comment_outlined, 'Comment', notes.comment));
    }

    rows.add(_row(context, Icons.link, 'Path', widget.photo.path));

    return rows;
  }

  Widget _tagsRow(BuildContext context, List<String> tags) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tag, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text('Tags',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;

    final time = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    if (diff == 0) return 'Today at $time';
    if (diff == 1) return 'Yesterday at $time';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $time';
  }
}