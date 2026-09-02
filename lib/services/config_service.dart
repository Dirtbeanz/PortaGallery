import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ConfigService {
  static const _fileName = 'config.json';

  String? libraryPath;
  bool isConfigured = false;

  Future<File> _configFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }

  Future<void> load() async {
    try {
      final file = await _configFile(_fileName);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      libraryPath = data['libraryPath'] as String?;
      isConfigured =
          libraryPath != null && libraryPath!.isNotEmpty && Directory(libraryPath!).existsSync();
    } catch (_) {
      libraryPath = null;
      isConfigured = false;
    }
  }

  Future<void> saveLibraryPath(String path) async {
    libraryPath = path;
    isConfigured = path.isNotEmpty && Directory(path).existsSync();
    final file = await _configFile(_fileName);
    await file.writeAsString(jsonEncode({'libraryPath': path}));
  }

  Future<String?> configFileLocation() async {
    final file = await _configFile(_fileName);
    return file.path;
  }
}