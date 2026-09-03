import 'package:flutter/material.dart';

import '../providers/gallery_provider.dart';

class ZoomSlider extends StatelessWidget {
  final GalleryProvider provider;
  const ZoomSlider({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final sliderW = (screenW * 0.22).clamp(80.0, 220.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.zoom_out, size: 20),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          onPressed: () => provider.setZoom(provider.zoomLevel - 1),
        ),
        SizedBox(
          width: sliderW,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              value: provider.zoomLevel.toDouble(),
              min: 0,
              max: 3,
              divisions: 3,
              onChanged: (v) => provider.setZoom(v.round()),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in, size: 20),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          onPressed: () => provider.setZoom(provider.zoomLevel + 1),
        ),
      ],
    );
  }
}