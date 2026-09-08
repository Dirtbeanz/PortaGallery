import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ConfigService {
  static const _fileName = 'config.json';

  String? libraryPath;
  bool isConfigured = false;
  bool showHiddenFolders = false;

  bool get hasLibrary =>
      libraryPath != null && libraryPath!.trim().isNotEmpty;

  Future<File> _configFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }

  Future<Map<String, dynamic>> _loadMap() async {
    try {
      final file = await _configFile(_fileName);
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return {};
  }

  Future<void> load() async {
    try {
      final data = await _loadMap();
      libraryPath = data['libraryPath'] as String?;
      isConfigured = libraryPath != null &&
          libraryPath!.isNotEmpty &&
          Directory(libraryPath!).existsSync();
      showHiddenFolders = data['showHiddenFolders'] as bool? ?? false;
    } catch (_) {
      libraryPath = null;
      isConfigured = false;
    }
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final file = await _configFile(_fileName);
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> saveLibraryPath(String path) async {
    libraryPath = path;
    isConfigured = path.isNotEmpty && Directory(path).existsSync();
    final data = await _loadMap();
    data['libraryPath'] = path;
    await _save(data);
  }

  Future<void> saveShowHiddenFolders(bool value) async {
    showHiddenFolders = value;
    final data = await _loadMap();
    data['showHiddenFolders'] = value;
    await _save(data);
  }

  Future<String?> configFileLocation() async {
    final file = await _configFile(_fileName);
    return file.path;
  }
}