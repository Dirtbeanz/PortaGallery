import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Temporary diagnostic log that captures Dart errors and library scan
/// summaries while the crash problem is being investigated. Logs are bounded
/// (rotated, size-capped) and live next to the app's config.
class DiagnosticLogService with WidgetsBindingObserver {
  static final DiagnosticLogService instance = DiagnosticLogService._();
  DiagnosticLogService._();

  static const int _maxBytes = 512 * 1024;
  static const int _maxFiles = 2;
  static const int _flushThreshold = 8;

  File? _file;
  final List<String> _buffer = [];
  bool _initialized = false;
  int _logVersion = 0;

  String? get logPath => _file?.path;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final version = ++_logVersion;
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      if (!await logDir.exists()) await logDir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(logDir.path, 'portagallery-$stamp.log'));
      await _rotateIfNeeded(logDir, keepName: file.path);
      await file.writeAsString(
          '--- PortaGallery session $stamp (${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}) ---\n');
      _file = file;
      WidgetsBinding.instance.addObserver(this);
      FlutterError.onError = (details) {
        log('FLUTTER ERROR: ${details.exception}');
        if (details.stack != null) log(details.stack.toString());
        flush();
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        log('UNCAUGHT ERROR: $error');
        log(stack.toString());
        flush();
        return true;
      };
    } catch (_) {
      if (version == _logVersion) _initialized = false;
    }
  }

  Future<void> _rotateIfNeeded(Directory logDir, {String? keepName}) async {
    final files = (await logDir.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    var keep = 0;
    for (final f in files) {
      if (f.path == keepName) continue;
      keep++;
      if (keep >= _maxFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  void log(String message) {
    final line =
        '${DateTime.now().toIso8601String().split('.').first} $message';
    _buffer.add(line);
    if (_buffer.length >= _flushThreshold) flush();
  }

  void flush() {
    if (_buffer.isEmpty || _file == null) return;
    final chunk = _buffer.join('\n');
    _buffer.clear();
    final f = _file!;
    () async {
      try {
        if (await f.exists() && await f.length() > _maxBytes) {
          await f.writeAsString('--- log truncated (size limit) ---\n');
        }
        await f.writeAsString('$chunk\n', mode: FileMode.append);
      } catch (_) {}
    }();
  }

  @override
  void didHaveMemoryPressure() {
    log('MEMORY PRESSURE: imageCache='
        '${PaintingBinding.instance.imageCache.currentSizeBytes}B');
    flush();
  }

  void recordScanSummary({
    required String libraryPath,
    required int scannedCount,
    required int cacheCount,
    required int duplicateCount,
  }) {
    log('SCAN library=$libraryPath scanned=$scannedCount '
        'cacheLoaded=$cacheCount duplicates=$duplicateCount');
    flush();
  }
}
