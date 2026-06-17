# Changelog

## Unreleased

- Added a disk-space precheck before imports start, including a local reserve for large video transfers.
- Added safe duplicate handling: imports now keep existing local files and save new copies with a numbered suffix instead of overwriting.
- Added an original macOS app icon and bundled it into packaged builds.
- Improved the main workflow UI with readiness chips, clearer empty states, larger thumbnails, and grouped inspector details.
- Fixed raw PTP re-import behavior so an existing local file is replaced only after the new `.partial` file is fully written and size-verified.
- Added a release-readiness audit document and cleaned up public maintenance docs.
- Added beginner-friendly DMG packaging with an Applications shortcut and first-run install instructions.
- Added release packaging script that builds app, zip, DMG, and checksum files.
- Renamed public project direction to Open Nikon Importer.
- Added open-source project files, packaging scripts, GitHub templates, and CI scaffolding.
- Added Nikon ZR N-RAW import support through raw PTP commands.
- Added Nikon 64-bit PTP import path for `.NEV` files reported as `0xFFFFFFFF`.
- Added thumbnail contact sheet, proxy previews for raw-video workflows, and metadata inspector.
