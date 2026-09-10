import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../services/permission_service.dart';
import 'photo_viewer_screen.dart';

class PhotoGrid extends StatefulWidget {
  final List<({String header, List<PhotoItem> photos})> sections;
  final Set<String> selectedPaths;
  final int columns;
  final bool squareTiles;
  final List<PhotoItem>? viewerPhotos;
  final ValueChanged<PhotoItem>? onPhotoTap;
  final ValueChanged<PhotoItem>? onPhotoLongPress;

  const PhotoGrid({
    super.key,
    required this.sections,
    required this.columns,
    required this.squareTiles,
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(PhotoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns ||
        oldWidget.squareTiles != widget.squareTiles) {
      _captureAnchor(oldWidget);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _captureAnchor(PhotoGrid oldWidget) {
    if (!_scrollController.hasClients) return;
    if (oldWidget.sections.isEmpty) return;
    final offset = _scrollController.offset;
    for (var i = 0; i < _sectionStarts.length; i++) {
      if (_sectionStarts[i] <= offset + 8) {
        _pendingAnchor = oldWidget.sections[i].photos.isNotEmpty
            ? oldWidget.sections[i].photos.first.path
            : null;
      }
    }
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
    var index = 0;
    for (var i = 0; i < _sectionStarts.length; i++) {
      if (_sectionStarts[i] <= offset) index = i;
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

        // Compute section starts for scroll indicator.
        _sectionStarts = [];
        var acc = 0.0;
        for (final section in widget.sections) {
          _sectionStarts.add(acc);
          acc += 46; // header
          final rows = _buildRows(section.photos, width, hPadding, spacing);
          for (final row in rows) {
            acc += row.height + spacing;
          }
        }

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
                  for (final section in widget.sections) ...[
                    SliverToBoxAdapter(
                        child: _DateHeader(label: section.header)),
                    _buildJustifiedSection(
                      context,
                      section.photos,
                      width,
                      hPadding,
                      spacing,
                    ),
                  ],
                ],
              ),
            ),
            if (_showLabel && _activeLabel != null)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IgnorePointer(
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

  double _rowHeight(double containerWidth) {
    // Immich-style: row height scales with zoom level and container width.
    // Higher columns = smaller rows, lower columns = larger rows.
    final colCount = math.max(1, widget.columns);
    if (widget.squareTiles) {
      return (containerWidth - (colCount - 1) * 2) / colCount;
    }
    // Justified mode: fixed row height based on zoom.
    switch (widget.columns) {
      case 0:
        return 80;
      case 1:
        return 120;
      case 2:
        return 160;
      case 3:
        return 200;
      default:
        return 240;
    }
  }

  List<_JustifiedRow> _buildRows(
      List<PhotoItem> photos, double width, double hPadding, double spacing) {
    final provider = context.read<GalleryProvider>();
    final availableWidth = width - hPadding * 2;
    final rowHeight = _rowHeight(width);
    final rows = <_JustifiedRow>[];
    var currentRow = <_RowItem>[];
    var currentWidth = 0.0;

    for (final photo in photos) {
      final ratio = provider.getAspectRatio(photo);
      final itemWidth = rowHeight * ratio;
      currentRow.add(_RowItem(photo: photo, width: itemWidth));
      currentWidth += itemWidth + spacing;

      if (currentWidth >= availableWidth) {
        // Scale row to fill width.
        final totalItemWidth = currentRow.fold<double>(
            0, (sum, item) => sum + item.width);
        final totalSpacing = (currentRow.length - 1) * spacing;
        final scale = (availableWidth - totalSpacing) / totalItemWidth;
        final scaledRow = currentRow
            .map((item) =>
                _RowItem(photo: item.photo, width: item.width * scale))
            .toList();
        rows.add(_JustifiedRow(items: scaledRow, height: rowHeight * scale));
        currentRow = [];
        currentWidth = 0;
      }
    }

    // Last row: don't scale, use natural height.
    if (currentRow.isNotEmpty) {
      rows.add(_JustifiedRow(items: currentRow, height: rowHeight));
    }

    return rows;
  }

  Widget _buildJustifiedSection(
    BuildContext context,
    List<PhotoItem> photos,
    double width,
    double hPadding,
    double spacing,
  ) {
    final provider = context.read<GalleryProvider>();
    final rows = _buildRows(photos, width, hPadding, spacing);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final row = rows[index];
            provider.requestThumbnails(row.items.map((i) => i.photo).toList());
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
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
                          selected: widget.selectedPaths
                              .contains(row.items[j].photo.path),
                          thumbPath: provider
                              .thumbPathOrNull(row.items[j].photo),
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
          },
          childCount: rows.length,
          addAutomaticKeepAlives: false,
        ),
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
          fit: BoxFit.cover,
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
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.low,
        cacheWidth: gridCacheWidth,
        errorBuilder: (context, error, stack) => _fallback(context),
      );
    }

    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return Image.file(
      File(photo.path),
      fit: BoxFit.cover,
      alignment: Alignment.center,
      cacheWidth: 200,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const ColoredBox(color: Color(0xFF2A2A2E));
      },
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: Color(0xFF333333),
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 28),
        ),
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