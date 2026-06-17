# Install Open Nikon Importer

This guide assumes you have never installed a Mac app manually before.

## Recommended Download

Download the `.dmg` file from the latest GitHub Release.

Use the `.dmg`, not the source code zip.

## Install

1. Double-click the downloaded `.dmg`.
2. A Finder window opens.
3. Drag `Open Nikon Importer.app` onto the `Applications` shortcut.
4. Wait until the copy is finished.
5. Eject the mounted installer disk.
6. Open `Applications`.
7. Double-click `Open Nikon Importer`.

## First Open Warning

Preview builds are not Developer ID notarized yet. macOS may warn that it cannot verify the app.

If that happens:

1. Open `Applications`.
2. Right-click `Open Nikon Importer`.
3. Click `Open`.
4. Confirm `Open` once.

After that, normal double-clicking should work.

## Camera Permission

When macOS asks whether Open Nikon Importer may access files on a removable volume, click `Allow`.

Without this permission, the app cannot read the camera catalog.

## Import

1. Connect the camera by USB-C.
2. Put the camera into its normal MTP/PTP transfer mode.
3. Open Open Nikon Importer.
4. Choose a destination folder if needed.
5. Select files.
6. Click import.

The app does not delete files from the camera.

## Uninstall

Delete `Open Nikon Importer.app` from `Applications`.

Optional cache cleanup:

```sh
rm -rf "$HOME/Library/Caches/Open Nikon Importer"
```
