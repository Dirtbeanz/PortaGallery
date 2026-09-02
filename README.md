# Photo Gallery

A modern, cross-platform photo gallery for browsing the photos stored on an
external drive. One Flutter codebase that ships as a **Linux AppImage** and an
**Android APK**.

It's designed to be a clean replacement for browsing a USB drive through a file
manager: point it at the folder that holds your photos and you get a real
gallery experience.

## Features

- **Gallery grid** — a responsive masonry layout with thumbnails (photos and
  video badges).
- **Albums** — folders on the drive become albums automatically; create new
  albums and move photos into them.
- **Favorites** — heart any photo; persisted in a local SQLite database.
- **Sorting** — by name, date modified, or size (ascending/descending).
- **Search** — filter by filename.
- **Full-screen viewer** — swipe between photos, pinch-to-zoom.
- **Video playback** — powered by [media_kit](https://pub.dev/packages/media_kit)
  on both Linux and Android.
- **Metadata** — view EXIF details (dimensions, date taken, camera, ISO,
  aperture, shutter, focal length, GPS).
- **Rename** photos.
- **Import / Export** — copy photos into the library (upload) or save a copy to
  your Downloads folder (download).
- **Share** via the platform share sheet.
- **Multi-select** — long-press to select several photos and batch favorite,
  move, share, or delete.
- **Delete** with confirmation.
- **Dark / light theme** following the system setting.

## How it works

On first launch you choose the folder that contains your photos (you can pick a
folder with the file dialog, or type a path such as
`/media/yourname/DRIVE/Pictures`).

The chosen path is stored in a config file:

- **Linux:** `~/.local/share/com.photoalbum.photo_gallery/config.json`
- **Android:** the app's private support directory (the "type a path" option is
  best for USB drives, which mount at paths like `/storage/XXXX-XXXX/`)

On Android, grant "All files access" when prompted so the app can read photos on
a mounted USB drive.

## Download / run

### Linux AppImage

Grab `dist/PhotoGallery-x86_64.AppImage`, make it executable, and run:

```sh
chmod +x PhotoGallery-x86_64.AppImage
./PhotoGallery-x86_64.AppImage
```

Video playback on Linux uses the system's `libmpv` (install `mpv` if it's
missing, e.g. `sudo pacman -S mpv` on Arch, `sudo apt install libmpv-dev` on
Debian/Ubuntu).

### Android APK

Build it (see below) and install `build/app/outputs/flutter-apk/app-release.apk`
onto your device.

## Building from source

### Requirements

- [Flutter](https://flutter.dev) SDK (stable, 3.29 or newer)
- Linux desktop build: `clang`, `ninja`, `pkg-config`, GTK3 headers
- Android build: Android SDK (platform 36, build-tools 36) and JDK 17
  (Java 26 will not work with the Gradle version used here)
- `appimagetool` (for packaging the AppImage)

### Linux AppImage

```sh
./packaging/build_appimage.sh
```

The script builds the Flutter Linux bundle and packages it into
`dist/PhotoGallery-x86_64.AppImage`.

### Android APK

```sh
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

Note: the first Android build is slow (it downloads Gradle, the Android Gradle
Plugin, and bundled video libraries).

### Tests

```sh
flutter test
```

## Project structure

```
lib/
  main.dart                     App entry point
  models/                       PhotoItem, Album, SortMode, PhotoMetadata
  providers/gallery_provider.dart  Central state (ChangeNotifier)
  services/
    config_service.dart         Config file (library path)
    database_service.dart       SQLite favorites
    photo_service.dart          Directory scanning, import/export
    metadata_service.dart       EXIF reading, dimensions
    permission_service.dart     Android storage permissions
  screens/                      Home, photos, albums, favorites, viewer, settings
  widgets/                      Video player, path dialog, photo grid
packaging/
  build_appimage.sh             AppImage build script
  AppRun, photo_gallery.desktop  AppImage metadata
android/                        Android platform project
linux/                          Linux platform project
test/                           Unit tests
```

## Config file format

`config.json` contains a single key:

```json
{
  "libraryPath": "/path/to/your/photos"
}
```

## License

[MIT](LICENSE)