import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/photo_item.dart';
import '../providers/gallery_provider.dart';
import '../services/metadata_service.dart';
import 'photo_viewer_screen.dart';

typedef _GeoPoint = ({PhotoItem photo, double lat, double lon});

Future<List<(String, double?, double?)>> _scanGpsBatch(
    List<String> paths) async {
  final out = <(String, double?, double?)>[];
  for (final path in paths) {
    final gps = await MetadataService.readGps(path);
    out.add((path, gps?.$1, gps?.$2));
  }
  return out;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const Set<String> _gpsExtensions = {
    '.jpg', '.jpeg', '.jpe', '.jfif', '.tif', '.tiff',
  };

  List<_GeoPoint> _points = [];
  List<_GeoPoint> _visiblePoints = [];
  bool _scanning = false;
  int _scanned = 0;
  int _total = 0;
  final MapController _mapController = MapController();
  bool _focused = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final provider = context.read<GalleryProvider>();
    final photos = provider.photos
        .where((photo) =>
            !photo.isVideo &&
            _gpsExtensions.contains(p.extension(photo.path).toLowerCase()))
        .toList();

    final photoByPath = {for (final photo in photos) photo.path: photo};
    final knownPoints = <_GeoPoint>[];
    final toScan = <String>[];
    for (final photo in photos) {
      if (MetadataService.hasGpsCache(photo.path)) {
        final gps = MetadataService.cachedGps(photo.path);
        if (gps != null) {
          knownPoints.add((photo: photo, lat: gps.$1, lon: gps.$2));
        }
      } else {
        toScan.add(photo.path);
      }
    }

    setState(() {
      _scanning = true;
      _scanned = photos.length - toScan.length;
      _total = photos.length;
      _points = knownPoints;
      _visiblePoints = knownPoints;
      _focused = false;
    });
    if (_mapReady && knownPoints.isNotEmpty) {
      _updateVisiblePoints(_mapController.camera);
    }

    const batch = 250;
    for (var i = 0; i < toScan.length; i += batch) {
      final chunk = toScan.sublist(
          i, i + batch > toScan.length ? toScan.length : i + batch);
      final results = await compute(_scanGpsBatch, chunk);
      if (!mounted) return;
      final newPoints = <_GeoPoint>[];
      for (final (path, lat, lon) in results) {
        if (lat != null && lon != null) {
          MetadataService.cacheGps(path, (lat, lon));
          final photo = photoByPath[path];
          if (photo != null) {
            newPoints.add((photo: photo, lat: lat, lon: lon));
          }
        } else {
          MetadataService.cacheGps(path, null);
        }
      }
      setState(() {
        _points.addAll(newPoints);
        _scanned += chunk.length;
      });

      // Focus on the most recent photo's location on first GPS hit.
      if (!_focused && _points.isNotEmpty) {
        _focused = true;
        // Photos are sorted newest-first, so first point is most recent.
        final newest = _points.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(LatLng(newest.lat, newest.lon), 6);
          }
        });
      }

      if (_mapReady) _updateVisiblePoints(_mapController.camera);
      await Future<void>.delayed(Duration.zero);
    }

    if (mounted) setState(() => _scanning = false);
  }

  void _updateVisiblePoints(MapCamera camera) {
    if (_points.isEmpty) {
      if (_visiblePoints.isNotEmpty) {
        setState(() => _visiblePoints = []);
      }
      return;
    }
    final bounds = camera.visibleBounds;
    final visible = <_GeoPoint>[];
    for (final point in _points) {
      if (bounds.contains(LatLng(point.lat, point.lon))) visible.add(point);
    }
    final unchanged = visible.length == _visiblePoints.length &&
        (visible.isEmpty ||
            (visible.first.photo.path == _visiblePoints.first.photo.path &&
                visible.last.photo.path == _visiblePoints.last.photo.path));
    if (unchanged) return;
    setState(() => _visiblePoints = visible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _total == 0 ? null : _scanned / _total,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan GPS data',
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _points.isEmpty
              ? const LatLng(20, 0)
              : LatLng(_points.first.lat, _points.first.lon),
          initialZoom: _points.isEmpty ? 2 : 6,
          onMapReady: () {
            _mapReady = true;
            _updateVisiblePoints(_mapController.camera);
          },
          onPositionChanged: (camera, hasGesture) {
            _updateVisiblePoints(camera);
          },
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
              for (final point in _visiblePoints)
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
