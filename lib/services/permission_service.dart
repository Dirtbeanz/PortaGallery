import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStorage() async {
    if (!Platform.isAndroid) return true;

    if (await hasAllFilesAccess()) return true;
    if (await ensureAllFilesAccess()) return true;

    final photos = await Permission.photos.request();
    final videos = await Permission.videos.request();
    return photos.isGranted || videos.isGranted;
  }

  static Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.manageExternalStorage.status).isGranted;
  }

  static Future<bool> ensureAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }
}
