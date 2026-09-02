import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../providers/gallery_provider.dart';
import '../services/permission_service.dart';
import '../widgets/manual_path_dialog.dart';
import 'albums_view.dart';
import 'favorites_view.dart';
import 'photos_view.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    PermissionService.requestStorage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    if (!provider.isConfigured) {
      return const _NoLibraryScreen();
    }

    final views = [
      const PhotosView(),
      const AlbumsView(),
      const FavoritesView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search photos...',
                  border: InputBorder.none,
                ),
                onChanged: provider.setSearchQuery,
              )
            : Text(
                switch (_index) {
                  0 => 'Photos',
                  1 => 'Albums',
                  _ => 'Favorites',
                },
              ),
        actions: [
          if (_index == 0)
            IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              tooltip: _searching ? 'Close search' : 'Search',
              onPressed: () => _toggleSearch(provider),
            ),
          if (_index == 1)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New album',
              onPressed: () => _createAlbum(context, provider),
            ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import photos',
            onPressed: () => _importPhotos(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: views[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Photos',
          ),
          NavigationDestination(
            icon: Icon(Icons.album_outlined),
            selectedIcon: Icon(Icons.album),
            label: 'Albums',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favorites',
          ),
        ],
      ),
    );
  }

  void _toggleSearch(GalleryProvider provider) {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchController.clear();
      provider.setSearchQuery('');
    }
  }

  Future<void> _createAlbum(
      BuildContext context, GalleryProvider provider) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New album'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Album name'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) return;
    final ok = await provider.createAlbum(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Album created' : 'Could not create album')),
    );
  }

  Future<void> _importPhotos(
      BuildContext context, GalleryProvider provider) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp',
        'heic', 'heif', 'avif', 'tif', 'tiff', 'jfif',
        'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp',
      ],
    );

    if (result == null || result.files.isEmpty) return;

    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();

    if (paths.isEmpty) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Importing photos...')),
    );

    await provider.importPhotos(paths);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import complete')),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}

class _NoLibraryScreen extends StatelessWidget {
  const _NoLibraryScreen();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GalleryProvider>();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 96),
              const SizedBox(height: 24),
              Text(
                'Connect your photo library',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Select the folder on your external drive '
                'that contains your photos.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose folder'),
                onPressed: () => _pickFolder(context, provider),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.keyboard),
                label: const Text('Type a path instead'),
                onPressed: () => _pickManualPath(context, provider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFolder(
      BuildContext context, GalleryProvider provider) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;

    if (!Directory(path).existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder does not exist')),
        );
      }
      return;
    }

    await provider.setLibraryPath(path);
  }

  Future<void> _pickManualPath(
      BuildContext context, GalleryProvider provider) async {
    final path = await showManualPathDialog(context);
    if (path == null || path.trim().isEmpty) return;

    final trimmed = path.trim();
    if (!Directory(trimmed).existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folder does not exist: $trimmed')),
        );
      }
      return;
    }

    await provider.setLibraryPath(trimmed);
  }
}