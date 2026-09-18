import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../services/duplicate_service.dart';

class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  List<List<PhotoItem>> _groups = [];
  final Set<String> _selected = {};
  bool _scanning = false;
  int _scanned = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final provider = context.read<GalleryProvider>();
    setState(() {
      _scanning = true;
      _groups = [];
      _selected.clear();
      _scanned = 0;
      _total = 0;
    });
    final groups = await DuplicateService.findDuplicates(
      List<PhotoItem>.of(provider.photos),
      onProgress: (scanned, total) {
        if (!mounted) return;
        setState(() {
          _scanned = scanned;
          _total = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _scanning = false;
      for (final group in groups) {
        for (var i = 1; i < group.length; i++) {
          _selected.add(group[i].path);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_scanning ? 'Finding duplicates' : 'Duplicates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                        'Move ${_selected.length} selected to trash'),
                    onPressed: _moveSelectedToTrash,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _total == 0 ? null : _scanned / _total,
            ),
            const SizedBox(height: 16),
            Text(_total == 0
                ? 'Grouping files by size…'
                : 'Comparing $_scanned / $_total files…'),
          ],
        ),
      );
    }
    if (_groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text('No duplicates found'),
          ],
        ),
      );
    }
    final provider = context.read<GalleryProvider>();
    return ListView.builder(
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  '${group.length} copies · ${group.first.sizeLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final photo in group)
                _DuplicateTile(
                  photo: photo,
                  thumbPath: provider.thumbPathOrNull(photo),
                  selected: _selected.contains(photo.path),
                  onToggle: () => setState(() {
                    if (_selected.contains(photo.path)) {
                      _selected.remove(photo.path);
                    } else {
                      _selected.add(photo.path);
                    }
                  }),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _moveSelectedToTrash() async {
    final provider = context.read<GalleryProvider>();
    final photos = [
      for (final group in _groups)
        for (final photo in group)
          if (_selected.contains(photo.path)) photo,
    ];
    if (photos.isEmpty) return;
    final count = await provider.moveToTrash(photos);
    if (!mounted) return;
    final remaining = <List<PhotoItem>>[];
    for (final group in _groups) {
      final kept = group
          .where((photo) => !_selected.contains(photo.path))
          .toList();
      if (kept.length > 1) remaining.add(kept);
    }
    setState(() {
      _groups = remaining;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved $count item(s) to trash')),
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  final PhotoItem photo;
  final String? thumbPath;
  final bool selected;
  final VoidCallback onToggle;

  const _DuplicateTile({
    required this.photo,
    required this.thumbPath,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: thumbPath != null
            ? Image.file(
                File(thumbPath!),
                fit: BoxFit.cover,
                cacheWidth: 100,
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.broken_image_outlined),
              )
            : const Icon(Icons.image_outlined),
      ),
      title: Text(photo.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        photo.album.isEmpty ? 'Photos' : photo.album,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Checkbox(value: selected, onChanged: (_) => onToggle()),
      onTap: onToggle,
    );
  }
}
