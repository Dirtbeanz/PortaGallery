import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStorage() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return true;
    }

    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      final videos = await Permission.videos.request();
      if (photos.isGranted || videos.isGranted) return true;

      final manage = await Permission.manageExternalStorage.request();
      if (manage.isGranted) return true;

      return photos.isGranted || videos.isGranted;
    }

    return true;
  }
}