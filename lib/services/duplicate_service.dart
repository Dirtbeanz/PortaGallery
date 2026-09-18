import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/photo_item.dart';

Future<List<(String, String)>> _hashFileBatch(List<String> paths) async {
  final out = <(String, String)>[];
  for (final path in paths) {
    try {
      final file = File(path);
      final raf = await file.open();
      final length = await raf.length();
      final head = await raf.read(65536);
      var tailHash = '';
      if (length > 65536) {
        await raf.setPosition(length - 65536);
        final tail = await raf.read(65536);
        tailHash = _fnv1a(tail);
      }
      await raf.close();
      out.add((path, '${length}_${_fnv1a(head)}_$tailHash'));
    } catch (_) {
      out.add((path, ''));
    }
  }
  return out;
}

String _fnv1a(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

class DuplicateService {
  /// Finds groups of files with identical size and identical first/last
  /// 64KB. This is a fast, content-based comparison that avoids hashing
  /// entire multi-megabyte files.
  static Future<List<List<PhotoItem>>> findDuplicates(
    List<PhotoItem> photos, {
    void Function(int scanned, int total)? onProgress,
  }) async {
    final bySize = <int, List<PhotoItem>>{};
    for (final photo in photos) {
      bySize.putIfAbsent(photo.sizeBytes, () => []).add(photo);
    }
    final candidates = <PhotoItem>[
      for (final group in bySize.values)
        if (group.length > 1) ...group,
    ];
    if (candidates.isEmpty) {
      onProgress?.call(0, 0);
      return [];
    }

    final hashes = <String, List<PhotoItem>>{};
    const batchSize = 100;
    var scanned = 0;
    for (var i = 0; i < candidates.length; i += batchSize) {
      final chunk = candidates.sublist(
          i,
          i + batchSize > candidates.length
              ? candidates.length
              : i + batchSize);
      final results =
          await compute(_hashFileBatch, chunk.map((p) => p.path).toList());
      for (final (path, hash) in results) {
        if (hash.isEmpty) continue;
        hashes.putIfAbsent(hash, () => []).add(
              chunk.firstWhere((photo) => photo.path == path),
            );
      }
      scanned += chunk.length;
      onProgress?.call(scanned, candidates.length);
    }

    final groups = [
      for (final group in hashes.values)
        if (group.length > 1) group,
    ];
    groups.sort((a, b) => b.length.compareTo(a.length));
    return groups;
  }
}
