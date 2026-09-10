import 'package:flutter/material.dart';

import '../providers/gallery_provider.dart';

class ZoomSlider extends StatelessWidget {
  final GalleryProvider provider;
  const ZoomSlider({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.zoom_out, size: 18),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          padding: EdgeInsets.zero,
          onPressed: () => provider.setZoom(provider.zoomLevel - 1),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in, size: 18),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          padding: EdgeInsets.zero,
          onPressed: () => provider.setZoom(provider.zoomLevel + 1),
        ),
      ],
    );
  }
}