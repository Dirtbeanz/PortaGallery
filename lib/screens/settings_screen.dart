import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
                  borderRadius: BorderRadius.circular(16),
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