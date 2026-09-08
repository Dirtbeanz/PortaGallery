import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_provider.dart';
import '../services/config_service.dart';
import '../widgets/manual_path_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/logo.png',
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Text('PortaGallery',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
              ],
            ),
          ),
          _section(context, 'Library',
              child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Photo library'),
                subtitle: Text(provider.libraryPath ?? 'Not set'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Change folder'),
                onPressed: () => _changeFolder(context, provider),
              ),
              TextButton.icon(
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter path manually'),
                onPressed: () => _enterPath(context, provider),
              ),
            ],
          )),
          const SizedBox(height: 16),
          _section(context, 'Storage',
              child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('Photos'),
                trailing: Text('${provider.photos.length}'),
              ),
              ListTile(
                leading: const Icon(Icons.album),
                title: const Text('Albums'),
                trailing: Text('${provider.albums.length}'),
              ),
              ListTile(
                leading: const Icon(Icons.favorite),
                title: const Text('Favorites'),
                trailing: Text('${provider.favorites.length}'),
              ),
            ],
          )),
          const SizedBox(height: 16),
          _section(context, 'Library options',
              child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Show hidden folders'),
                subtitle: const Text('Include folders marked with .nomedia'),
                value: provider.showHiddenFolders,
                onChanged: (v) => provider.setShowHiddenFolders(v),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Backup report'),
                subtitle: const Text('Export a CSV report of the library'),
                onTap: () => _backupReport(context, provider),
              ),
            ],
          )),
          const SizedBox(height: 16),
          _section(context, 'Actions',
              child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Rescan library'),
                onTap: () => _rescan(context, provider),
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Config file location'),
                subtitle: const Text('Holds the library path'),
                onTap: () => _showConfigLocation(context),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Future<void> _backupReport(
      BuildContext context, GalleryProvider provider) async {
    final photos = provider.photos;
    final videos = photos.where((p) => p.isVideo).length;
    final images = photos.length - videos;
    final noDate = photos.where((p) => p.dateTaken == null).length;
    final totalBytes = photos.fold<int>(0, (sum, p) => sum + p.sizeBytes);
    final albums = <String, int>{};
    for (final photo in photos) {
      albums[photo.album.isEmpty ? 'Photos' : photo.album] =
          (albums[photo.album.isEmpty ? 'Photos' : photo.album] ?? 0) + 1;
    }

    final buffer = StringBuffer()
      ..writeln('path,name,album,type,size_bytes,date_taken')
      ..writeAll(
        photos.map((p) =>
            '${_csv(p.path)},${_csv(p.name)},${_csv(p.album.isEmpty ? 'Photos' : p.album)},'
            '${p.isVideo ? 'video' : 'photo'},${p.sizeBytes},'
            '${p.dateTaken?.toIso8601String() ?? ''}'),
        '\n',
      );

    final downloads = await getDownloadsDirectory();
    final reportPath =
        p.join(downloads?.path ?? '/tmp', 'portagallery_report.csv');
    await File(reportPath).writeAsString(buffer.toString());

    if (!context.mounted) return;
    final albumList = albums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final albumText = albumList
        .take(12)
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Backup report'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total items: ${photos.length}'),
                Text('Photos: $images  •  Videos: $videos'),
                Text('Missing capture date: $noDate'),
                Text('Total size: ${_bytes(totalBytes)}'),
                const Divider(),
                const Text('Albums:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(albumText),
                const Divider(),
                Text('CSV saved to:\n$reportPath'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  String _bytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _section(BuildContext context, String title, {required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(title,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _changeFolder(
      BuildContext context, GalleryProvider provider) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;

    if (!Directory(path).existsSync()) {
      if (context.mounted) _snack(context, 'Folder does not exist');
      return;
    }

    await provider.setLibraryPath(path);
    if (context.mounted) _snack(context, 'Library updated');
  }

  Future<void> _enterPath(BuildContext context, GalleryProvider provider) async {
    final path = await showManualPathDialog(context);
    if (path == null || path.trim().isEmpty) return;

    final trimmed = path.trim();
    if (!Directory(trimmed).existsSync()) {
      if (context.mounted) {
        _snack(context, 'Folder does not exist: $trimmed');
      }
      return;
    }

    await provider.setLibraryPath(trimmed);
    if (context.mounted) _snack(context, 'Library updated');
  }

  Future<void> _rescan(BuildContext context, GalleryProvider provider) async {
    await provider.rescan();
    if (context.mounted) _snack(context, 'Library rescanned');
  }

  Future<void> _showConfigLocation(BuildContext context) async {
    final location = await ConfigService().configFileLocation();
    if (context.mounted) _snack(context, 'Config: $location');
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}