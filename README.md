<div align="center">

<img src="assets/logo.png" width="140" alt="PortaGallery logo" />

# PortaGallery

**A portable photo and video gallery for external drives — your library, on any device.**

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Dirtbeanz/PortaGallery?label=release)](https://github.com/Dirtbeanz/PortaGallery/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Android-9cf.svg)](#platform-support)
[![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B.svg?logo=flutter&logoColor=white)](https://flutter.dev)
[![Ko-fi](https://img.shields.io/badge/Support-Ko--fi-FF5E5B.svg?logo=ko-fi&logoColor=white)](https://ko-fi.com/dirtbeanz59)

One Flutter codebase that ships as a **Linux AppImage** and an **Android APK**.

Point it at a folder on a USB drive and browse it like a real gallery — albums,
favorites, search, tags, a map, and full-screen viewing — without copying
anything to internal storage.

</div>

> [!WARNING]
> Your photos deserve backups. Follow the [3-2-1 backup rule](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/) — especially before bulk operations like deleting duplicates or emptying the trash.

> [!NOTE]
> This project was built with significant help from AI coding assistants. Bug
> reports, feature requests, and code contributions are what make it better —
> see [Contributing](#contributing).

## Table of contents

- [Why PortaGallery](#why-portagallery)
- [Features](#features)
- [Platform support](#platform-support)
- [Install](#install)
- [First run](#first-run)
- [Performance](#performance)
- [Supported formats](#supported-formats)
- [Building from source](#building-from-source)
- [Project structure](#project-structure)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Roadmap ideas](#roadmap-ideas)
- [Contributing](#contributing)
- [License](#license)

## Why PortaGallery

Most gallery apps assume your photos live in the phone or on a cloud server.
PortaGallery is built for the opposite case:

- Your library lives on a **portable drive** (USB stick, external SSD/HDD, SD card).
- You want a **real gallery experience on the go** — not a file manager.
- Nothing is uploaded. Everything stays on the drive; metadata (favorites,
  albums, tags, trash) is stored locally by the app.

## Features

### Browsing

- **Justified gallery grid** — rows keep the same height at each zoom level and
  photos keep their true aspect ratio (no forced squares, no cropping). Rows
  can leave space at the right; very wide images are clamped to the viewport
  without stretching.
- **4 zoom levels** with screen-aware sizing — base row heights of
  `56 / 72 / 112 / 170` logical pixels, scaled down further on narrow
  (portrait phone) screens.
- **Zoom-aware date groups** — years at the widest zoom, months next, then
  individual days labelled with the weekday (e.g. *"Friday, September 18, 2026"*).
- **Top-center date indicator** while scrolling.
- **Default sort: date taken** (EXIF), newest first; also sortable by name,
  date modified, and size, ascending or descending. Photos without EXIF dates
  fall back to the file's modified date.
- **Search** across filenames, tags, and comments.

### Organizing

- **Albums** — folders on the drive become albums automatically.
- **Album management** — long-press any album to rename it, dissolve it into
  the library root, or delete it with its photos moved to the trash.
- **Virtual collections** — SQLite-backed albums that group photos across
  folders (e.g. "Best of 2024").
- **Favorites** — heart any photo; persisted locally.
- **Tags and comments** — attach tags and a note to any photo, then search by
  them. Built with future AI auto-tagging in mind.
- **Date-taken editing** — override a photo's date; it drives sorting and date
  grouping and can be cleared to fall back to EXIF.
- **Trash** — deleted photos and videos move to a `.trash` folder inside the
  library. Restore items individually, or empty the trash to delete
  permanently.
- **Duplicate finder** — groups files by size and content (first/last 64KB
  comparison) so you can review and trash the extra copies.
- **Bulk actions** — long-press to select many photos: favorite, move, share,
  download, add to a collection, or move to trash. The action bar wraps so
  every action stays reachable on narrow screens.

### Viewing

- **Full-screen viewer** — pinch-to-zoom, swipe between photos, on-screen
  arrows and keyboard `←`/`→` navigation. The previous and next photos are
  preloaded, so swiping usually shows them instantly.
- **Rotate photos** — rotate any photo 90° at a time (left or right); the
  rotation is saved and applied in the grid and viewer.
- **EXIF metadata panel** — dimensions, date taken, camera, ISO, aperture,
  shutter, focal length, GPS.
- **Video playback** — powered by [media_kit](https://pub.dev/packages/media_kit)
  on Linux and Android, with a video badge in the grid and ffmpeg-generated
  thumbnails on Linux.
- **Map view** — browse geotagged photos on an OpenStreetMap map; it
  auto-centers on your most recent photo's location.

### Desktop keyboard shortcuts (Linux)

| Shortcut | Action |
| --- | --- |
| `Ctrl` + `F` | Search |
| `Esc` | Close search |
| `Ctrl` + `I` | Import photos |
| `F5` | Rescan library |
| `Ctrl` + `+` / `Ctrl` + `-` | Zoom in / out |
| `1` – `4` | Jump to zoom level |
| `←` / `→` | Previous / next photo (in the viewer) |

### Library & data

- **Import to album** — choose an existing album, create a new one, or import
  to the library root. Imported files keep the source file's modified date.
- **Export / download** — save a copy to your Downloads folder.
- **Share** via the platform share sheet.
- **Backup report** — export a CSV report of your entire library.
- **Drive-missing detection** — shows a banner when the drive is disconnected
  and auto-rescans when it reappears.
- **Dark / light theme** following the system setting.
- **Diagnostic log** — captures Dart/Flutter errors, scan summaries,
  memory-pressure events, and video errors for troubleshooting
  (Settings → Diagnostic log location).

## Platform support

| Feature | Linux | Android |
| --- | :---: | :---: |
| Gallery, albums, tags, favorites | Yes | Yes |
| Video playback | Software decode | Hardware (auto-safe) |
| External USB drives | Auto-mounted | "All files access" + drive picker |
| Map view (online tiles) | Yes | Yes |
| HEIC/HEIF previews | With `libheif` | Native |
| RAW previews | Via ImageMagick | Via platform codecs |

## Install

### Linux (AppImage)

1. Download `PortaGallery-x86_64.AppImage` from the
   [latest release](https://github.com/Dirtbeanz/PortaGallery/releases/latest).
2. Make it executable and run:

```sh
chmod +x PortaGallery-x86_64.AppImage
./PortaGallery-x86_64.AppImage
```

Video playback uses the system `libmpv` (install `mpv` if missing:
`sudo pacman -S mpv` on Arch, `sudo apt install libmpv-dev` on Debian/Ubuntu).
HEIC support needs `libheif` (`sudo pacman -S libheif` on Arch, or equivalent).

### Android (APK)

1. Download `PortaGallery-vX.Y.Z.apk` from the
   [latest release](https://github.com/Dirtbeanz/PortaGallery/releases/latest).
2. Enable installs from unknown sources and install.

On Android 11+, the app asks for **"All files access"** — this is required to
read USB drives and is used only for reading your library.

## First run

1. Connect your drive and pick the folder that contains your photos:
   - **Linux:** *Choose folder* or type a path like `/media/yourname/DRIVE/Pictures`.
   - **Android:** tap **Detect drives**, grant "All files access" when asked,
     pick your USB volume (shown as `/storage/XXXX-XXXX`), then **Use this folder**.
2. The app scans in the background. The photo list is cached in SQLite, so the
   next launch is instant while a background rescan picks up changes.

The chosen path is stored in a config file:

- **Linux:** `~/.local/share/com.photoalbum.photo_gallery/config.json`
- **Android:** the app's private support directory

## Performance

Designed to keep large libraries (tested with ~18,000 items) responsive:

- **Lazy timeline** — one list delegate builds only nearby headers and photo
  rows, instead of creating an offscreen first row for every date section.
  Only the visible rows plus a small margin are kept built. An 18,000-item
  widget regression test ensures initial thumbnail requests stay bounded.
- **Fast preview loading** — JPEG previews reuse the camera's embedded EXIF
  thumbnail when available, reading only 256KB per photo instead of decoding
  the whole original. EXIF orientation is applied, and unusual orientations
  fall back to full decoding.
- **Drive-friendly ordering** — thumbnail generation and header-reading passes
  work through files in path order, so reads are sequential instead of jumping
  around the disk. This matters most on spinning hard drives.
- **Thumbnail-only grid** — missing or failed thumbnails show placeholders;
  grid cells never fall back to decoding original photos. Previews for the
  visible rows load first (newest first with the default sort), and cached
  previews appear immediately at startup while the background rescan runs.
  Cached thumbnails are validated against the original's aspect ratio, so
  cropped, rotated, or squished thumbnails from older builds are regenerated.
- **Rebuild previews** — Settings → *Rebuild thumbnails* clears the entire
  preview cache and regenerates it with the current version. This is the
  reliable fix for thumbnails that show a wrong orientation or cropping after
  upgrading from an older version, because legacy preview files cannot always
  be detected and corrected automatically.
- **Cached startup** — SQLite supplies the initial photo list, filtered to the
  selected library root, while a background rescan checks for changes.
- **Background indexing** — directory scanning, existing-thumbnail discovery,
  EXIF date enrichment, and aspect-ratio reading run in background isolates.
- **Controlled thumbnail work** — up to three generation jobs run concurrently;
  failed items are not retried endlessly. Generated images use bounded decode
  dimensions and atomic cache writes.
- **Lifecycle guards** — serialized rescans and generation checks prevent stale
  asynchronous results from replacing newer library state.

Loading new previews while scrolling is bounded by drive speed — an external
HDD is noticeably slower than an SSD.

### First run after installing or updating

The first launch scans the library, then reads image headers in the background
to fix aspect ratios and enrich EXIF dates. A thin progress bar at the top
indicates this indexing. On a large library stored on a hard drive this can
take a few minutes, and previews may appear as placeholders while their
thumbnails are generated. Results are cached in SQLite, so following launches
are fast — only new or changed files are re-processed.

## Supported formats

**Images:** JPG/JPEG, PNG, GIF, BMP, WEBP, HEIC/HEIF, AVIF, TIFF, JP2/J2K/JXL,
SVG, ICO, PSD, MPO, and camera RAW formats including DNG, CR2/CR3, NEF, ARW,
ORF, RW2, PEF, RAF.

**Video:** MP4, MOV, AVI, MKV, WEBM, M4V, 3GP, WMV, FLV, MPG/MPEG, M2TS/MTS,
OGV, VOB.

Format support for thumbnails depends on the platform codecs; on Linux,
ImageMagick and `libheif` extend RAW/HEIC preview support.

## Building from source

Requirements:

- [Flutter](https://flutter.dev) SDK (stable, 3.29 or newer)
- **Linux:** `clang`, `ninja`, `pkg-config`, GTK3 headers, and `mpv` for video
- **Android:** Android SDK (platform 36, build-tools 36), NDK 27, JDK 17
  (Java 26 will not work with the Gradle version used here)
- `appimagetool` for packaging the AppImage

```sh
# Linux AppImage -> dist/PortaGallery-x86_64.AppImage
./packaging/build_appimage.sh

# Android APK -> build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release

# Tests and static analysis
flutter analyze
flutter test
```

The first Android build is slow (it downloads Gradle, the Android Gradle
Plugin, and bundled video libraries).

## Project structure

```
lib/
  main.dart                        App entry point, image cache config
  models/                          PhotoItem, Album, SortMode, PhotoMetadata, PhotoNotes, TrashItem
  providers/gallery_provider.dart  Central state (ChangeNotifier)
  services/
    config_service.dart            Config file (library path, show hidden folders)
    database_service.dart          SQLite (favorites, tags, albums, cache, date/rotation overrides, trash)
    photo_service.dart             Scanning, import/export, EXIF header parsing, dimensions
    metadata_service.dart          Full EXIF metadata (viewer, GPS)
    thumbnail_service.dart         Thumbnail generation (EXIF thumbnails + codecs)
    duplicate_service.dart         Size + content duplicate detection
    external_drive_service.dart    Android volume enumeration / drive picker
    permission_service.dart        Android storage permissions
    diagnostic_log_service.dart    Temporary local error and scan logging
    external_player_service.dart   Open videos in the system player on Linux
  screens/
    home_screen.dart               Main scaffold with nav bar, search, import
    photos_view.dart               Photos tab with toolbar and multi-select
    photo_grid.dart                Justified grid with date sections
    photo_viewer_screen.dart       Full-screen viewer with metadata panel
    albums_view.dart               Folder albums + virtual collections
    album_detail_screen.dart       Single folder album grid
    virtual_album_screen.dart      Virtual album view/manage
    favorites_view.dart            Favorites grid
    map_screen.dart                OpenStreetMap view with GPS markers
    trash_screen.dart              Trash with restore / empty
    duplicates_screen.dart         Duplicate review and cleanup
    settings_screen.dart           Library config, stats, about, diagnostics
  widgets/                         Video player, zoom buttons, dialogs, editors
  utils/                           Shared date labels
assets/                            App logo
packaging/                         AppImage build script and metadata
android/  linux/                   Platform projects
test/                              Unit and widget tests (30+)
```

## Configuration

`config.json` contains:

```json
{
  "libraryPath": "/path/to/your/photos",
  "showHiddenFolders": false
}
```

## Troubleshooting

**Linux video: some clips lag or show a black screen with audio.**
Linux uses software decoding; HEVC 1080p+ is CPU-heavy. Use *Open with system
player* in the video controls, or install a hardware-capable player.

**HEIC photos show placeholders on Linux.**
Install `libheif` (`sudo pacman -S libheif` on Arch).

**Android: the drive doesn't appear in "Detect drives".**
Grant "All files access" (Settings → Apps → PortaGallery → Special access), then
tap **Refresh** in the drive picker. If the drive still doesn't appear, Android
hasn't mounted it — check the notification shade.

**Map is blank.**
Map tiles come from OpenStreetMap and need an internet connection. GPS scanning
is done locally from EXIF headers.

**Thumbnails show the wrong orientation or look cropped.**
Usually caused by previews cached by an older version. Open Settings →
*Rebuild thumbnails* to clear the preview cache and regenerate it with the
current version.

**The app lags after browsing a lot.**
Report it with a diagnostic log: Settings → *Diagnostic log location* →
*Copy to Downloads*, then open an issue.

## Roadmap ideas

- **Library data on the drive** — store the database (favorites, albums, tags,
  overrides, trash) and thumbnails inside `<drive>/.portagallery/`, so the
  metadata and previews travel with the drive across devices.
- **Offline map tiles** for places without internet.
- **Phone → drive backup** with hash-based dedupe and "free up space after
  verifying".
- **Multi-drive switcher** with per-drive settings.
- **Timeline scrubber** — drag to jump to any date.
- **Advanced search filters** — date range, camera, orientation, resolution,
  has-GPS.
- **Slideshow mode**, **XMP sidecar support**, **ratings**, **encrypted
  albums**, **checksum/integrity reports**.
- Auto-tagging with on-device models (the tags system was built for this).
- Windows and macOS builds.

## Contributing

Contributions are very welcome — this project is better with more hands on it.

- Found a bug? [Open an issue](https://github.com/Dirtbeanz/PortaGallery/issues)
  with your OS, app version (Settings → Version), and steps to reproduce.
  Attach a diagnostic log when relevant.
- Have an idea? Open an issue to discuss before a large pull request.
- Code: run `flutter analyze` and `flutter test` before submitting.

## License

[MIT](LICENSE).

## Support

If you like this project and want to support its development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/dirtbeanz59)