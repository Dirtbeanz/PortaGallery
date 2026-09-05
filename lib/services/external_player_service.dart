import 'dart:io';

import 'package:flutter/foundation.dart';

class ExternalPlayerService {
  static const List<String> _linuxCandidates = [
    'mpv',
    'haruna',
    'vlc',
    'celluloid',
    'smplayer',
    'totem',
  ];

  static Future<String?> _findOnLinux() async {
    for (final exe in _linuxCandidates) {
      try {
        final result = await Process.run('which', [exe]);
        if (result.exitCode == 0) return exe;
      } catch (_) {}
    }
    return null;
  }

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (Platform.isLinux) return await _findOnLinux() != null;
    return false;
  }

  static Future<String?> launch(String path) async {
    if (kIsWeb || !Platform.isLinux) return null;
    final exe = await _findOnLinux();
    if (exe == null) return null;
    try {
      await Process.start(exe, [path],
          mode: ProcessStartMode.detachedWithStdio);
      return exe;
    } catch (_) {
      return null;
    }
  }
}