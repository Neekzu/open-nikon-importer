# Open Nikon Importer

Native macOS importer for Nikon cameras over USB-C, built because macOS Image Capture can list Nikon ZR N-RAW `.NEV` clips and then fail to import them.

The first proven camera target is the Nikon ZR. The app imports normal media through Apple's `ImageCaptureCore` APIs and uses raw PTP commands for Nikon N-RAW `.NEV` clips that Apple's normal import path filters out or fails on.

> Not affiliated with, endorsed by, or sponsored by Nikon Corporation. Nikon names are used only to describe camera/file compatibility.

## Current Features

- Native SwiftUI macOS app.
- USB-C workflow; no Nikon account, no Nikon cloud, no Nikon NX Studio dependency.
- Imports to a local folder, defaulting to `~/Movies/Nikon Imports/YYYY-MM-DD`.
- Does not delete files from the camera.
- Shows thumbnail contact sheets and a list view.
- Distinguishes Nikon `N-RAW` (`.NEV`), RED `R3D`, proxy video, normal video, photo RAW, and photos.
- Uses same-basename proxy video thumbnails/previews for raw-video files when available.
- Provides a right-side inspector with preview status, local/import path, PTP handle/format/storage data, transfer method, UTI, and video metadata where available.
- Opens Quick Look previews from the app.

## Nikon ZR N-RAW Path

Nikon ZR `.NEV` files are N-RAW video files. On the test Mac, Apple's normal `ImageCaptureCore` media list exposes visible `.MOV`, `.MP4`, `.JPG`, `.NEF`, and similar files, while Apple's own Image Capture UI can show `.NEV` entries and then fail with `com.apple.ImageCaptureCore` error `-9934`.

Open Nikon Importer works around that by sending raw PTP commands through the active Apple camera session:

- `GetStorageIDs`
- `GetObjectHandles`
- `GetObjectInfo`
- `GetPartialObject`
- Nikon `GetObjectSize` (`0x9421`)
- Nikon `GetPartialObjectEx` (`0x9431`)

Known-size `.NEV` files are downloaded exactly by reported byte size using standard `GetPartialObject`. Files reported as `0xFFFFFFFF` need Nikon's 64-bit extended path: `GetObjectSize` for the real size and `GetPartialObjectEx` for 64-bit offsets. The Nikon ZR did not advertise Android/MTP-style `GetPartialObject64` (`0x95C1`) during testing.

## Build

```sh
cd "App"
swift build -c release --product ZRImporter
```

To build a local `.app` bundle:

```sh
./Scripts/package-app.sh
```

The packaged app is written to `Build/Open Nikon Importer.app` and a zip archive is written next to it.

## Install Locally

```sh
./Scripts/install-local.sh
```

macOS may ask for removable-media access after each ad-hoc build/sign. Allow it once so the app can read the connected camera catalog.

## Verified Test Case

Tested on macOS with a Nikon ZR connected over USB-C.

- Camera catalog probe saw the Nikon `ZR` and Apple's importable media list.
- Raw PTP probe saw `.NEV` objects not imported by Apple's normal path.
- Four N-RAW clips were fully imported with exact sizes:
  - `NKZ_2848.NEV` - `18,612,589,568` bytes
  - `A001_C139_0616D4.NEV` - `9,087,961,600` bytes
  - `A001_C140_0616BE.NEV` - `2,575,298,560` bytes
  - `A001_C141_0616XS.NEV` - `8,505,957,888` bytes

## Privacy

Open Nikon Importer is designed as a local-only utility. It does not upload media, phone home, create an account, or use analytics. See [docs/PRIVACY.md](docs/PRIVACY.md).

## Auto-Update Plan

The intended public update path is Sparkle 2 with signed appcast releases. The project includes packaging scripts and documentation, but runtime auto-update is intentionally not enabled until Developer ID signing, notarization, Sparkle EdDSA keys, and a public release feed are configured. See [docs/AUTOUPDATE.md](docs/AUTOUPDATE.md).

## GitHub Checks

GitHub Actions templates live in [docs/github-actions](docs/github-actions). Move them to `.github/workflows/` after the GitHub token has `workflow` scope.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).
