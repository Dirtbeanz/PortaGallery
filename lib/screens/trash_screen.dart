import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_provider.dart';
import '../utils/date_labels.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();
    final items = provider.trashItems;

    return Scaffold(
      appBar: AppBar(
        title: Text('Trash (${items.length})'),
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restore selected',
              onPressed: () async {
                final selected = items
                    .where((item) => _selected.contains(item.trashedPath))
                    .toList();
                final count = await provider.restoreTrash(selected);
                if (!context.mounted) return;
                setState(_selected.clear);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Restored $count item(s)')),
                );
              },
            ),
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Empty trash',
              onPressed: () => _confirmEmpty(context, provider),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 72, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Trash is empty'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = _selected.contains(item.trashedPath);
                return ListTile(
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    'Deleted ${formatDateTime(item.deletedAt)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => setState(() {
                    if (selected) {
                      _selected.remove(item.trashedPath);
                    } else {
                      _selected.add(item.trashedPath);
                    }
                  }),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () async {
                      final count = await provider.restoreTrash([item]);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(count > 0
                                ? 'Restored ${item.name}'
                                : 'Could not restore ${item.name}')),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmEmpty(
      BuildContext context, GalleryProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text(
            'This permanently deletes ${provider.trashCount} item(s). '
            'This cannot be undone.'),
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
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await provider.emptyTrash();
    if (!context.mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Permanently deleted $count item(s)')),
    );
  }
}
