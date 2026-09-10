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
  double _lastTileWidth = 120;
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
    final offset = _scrollController.offset;
    if (oldWidget.sections.isEmpty) return;

    final starts = _computeSectionStarts(
        oldWidget.sections, _lastTileWidth, oldWidget.columns);
    var sectionIndex = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= offset + 8) sectionIndex = i;
    }
    final section = oldWidget.sections[sectionIndex];
    final within = (offset - starts[sectionIndex]).clamp(0.0, double.infinity);
    final rowHeight = _lastTileWidth + 4.0;
    final row = (within / rowHeight).floor();
    final index = (row * oldWidget.columns)
        .clamp(0, math.max(0, section.photos.length - 1))
        .toInt();
    _pendingAnchor = section.photos[index].path;
  }

  void _restoreAnchor() {
    final anchor = _pendingAnchor;
    if (anchor == null || !_scrollController.hasClients) return;
    _pendingAnchor = null;

    final starts = _computeSectionStarts(
        widget.sections, _lastTileWidth, widget.columns);
    for (var s = 0; s < widget.sections.length; s++) {
      final photos = widget.sections[s].photos;
      final photoIndex = photos.indexWhere((p) => p.path == anchor);
      if (photoIndex < 0) continue;
      final row = photoIndex ~/ widget.columns;
      final rowHeight = _lastTileWidth + 4.0;
      final target = starts[s] + row * rowHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(target.clamp(
            0.0, _scrollController.position.maxScrollExtent));
      });
      break;
    }
  }

  void _onScroll() {
    if (_sectionStarts.isEmpty) return;
    final offset = _scrollController.offset + 60;
    var index = 0;
    for (var i = 0; i < _sectionStarts.length; i++) {
      if (_sectionStarts[i] <= offset) index = i;
    }
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
        const spacing = 4.0;
        const hPadding = 4.0;
        final width = constraints.maxWidth;
        final colCount = math.max(1, widget.columns);
        final tileWidth =
            (width - hPadding * 2 - (colCount - 1) * spacing) / colCount;

        _lastTileWidth = tileWidth;
        _sectionStarts = _computeSectionStarts(
            widget.sections, tileWidth, colCount);
        if (_pendingAnchor != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAnchor());
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
                slivers: [
                  for (final section in widget.sections) ...[
                    SliverToBoxAdapter(
                        child: _DateHeader(label: section.header)),
                    _buildSection(
                      context,
                      section.photos,
                      tileWidth,
                      colCount,
                      spacing,
                      hPadding,
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

  List<double> _computeSectionStarts(
      List<({String header, List<PhotoItem> photos})> sections,
      double tileWidth,
      int colCount) {
    const headerHeight = 46.0;
    const rowSpacing = 4.0;
    final starts = <double>[];
    var acc = 0.0;
    for (final section in sections) {
      starts.add(acc);
      acc += headerHeight;
      final rows = (section.photos.length / colCount).ceil();
      acc += rows * (tileWidth + rowSpacing);
    }
    return starts;
  }

  Widget _buildSection(
    BuildContext context,
    List<PhotoItem> photos,
    double tileWidth,
    int colCount,
    double spacing,
    double hPadding,
  ) {
    final provider = context.read<GalleryProvider>();
    final rows = <List<PhotoItem>>[];
    for (var i = 0; i < photos.length; i += colCount) {
      rows.add(photos.sublist(i, math.min(i + colCount, photos.length)));
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final row = rows[index];
            provider.requestThumbnails(row);
            final children = <Widget>[];
            for (var j = 0; j < row.length; j++) {
              if (j > 0) children.add(const SizedBox(width: 4));
              final photo = row[j];
              final height = widget.squareTiles
                  ? tileWidth
                  : tileWidth / provider.getAspectRatio(photo);
              children.add(SizedBox(
                width: tileWidth,
                height: height,
                child: RepaintBoundary(
                  child: _PhotoTile(
                    photo: photo,
                    index: index * colCount + j,
                    selected: widget.selectedPaths.contains(photo.path),
                    cacheWidth: widget.squareTiles ? 400 : 1000,
                    thumbPath: provider.thumbPathOrNull(photo),
                    onTap: widget.onPhotoTap,
                    onLongPress: widget.onPhotoLongPress,
                    viewerPhotos: widget.viewerPhotos,
                  ),
                ),
              ));
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
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
  final int cacheWidth;
  final String? thumbPath;
  final ValueChanged<PhotoItem>? onTap;
  final ValueChanged<PhotoItem>? onLongPress;
  final List<PhotoItem>? viewerPhotos;

  const _PhotoTile({
    required this.photo,
    required this.index,
    this.selected = false,
    this.cacheWidth = 400,
    this.thumbPath,
    this.onTap,
    this.onLongPress,
    this.viewerPhotos,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'photo_${photo.path}_$index',
      child: GestureDetector(
        onTap: () => onTap != null ? onTap!(photo) : _openViewer(context),
        onLongPress: () => onLongPress?.call(photo),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Thumbnail(
                photo: photo,
                cacheWidth: cacheWidth,
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
                  top: 6,
                  right: 6,
                  child: Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                ),
              if (photo.isVideo)
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.white, size: 14),
                        SizedBox(width: 2),
                        Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                ),
            ],
          ),
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
        builder: (_) => PhotoViewerScreen(
          photos: source,
          initialIndex: startIndex,
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PhotoItem photo;
  final int cacheWidth;
  final String? thumbPath;

  const _Thumbnail({
    required this.photo,
    this.cacheWidth = 400,
    this.thumbPath,
  });

  @override
  Widget build(BuildContext context) {
    if (photo.isVideo) {
      if (thumbPath != null) {
        return Image.file(
          File(thumbPath!),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stack) => _videoPlaceholder(),
        );
      }
      return _videoPlaceholder();
    }

    if (thumbPath != null) {
      return Image.file(
        File(thumbPath!),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stack) => _fallbackFull(context),
      );
    }

    return _fallbackFull(context);
  }

  Widget _fallbackFull(BuildContext context) {
    return Image.file(
      File(photo.path),
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const ColoredBox(color: Color(0xFF2A2A2E));
      },
      errorBuilder: (context, error, stack) => const ColoredBox(
        color: Color(0xFF333333),
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 32),
        ),
      ),
    );
  }

  Widget _videoPlaceholder() {
    return const ColoredBox(
      color: Color(0xFF1B1B1F),
      child: Center(
        child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 24),
      ),
    );
  }
}