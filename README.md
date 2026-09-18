# PortaGallery

A modern, cross-platform photo gallery for browsing the photos stored on an
external drive. One Flutter codebase that ships as a **Linux AppImage** and an
**Android APK**.

It's a clean replacement for digging through a USB drive with a file manager:
point it at the folder that holds your photos and you get a real gallery
experience — albums, favorites, search, zoom, tags, and more.

## Features

- **Gallery grid with 4 zoom levels** — zoom buttons select row heights of
  100, 160, 230, or 300 logical pixels on Linux and Android. Rows keep the
  same height at each zoom level, with variable-width, uncropped previews
  instead of forced square tiles. Rows can leave unused space at the right;
  very wide images fit within the available width without stretching.
- **Zoom-aware date groups** — date sections broaden as you zoom out: years at
  the widest level, months at the next, and individual days (with the weekday
  name) at the closest levels. A top-center date indicator shows the current
  section while scrolling.
- **Albums** — folders on the drive become albums automatically; create new
  albums and move photos into them.
- **Virtual collections** — SQLite-based albums that can group photos across
  different folders (e.g. "Best of 2024").
- **Favorites** — heart any photo; persisted in a local SQLite database.
- **Sorting** — by date taken (EXIF, default), name, date modified, or size
  (ascending/descending). Photos without EXIF dates fall back to the file's
  modified date.
- **Search** — across filenames, tags, and comments.
- **Tags & comments** — attach tags and a note to any photo, then search by
  them. Built with future AI auto-tagging in mind.
- **Full-screen viewer** — pinch-to-zoom, swipe between photos, on-screen arrow
  buttons and keyboard `←`/`→` navigation, and an EXIF metadata panel.
- **Video playback** — powered by [media_kit](https://pub.dev/packages/media_kit)
  on both Linux and Android, with a video badge indicator in the grid and
  ffmpeg-generated thumbnails on Linux.
- **Map view** — browse geotagged photos on an OpenStreetMap map, auto-centers
  on your most recent photo's location. GPS extraction runs in a background
  isolate, results are cached for the session, and only markers in the current
  viewport are built, so panning and zooming stay responsive.
- **Date-preserving import** — imported photos keep the source file's modified
  date, and EXIF date taken is used for sorting and grouping when present.
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

Designed to keep large libraries responsive:

- **Lazy timeline** — one list delegate builds nearby headers and photo rows,
  rather than creating an offscreen first row for every date section. An
  18,000-item widget regression test checks that initial thumbnail requests
  stay below 100 for its viewport and zoom configuration.
- **Thumbnail-only grid** — missing or failed thumbnails show placeholders;
  grid cells never fall back to decoding original photos.
- **Cached startup** — SQLite supplies the initial photo list, filtered to the
  selected library root, while a background rescan checks for changes.
- **Background indexing** — directory scanning, existing-thumbnail discovery,
  and lightweight JPEG EXIF date enrichment run in background isolates.
  Date-taken sorting can update as enrichment finishes.
- **Controlled thumbnail work** — up to three generation jobs run concurrently;
  failed items are tracked to avoid continuous retries. Generated images use
  bounded decode dimensions and atomic cache writes.
- **Cached geometry and lists** — row layouts, filtered/sorted lists, date
  sections, and favorites are cached. Thumbnail-derived aspect ratios update
  layouts without opening every original in the grid.
- **Lifecycle guards** — serialized rescans and generation checks prevent stale
  asynchronous results from replacing newer library state.

Gallery loading has been reported responsive on Linux and Android with an
approximately 18,000-item library. This is user feedback, not a guarantee for
all devices or media formats.

## How it works

On first launch you choose the folder that contains your photos (pick it with
the file dialog, or type a path such as `/media/yourname/DRIVE/Pictures`).

The chosen path is stored in a config file:

- **Linux:** `~/.local/share/com.photoalbum.photo_gallery/config.json`
- **Android:** the app's private support directory (the "type a path" option is
  best for USB drives, which mount at paths like `/storage/XXXX-XXXX/`)

On Android, tap **Detect drives** (or **Settings → Change drive**) to pick your
USB drive directly — volumes appear as `/storage/XXXX-XXXX`. Grant
**"All files access"** when prompted: photo/video permissions alone cannot
read files on removable drives, and the system folder picker may not show USB
volumes at all. If the app shows the drive as not connected, tap the banner to
grant access and retry.

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

Linux currently uses software video decoding; Android retains `auto-safe`
hardware decoding. Installing VAAPI drivers alone does not enable hardware
decoding in this Linux build.

### Known limitations and diagnostics

- **Linux video playback remains under investigation.** Some clips may lag or
  show a black screen with audio. The video controller is now attached before
  media opens, and player errors/first-frame timeouts are logged, but native
  HEVC playback has not been verified by the automated tests. Use **Open with
  system player** when needed.
- Existing thumbnail files may retain older cropping or incorrect dimensions;
  the grid cannot restore pixels missing from a cached thumbnail.
- Temporary diagnostic logging captures Flutter/Dart errors, scan summaries,
  memory-pressure notifications, and video errors. It cannot reliably capture
  native process crashes or OS memory kills; those may require system logs.
- Find the current log in **Settings → Diagnostic log location**. Linux logs
  are under `~/.local/share/com.photoalbum.photo_gallery/logs/`; Android uses
  private app storage. **Copy to Downloads** requires a writable Downloads
  directory and may depend on Android storage permissions.
- Logs are local and may contain library paths, filenames, and error details.
  Review them before sharing. Only recent sessions are retained.

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
    diagnostic_log_service.dart    Temporary local error and scan logging
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
    zoom_slider.dart               Shared zoom buttons
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