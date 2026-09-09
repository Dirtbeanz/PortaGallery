# PortaGallery

A modern, cross-platform photo gallery for browsing the photos stored on an
external drive. One Flutter codebase that ships as a **Linux AppImage** and an
**Android APK**.

It's a clean replacement for digging through a USB drive with a file manager:
point it at the folder that holds your photos and you get a real gallery
experience — albums, favorites, search, zoom, tags, and more.

## Features

- **Gallery grid with zoom** — pinch-zoom-style slider that resizes tiles from a
  dense overview to large, full-aspect-ratio photos.
- **Smart date separators** — photos grouped under headers that get broader as
  you zoom out (day → month → year).
- **Albums** — folders on the drive become albums automatically; create new
  albums and move photos into them.
- **Favorites** — heart any photo; persisted in a local SQLite database.
- **Sorting** — by name, date modified, or size (ascending/descending).
- **Search** — across filenames, tags, and comments.
- **Tags & comments** — attach tags and a note to any photo, then search by
  them. Built with future AI auto-tagging in mind.
- **Full-screen viewer** — pinch-to-zoom, swipe between photos, on-screen arrow
  buttons and keyboard `←`/`→` navigation, and an EXIF metadata panel.
- **Video playback** — powered by [media_kit](https://pub.dev/packages/media_kit)
  on both Linux and Android, with a clear play badge in the grid.
- **Metadata** — view EXIF details (dimensions, date taken, camera, ISO,
  aperture, shutter, focal length, GPS).
- **Rename** and **delete** (single or in bulk).
- **Import / Export** — copy photos into the library (upload) or save a copy to
  your Downloads folder (download).
- **Share** via the platform share sheet.
- **Multi-select** — long-press to select several photos and batch favorite,
  move, share, or delete.
- **Dark / light theme** following the system setting.

## Performance

v1.4.0 brings major speed improvements for large libraries:

- **Instant startup** — the photo list is cached in SQLite, so the app loads
  immediately on second launch while a background rescan picks up any changes.
- **Parallel directory scanning** — subdirectories are scanned in batches of 8
  simultaneously instead of one at a time.
- **Parallel thumbnail generation** — 6 thumbnails are generated at once instead
  of sequentially.
- **Async batched I/O** — thumbnail cache lookups and file existence checks run
  in parallel batches of 50 instead of synchronously one-by-one.
- **Cached computed results** — filtered/sorted photo lists and favorites are
  cached and only recomputed when the underlying data changes.
- **No full-file reads for aspect ratios** — aspect ratios are populated from
  cached thumbnails instead of reading each original image file.

## How it works

On first launch you choose the folder that contains your photos (pick it with
the file dialog, or type a path such as `/media/yourname/DRIVE/Pictures`).

The chosen path is stored in a config file:

- **Linux:** `~/.local/share/com.photoalbum.photo_gallery/config.json`
- **Android:** the app's private support directory (the "type a path" option is
  best for USB drives, which mount at paths like `/storage/XXXX-XXXX/`)

On Android, grant "All files access" when prompted so the app can read photos on
a mounted USB drive.

## Download / run

### Linux AppImage

Grab `dist/PortaGallery-x86_64.AppImage`, make it executable, and run:

```sh
chmod +x PortaGallery-x86_64.AppImage
./PortaGallery-x86_64.AppImage
```

Video playback on Linux uses the system's `libmpv` (install `mpv` if it's
missing: `sudo pacman -S mpv` on Arch, `sudo apt install libmpv-dev` on
Debian/Ubuntu).

### Android APK

Build it (see below) and install `build/app/outputs/flutter-apk/app-release.apk`
onto your device.

## Building from source

### Requirements

- [Flutter](https://flutter.dev) SDK (stable, 3.29 or newer)
- Linux desktop build: `clang`, `ninja`, `pkg-config`, GTK3 headers, and `mpv`
  for video playback
- Android build: Android SDK (platform 36, build-tools 36), NDK 27, and JDK 17
  (Java 26 will not work with the Gradle version used here)
- `appimagetool` (for packaging the AppImage)

### Linux AppImage

```sh
./packaging/build_appimage.sh
```

The script builds the Flutter Linux bundle, stamps in the app icon, and packages
everything into `dist/PortaGallery-x86_64.AppImage`.

### Android APK

```sh
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

Note: the first Android build is slow (it downloads Gradle, the Android Gradle
Plugin, and bundled video libraries).

### Tests

```sh
flutter analyze
flutter test
```

## Project structure

```
lib/
  main.dart                     App entry point
  models/                       PhotoItem, Album, SortMode, PhotoMetadata, PhotoNotes
  providers/gallery_provider.dart  Central state (ChangeNotifier)
  services/
    config_service.dart         Config file (library path)
    database_service.dart       SQLite (favorites, tags/comments, photo cache)
    photo_service.dart          Directory scanning, import/export, dimensions
    metadata_service.dart       EXIF reading
    thumbnail_service.dart      Thumbnail generation & caching
    permission_service.dart     Android storage permissions
  screens/                      Home, photos, albums, favorites, viewer, settings
  widgets/                      Video player, tags editor, path dialog, photo grid
packaging/
  build_appimage.sh             AppImage build script
  AppRun, photo_gallery.desktop AppImage metadata
  logo.png                      App icon/logo source
android/                        Android platform project
linux/                          Linux platform project
test/                           Unit tests
assets/                         Bundled assets (logo)
```

## Config file format

`config.json` contains a single key:

```json
{
  "libraryPath": "/path/to/your/photos"
}
```

## Contributing

Contributions are very welcome — this project is better with more hands on it.
Feel free to open an issue or submit a pull request.

Some ideas on the radar:

- **AI auto-tagging** — use on-device/cloud models to tag photos by people,
  places, and objects (the tags/comments system was built with this in mind).
- **Video thumbnails** instead of the static play badge.
- **Slideshow** mode and more import/export options (e.g. cloud storage).
- Better **Android USB-drive** handling without requiring "All files access".
- A Windows or macOS build.

Found a bug? Open an **issue** and describe what happened, your OS, and steps to
reproduce it.

## A note on how this is built

PortaGallery was developed with significant help from AI coding assistants — but
AI alone doesn't make good software. Human input — your bug reports, feature
requests, and code contributions — is what will actually make this project
great. If you spot something wrong or have an idea, please speak up.

## Support

If you like this project and want to support its development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/dirtbeanz59)

## License

[MIT](LICENSE)