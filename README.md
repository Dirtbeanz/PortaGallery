# PortaGallery

A modern, cross-platform photo gallery for browsing the photos stored on an
external drive. One Flutter codebase that ships as a **Linux AppImage** and an
**Android APK**.

It's a clean replacement for digging through a USB drive with a file manager:
point it at the folder that holds your photos and you get a real gallery
experience — albums, favorites, search, zoom, tags, and more.

## Features

- **Gallery grid with 5 zoom levels** — slider that resizes tiles from a dense
  16-column overview down to large 2-column photos, with date section headers
  that broaden as you zoom out (day → month).
- **Albums** — folders on the drive become albums automatically; create new
  albums and move photos into them.
- **Virtual collections** — SQLite-based albums that can group photos across
  different folders (e.g. "Best of 2024").
- **Favorites** — heart any photo; persisted in a local SQLite database.
- **Sorting** — by name, date modified, or size (ascending/descending).
- **Search** — across filenames, tags, and comments.
- **Tags & comments** — attach tags and a note to any photo, then search by
  them. Built with future AI auto-tagging in mind.
- **Full-screen viewer** — pinch-to-zoom, swipe between photos, on-screen arrow
  buttons and keyboard `←`/`→` navigation, and an EXIF metadata panel.
- **Video playback** — powered by [media_kit](https://pub.dev/packages/media_kit)
  on both Linux and Android, with a video badge indicator in the grid and
  ffmpeg-generated thumbnails on Linux.
- **Map view** — browse geotagged photos on an OpenStreetMap map, auto-centers
  on your most recent photo's location.
- **Metadata** — view EXIF details (dimensions, date taken, camera, ISO,
  aperture, shutter, focal length, GPS).
- **Rename** and **delete** (single or in bulk).
- **Import to album** — when importing photos, choose an existing album, create
  a new one, or import to the library root.
- **Export / download** — save a copy to your Downloads folder.
- **Share** via the platform share sheet.
- **Multi-select** — long-press to select several photos and batch favorite,
  move, share, or delete.
- **Backup report** — export a CSV report of your entire library.
- **Drive-missing detection** — shows a banner when the USB drive is
  disconnected and auto-rescans when it reappears.
- **Dark / light theme** following the system setting.

## Performance

Built for large libraries (3000+ items):

- **Instant startup** — the photo list is cached in SQLite, so the app loads
  immediately on second launch while a background rescan picks up any changes.
- **Parallel directory scanning** — subdirectories are scanned in batches of 8
  simultaneously instead of one at a time.
- **Parallel thumbnail generation** — 6 thumbnails are generated at once instead
  of sequentially.
- **Async batched I/O** — thumbnail cache lookups and file existence checks run
  in parallel batches of 50 instead of synchronously one-by-one.
- **Cached computed results** — filtered/sorted photo lists, date sections, and
  favorites are cached and only recomputed when the underlying data changes.
- **No full-file reads for aspect ratios** — aspect ratios are populated from
  cached thumbnails instead of reading each original image file.
- **Isolate-based scanning** — directory scanning runs on a background isolate
  to keep the UI responsive.

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

Grab `PortaGallery-x86_64.AppImage` from the
[latest release](https://github.com/Dirtbeanz/PortaGallery/releases/latest),
make it executable, and run:

```sh
chmod +x PortaGallery-x86_64.AppImage
./PortaGallery-x86_64.AppImage
```

Video playback on Linux uses the system's `libmpv` (install `mpv` if it's
missing: `sudo pacman -S mpv` on Arch, `sudo apt install libmpv-dev` on
Debian/Ubuntu).

For HEIC/HEIF support: `sudo pacman -S libheif` (Arch) or equivalent.

For hardware video decode (Intel): `sudo pacman -S intel-media-driver libva-utils`.

### Android APK

Download `PortaGallery-vX.Y.Z.apk` from the
[latest release](https://github.com/Dirtbeanz/PortaGallery/releases/latest),
enable installs from unknown sources, and install.

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
  main.dart                        App entry point
  models/                          PhotoItem, Album, SortMode, PhotoMetadata, PhotoNotes
  providers/gallery_provider.dart  Central state (ChangeNotifier)
  services/
    config_service.dart            Config file (library path, show hidden folders)
    database_service.dart          SQLite (favorites, tags/comments, virtual albums, photo cache)
    photo_service.dart             Directory scanning, import/export, dimensions
    metadata_service.dart          EXIF reading (including GPS for map view)
    thumbnail_service.dart         Thumbnail generation with EXIF orientation correction
    external_player_service.dart   Launch system video player (mpv/haruna/vlc) on Linux
    permission_service.dart        Android storage permissions
  screens/
    home_screen.dart               Main scaffold with nav bar, search, import
    photos_view.dart               Photos tab with toolbar and multi-select
    photo_grid.dart                Grid widget with date sections and scroll indicators
    photo_viewer_screen.dart       Full-screen viewer with metadata panel
    albums_view.dart               Folder albums + virtual collections
    album_detail_screen.dart       Single folder album grid
    virtual_album_screen.dart      Virtual album view/manage
    favorites_view.dart            Favorites grid
    map_screen.dart                flutter_map with EXIF GPS markers
    settings_screen.dart           Library config, backup report, logo
  widgets/
    video_player_view.dart         media_kit video with custom controls
    zoom_slider.dart               Shared zoom slider widget
    notes_editor.dart              Tags + comments editor
    manual_path_dialog.dart        Manual path entry dialog
packaging/
  build_appimage.sh                AppImage build script
  AppRun, photo_gallery.desktop    AppImage metadata
  logo.png                         App icon/logo source
android/                           Android platform project
linux/                             Linux platform project
test/                              Unit tests
assets/                            Bundled assets (logo)
```

## Config file format

`config.json` contains the following keys:

```json
{
  "libraryPath": "/path/to/your/photos",
  "showHiddenFolders": false
}
```

## Contributing

Contributions are very welcome — this project is better with more hands on it.
Feel free to open an issue or submit a pull request.

Some ideas on the radar:

- **AI auto-tagging** — use on-device/cloud models to tag photos by people,
  places, and objects (the tags/comments system was built with this in mind).
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