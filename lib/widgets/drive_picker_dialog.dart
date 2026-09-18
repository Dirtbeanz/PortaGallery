import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/external_drive_service.dart';
import '../services/permission_service.dart';

Future<String?> showDrivePickerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _DrivePickerDialog(),
  );
}

class _DrivePickerDialog extends StatefulWidget {
  const _DrivePickerDialog();

  @override
  State<_DrivePickerDialog> createState() => _DrivePickerDialogState();
}

class _DrivePickerDialogState extends State<_DrivePickerDialog> {
  bool _loading = true;
  bool _permissionGranted = true;
  List<String> _accessible = const [];
  List<AndroidVolume> _detected = const [];
  List<String> _subfolders = const [];
  String? _path;
  bool _browsing = false;

  @override
  void initState() {
    super.initState();
    _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    final granted = await PermissionService.ensureAllFilesAccess();
    final accessible = <String>[];
    var detected = <AndroidVolume>[];
    if (granted) {
      const internal = '/storage/emulated/0';
      if (await ExternalDriveService.isReadable(internal)) {
        accessible.add(internal);
      }
      accessible.addAll(await ExternalDriveService.androidVolumes());
      detected = await ExternalDriveService.platformVolumes();
    }
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _accessible = accessible;
      _detected = detected;
      _loading = false;
    });
  }

  Future<void> _openFolder(String path) async {
    setState(() {
      _browsing = true;
      _path = path;
      _subfolders = const [];
    });
    final subfolders = await ExternalDriveService.subfolders(path);
    if (!mounted) return;
    setState(() => _subfolders = subfolders);
  }

  void _backToVolumes() {
    setState(() {
      _browsing = false;
      _path = null;
      _subfolders = const [];
    });
  }

  Future<void> _goUp() async {
    final current = _path;
    if (current == null) return;
    if (_accessible.contains(current)) {
      _backToVolumes();
      return;
    }
    await _openFolder(p.dirname(current));
  }

  bool _isInternal(String path) => path.contains('/emulated/');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_browsing && _path != null
          ? p.basename(_path!)
          : 'Select drive or folder'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: _buildContent(context),
      ),
      actions: _browsing
          ? [
              TextButton(onPressed: _goUp, child: const Text('Up')),
              TextButton(
                onPressed: _backToVolumes,
                child: const Text('Drives'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_path),
                child: const Text('Use this folder'),
              ),
            ]
          : [
              TextButton(
                onPressed: () async {
                  setState(() => _loading = true);
                  await _loadVolumes();
                },
                child: const Text('Refresh'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_permissionGranted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          const Text(
            'PortaGallery needs "All files access" to read photos on USB '
            'drives.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await PermissionService.ensureAllFilesAccess();
              if (!mounted) return;
              setState(() => _loading = true);
              await _loadVolumes();
            },
            child: const Text('Grant access'),
          ),
        ],
      );
    }
    if (_browsing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_path ?? '', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: _subfolders.isEmpty
                ? const Center(child: Text('No subfolders'))
                : ListView(
                    children: [
                      for (final folder in _subfolders)
                        ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(p.basename(folder)),
                          onTap: () => _openFolder(folder),
                        ),
                    ],
                  ),
          ),
        ],
      );
    }

    final entries = <Widget>[];
    for (final path in _accessible) {
      final internal = _isInternal(path);
      entries.add(ListTile(
        leading: Icon(internal ? Icons.phone_android : Icons.usb),
        title: Text(internal ? 'Internal storage' : p.basename(path)),
        subtitle: Text(path),
        onTap: () => _openFolder(path),
      ));
    }
    for (final volume in _detected) {
      final path = volume.path;
      if (!volume.removable) continue;
      if (path != null && _accessible.contains(path)) continue;
      final title = volume.description.isNotEmpty
          ? volume.description
          : (path != null ? p.basename(path) : 'USB drive');
      final subtitle = !volume.mounted
          ? 'Detected but not mounted (${volume.state}). Mount it in the '
              'system settings or reinsert it, then tap Refresh.'
          : path == null
              ? 'Detected but no accessible path. Check "All files access".'
              : 'Detected but not readable: $path';
      entries.add(ListTile(
        leading: const Icon(Icons.usb, color: Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: false,
      ));
    }

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No drives detected.\nConnect a USB drive and tap Refresh.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(children: entries);
  }
}
