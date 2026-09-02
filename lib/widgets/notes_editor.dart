import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../models/photo_notes.dart';
import '../providers/gallery_provider.dart';

Future<void> showNotesEditor(BuildContext context, PhotoItem photo) {
  final provider = context.read<GalleryProvider>();
  final existing = provider.getNotes(photo.path);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NotesEditor(photo: photo, existing: existing),
  );
}

class _NotesEditor extends StatefulWidget {
  final PhotoItem photo;
  final PhotoNotes existing;

  const _NotesEditor({required this.photo, required this.existing});

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final List<String> _tags = List.of(widget.existing.tags);
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing.comment);
  final TextEditingController _tagInput = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.photo.name,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          _buildTags(context),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment',
              hintText: 'Add a note about this photo...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: _save,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTags(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in _tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => setState(() => _tags.remove(tag)),
              ),
            if (_tags.isEmpty)
              Text(
                'No tags yet',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInput,
                decoration: const InputDecoration(
                  labelText: 'Add tag',
                  hintText: 'beach, family, 2024...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.add),
              onPressed: _addTag,
              tooltip: 'Add tag',
            ),
          ],
        ),
      ],
    );
  }

  void _addTag() {
    final value = _tagInput.text.trim();
    if (value.isEmpty) return;
    setState(() {
      for (final part in value.split(',')) {
        final t = part.trim();
        if (t.isNotEmpty && !_tags.contains(t)) _tags.add(t);
      }
      _tagInput.clear();
    });
  }

  Future<void> _save() async {
    final provider = context.read<GalleryProvider>();
    await provider.saveNotes(widget.photo.path, _tags, _comment.text);
    if (mounted) Navigator.of(context).pop();
  }
}