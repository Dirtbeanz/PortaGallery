package com.photoalbum.photo_gallery

import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "portagallery/drives"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listVolumes" -> result.success(listVolumes())
                    else -> result.notImplemented()
                }
            }
    }

    private fun listVolumes(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return emptyList()
        val manager = getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val volumes = mutableListOf<Map<String, Any?>>()
        for (volume in manager.storageVolumes) {
            val uuid = volume.uuid
            val path = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    volume.directory?.absolutePath
                !uuid.isNullOrEmpty() -> "/storage/$uuid"
                else -> null
            }
            volumes.add(
                mapOf(
                    "path" to path,
                    "uuid" to uuid,
                    "description" to volume.getDescription(this),
                    "removable" to volume.isRemovable,
                    "primary" to volume.isPrimary,
                    "mounted" to (volume.state == Environment.MEDIA_MOUNTED),
                    "state" to volume.state,
                )
            )
        }
        return volumes
    }
}
