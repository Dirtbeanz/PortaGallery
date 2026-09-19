import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../services/permission_service.dart';
import 'photo_viewer_screen.dart';

class PhotoGrid extends StatefulWidget {
  final List<({String header, List<PhotoItem> photos})> sections;
  final Set<String> selectedPaths;
  final double targetRowHeight;
  final List<PhotoItem>? viewerPhotos;
  final ValueChanged<PhotoItem>? onPhotoTap;
  final ValueChanged<PhotoItem>? onPhotoLongPress;

  const PhotoGrid({
    super.key,
    required this.sections,
    required this.targetRowHeight,
    this.selectedPaths = const {},
    this.viewerPhotos,
    this.onPhotoTap,
    this.onPhotoLongPress,
  });

  @override
  State<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends State<PhotoGrid> {
  final ScrollController _scrollController = ScrollController();
  Timer? _hideTimer;
  String? _activeLabel;
  bool _showLabel = false;
  List<double> _sectionStarts = [];
  String? _pendingAnchor;
  // Cached justified-row layout, invalidated by content/width/rowHeight changes.
  List<List<_JustifiedRow>>? _layoutCache;
  final List<({int section, int row})> _entries = [];
  double? _layoutWidth;
  double? _layoutRowHeight;
  int? _layoutVersion;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(PhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetRowHeight != widget.targetRowHeight) {
      _invalidateLayout();
      _captureAnchor(oldWidget);
    } else if (!identical(oldWidget.sections, widget.sections)) {
      _invalidateLayout();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _invalidateLayout() {
    _layoutCache = null;
  }

  void _captureAnchor(PhotoGrid oldWidget) {
    if (!_scrollController.hasClients) return;
    if (oldWidget.sections.isEmpty || _sectionStarts.isEmpty) return;
    final offset = _scrollController.offset + 8;
    var lo = 0;
    var hi = _sectionStarts.length - 1;
    var index = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_sectionStarts[mid] <= offset) {
        index = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (index < 0 || index >= oldWidget.sections.length) return;
    final photos = oldWidget.sections[index].photos;
    _pendingAnchor = photos.isNotEmpty ? photos.first.path : null;
  }

  void _restoreAnchor() {
    final anchor = _pendingAnchor;
    if (anchor == null || !_scrollController.hasClients) return;
    _pendingAnchor = null;

    for (var s = 0; s < widget.sections.length; s++) {
      final photos = widget.sections[s].photos;
      if (photos.isEmpty) continue;
      if (photos.first.path == anchor || photos.any((p) => p.path == anchor)) {
        final target = _sectionStarts[s];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.jumpTo(
              target.clamp(0.0, _scrollController.position.maxScrollExtent));
        });
        break;
      }
    }
  }

  void _onScroll() {
    if (_sectionStarts.isEmpty) return;
    final offset = _scrollController.offset + 60;
    // Binary search — the linear scan ran on every scroll frame and got
    // expensive with thousands of day-sections.
    var lo = 0;
    var hi = _sectionStarts.length - 1;
    var index = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_sectionStarts[mid] <= offset) {
        index = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (index >= widget.sections.length) return;
    final label = widget.sections[index].header;
    if (label != _activeLabel || !_showLabel) {
      setState(() {
        _activeLabel = label;
        _showLabel = true;
      });
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _showLabel) setState(() => _showLabel = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      final provider = context.read<GalleryProvider>();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_outlined, size: 72, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No photos here yet'),
              if (Platform.isAndroid && provider.photos.isEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'If your drive is connected, this app may lack storage'
                  ' permission.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Grant access'),
                  onPressed: () async {
                    await PermissionService.requestStorage();
                    if (context.mounted) {
                      await context.read<GalleryProvider>().rescan();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 2.0;
        const hPadding = 2.0;
        final width = constraints.maxWidth;

        // Rebuild layout rows only when content, width, or zoom changed.
        // Previously this recomputed rows for ALL 18k photos on every
        // rebuild (e.g. every batch of generated thumbnails) — the single
        // biggest source of scroll/zoom jank.
        final layoutVersion = context.select<GalleryProvider, int>(
            (provider) => provider.layoutVersion);
        if (_layoutCache == null ||
            _layoutWidth != width ||
            _layoutRowHeight != widget.targetRowHeight ||
            _layoutVersion != layoutVersion) {
          _layoutWidth = width;
          _layoutRowHeight = widget.targetRowHeight;
          _layoutVersion = layoutVersion;
          _layoutCache = [
            for (final section in widget.sections)
              _buildRows(section.photos, width, hPadding, spacing),
          ];
          _entries.clear();
          _sectionStarts = [];
          var offset = 0.0;
          for (var s = 0; s < widget.sections.length; s++) {
            _sectionStarts.add(offset);
            _entries.add((section: s, row: -1));
            offset += 46;
            final rows = _layoutCache![s];
            for (var r = 0; r < rows.length; r++) {
              _entries.add((section: s, row: r));
              offset += rows[r].height + spacing;
            }
          }
        }
        final layout = _layoutCache!;

        if (_pendingAnchor != null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _restoreAnchor());
        }

        return Stack(
          children: [
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              thickness: 10,
              radius: const Radius.circular(10),
              child: CustomScrollView(
                controller: _scrollController,
                cacheExtent: 800,
                slivers: [
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = _entries[index];
                        if (entry.row < 0) {
                          return _DateHeader(
                              label: widget.sections[entry.section].header);
                        }
                        return _buildRow(context,
                            layout[entry.section][entry.row], index,
                            hPadding, spacing);
                      },
                      childCount: _entries.length,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
                ],
              ),
            ),
            if (_showLabel && _activeLabel != null)
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: IgnorePointer(
                  child: Center(
                    child: Material(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Text(
                          _activeLabel!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<_JustifiedRow> _buildRows(
      List<PhotoItem> photos, double width, double hPadding, double spacing) {
    final provider = context.read<GalleryProvider>();
    final availableWidth = width - hPadding * 2;
    final rowHeight = widget.targetRowHeight;
    final rows = <_JustifiedRow>[];
    var currentRow = <_RowItem>[];
    var currentWidth = 0.0;

    for (final photo in photos) {
      final rawRatio = provider.getAspectRatio(photo);
      final ratio = rawRatio.isFinite && rawRatio > 0 ? rawRatio : 1.0;
      final itemWidth = (rowHeight * ratio).clamp(1.0, availableWidth);
      final gap = currentRow.isEmpty ? 0.0 : spacing;
      if (currentRow.isNotEmpty &&
          currentWidth + gap + itemWidth > availableWidth) {
        rows.add(_JustifiedRow(items: currentRow, height: rowHeight));
        currentRow = [];
        currentWidth = 0;
      }
      currentWidth += (currentRow.isEmpty ? 0 : spacing) + itemWidth;
      currentRow.add(_RowItem(photo: photo, width: itemWidth));
    }

    // Last row: don't scale, use natural height.
    if (currentRow.isNotEmpty) {
      rows.add(_JustifiedRow(items: currentRow, height: rowHeight));
    }

    return rows;
  }

  Widget _buildRow(
    BuildContext context,
    _JustifiedRow row,
    int index,
    double hPadding,
    double spacing,
  ) {
    final provider = context.read<GalleryProvider>();
    provider.requestThumbnails(row.items.map((item) => item.photo).toList());
    return Padding(
      padding: EdgeInsets.fromLTRB(hPadding, 0, hPadding, spacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < row.items.length; j++) ...[
            if (j > 0) SizedBox(width: spacing),
            SizedBox(
              width: row.items[j].width,
              height: row.height,
              child: RepaintBoundary(
                child: _PhotoTile(
                  photo: row.items[j].photo,
                  index: index * 10 + j,
                  selected: widget.selectedPaths.contains(row.items[j].photo.path),
                  thumbPath: provider.thumbPathOrNull(row.items[j].photo),
                  onTap: widget.onPhotoTap,
                  onLongPress: widget.onPhotoLongPress,
                  viewerPhotos: widget.viewerPhotos,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JustifiedRow {
  final List<_RowItem> items;
  final double height;
  const _JustifiedRow({required this.items, required this.height});
}

class _RowItem {
  final PhotoItem photo;
  final double width;
  const _RowItem({required this.photo, required this.width});
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
  final String? thumbPath;
  final ValueChanged<PhotoItem>? onTap;
  final ValueChanged<PhotoItem>? onLongPress;
  final List<PhotoItem>? viewerPhotos;

  const _PhotoTile({
    required this.photo,
    required this.index,
    this.selected = false,
    this.thumbPath,
    this.onTap,
    this.onLongPress,
    this.viewerPhotos,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap != null ? onTap!(photo) : _openViewer(context),
      onLongPress: () => onLongPress?.call(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Thumbnail(
              photo: photo,
              thumbPath: thumbPath,
            ),
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
                top: 4,
                right: 4,
                child: Icon(Icons.favorite, color: Colors.redAccent, size: 16),
              ),
            if (photo.isVideo)
              Positioned(
                bottom: 3,
                left: 3,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, color: Colors.white, size: 12),
                      SizedBox(width: 1),
                      Text('VIDEO',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    final provider = context.read<GalleryProvider>();
    final source = viewerPhotos ?? provider.visiblePhotos;
    final startIndex = source.indexWhere((p) => p.path == photo.path);
    if (startIndex < 0) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PhotoViewerScreen(photos: source, initialIndex: startIndex),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PhotoItem photo;
  final String? thumbPath;

  const _Thumbnail({
    required this.photo,
    this.thumbPath,
  });

  @override
  Widget build(BuildContext context) {
    // Consistent cacheWidth across all zoom levels to prevent re-decode.
    const gridCacheWidth = 200;

    if (photo.isVideo) {
      if (thumbPath != null) {
        return Image.file(
          File(thumbPath!),
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.low,
          cacheWidth: gridCacheWidth,
          errorBuilder: (context, error, stack) => _placeholder(),
        );
      }
      return _placeholder();
    }

    if (thumbPath != null) {
      return Image.file(
        File(thumbPath!),
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.low,
        cacheWidth: gridCacheWidth,
        errorBuilder: (context, error, stack) => _fallback(context),
      );
    }

    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2A2A2E),
      child: Center(
        child: Icon(Icons.photo_outlined, color: Colors.white54, size: 28),
      ),
    );
  }

  Widget _placeholder() {
    return const ColoredBox(
      color: Color(0xFF1B1B1F),
      child: Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 20),
      ),
    );
  }
}