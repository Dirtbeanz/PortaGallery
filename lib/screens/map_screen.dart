import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../services/metadata_service.dart';
import 'photo_viewer_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<({PhotoItem photo, double lat, double lon})> _points = [];
  bool _scanning = false;
  int _scanned = 0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final provider = context.read<GalleryProvider>();
    final photos = provider.photos.where((p) => !p.isVideo).toList();
    setState(() {
      _scanning = true;
      _scanned = 0;
      _points = [];
    });

    const batch = 8;
    for (var i = 0; i < photos.length; i += batch) {
      final chunk = photos.sublist(
          i, i + batch > photos.length ? photos.length : i + batch);
      final results = await Future.wait(chunk.map((p) async {
        final gps = await MetadataService.readGps(p.path);
        if (gps == null) return null;
        return (photo: p, lat: gps.$1, lon: gps.$2);
      }));
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          if (r != null) _points.add(r);
        }
        _scanned += chunk.length;
      });
      await Future<void>.delayed(Duration.zero);
    }

    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GalleryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan GPS data',
            onPressed: _scan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            LinearProgressIndicator(value: _scanned / provider.photos.length),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _points.isEmpty
                    ? const LatLng(20, 0)
                    : LatLng(
                        _points.map((p) => p.lat).reduce((a, b) => a + b) /
                            _points.length,
                        _points.map((p) => p.lon).reduce((a, b) => a + b) /
                            _points.length),
                initialZoom: _points.isEmpty ? 2 : 4,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.photoalbum.photo_gallery',
                ),
                MarkerLayer(
                  markers: [
                    for (final point in _points)
                      Marker(
                        point: LatLng(point.lat, point.lon),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => _openPhoto(point.photo),
                          child: const Icon(Icons.location_on,
                              color: Color(0xFF6750A4), size: 32),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPhoto(PhotoItem photo) {
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
}