# Release Readiness Audit

Date: 2026-06-17

Audited commit: `8cc9427`

Current public release at audit time: `v0.2.1` preview

## Verified Locally

- `swift build --package-path App -c release --product ZRImporter` succeeds.
- `./Scripts/package-release.sh` succeeds.
- App bundle is created.
- ZIP archive is created.
- DMG is created and `hdiutil verify` reports it as valid.
- Checksum file is created.
- App bundle is ad-hoc signed.
- Gatekeeper still rejects the preview build because it is not Developer ID signed/notarized yet.
- `Contents/Resources/` is empty, so the app currently has no custom icon.
- Tracked-file scan found no private local paths or secrets.

## What Is Already Safe

- No camera-delete path was found.
- ImageCaptureCore import uses `deleteAfterSuccessfulDownload: false`.
- Raw PTP import writes to `.partial` first.
- Final byte-size verification is present and enforced for raw PTP imports.
- Catalog generation guards reduce stale camera-list overwrite risk.

## Findings

### High

**F1 - Re-import could remove the previous local file before the new transfer succeeded.**

Before the fix, raw PTP import removed an existing local destination file at the beginning of the transfer. If a large re-import failed mid-transfer, the previous local copy would already be gone.

Status: fixed after this audit and shipped in `v0.2.2`. The destination is now replaced only after the new `.partial` file is fully written and size-verified.

### Medium

**F2 - No disk-space precheck before large imports.**

Large N-RAW imports can fail late if the destination volume runs out of space. Add a preflight check using available volume capacity against the selected import size.

**F3 - Duplicate handling is still too silent.**

ImageCaptureCore import currently uses overwrite behavior, and raw PTP import replaces same-name files after successful verification. Public releases should warn, auto-suffix, or otherwise make duplicate behavior explicit.

**F4 - App UI language and public docs are mixed.**

The app UI is German while README/install docs are English. For a public release, pick an English base UI or add localization.

**F5 - Product name contains a camera manufacturer mark.**

The name `Open Nikon Importer` is descriptive and has a disclaimer, but a manufacturer mark in the product name is still a release-readiness risk. Consider a more neutral app name with Nikon compatibility described in subtitle/docs.

**F6 - No custom app icon.**

The Finder/Dock experience currently looks unfinished. Add an original icon that suggests camera import without copying manufacturer branding.

### Low

**F7 - PTP transaction counter is mutable shared state.**

The transaction ID is mutated from async code without explicit isolation. Practical use appears mostly serialized, but making the transfer engine an actor or otherwise serializing command creation would reduce latent race risk.

**F8 - Build warnings remain.**

Known warnings include non-Sendable captures, deprecated AVFoundation synchronous metadata access, and deprecated SwiftUI `onChange` overloads.

**F9 - Preview cache lacks a clear size/age policy.**

Add a cache cap, LRU cleanup, or user-visible reset option.

**F10 - R3D classification may imply support that has not been verified.**

Either test the workflow or label it as untested/experimental.

**F11 - Permission copy may be imprecise.**

`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` may not match the actual ImageCaptureCore/removable-media TCC prompts. Verify on a clean macOS account.

**F12 - Probe scripts are useful but noisy for a beginner-facing public repo.**

Consider moving probe tools into `Tools/` or documenting them as developer diagnostics.

## Suggested Release Plan

### 0.2.x

- Keep DMG release path.
- Add disk-space precheck.
- Add explicit duplicate behavior.
- Add custom icon.
- Clean build warnings.
- Review Info.plist permission copy.

### 0.3.0

- Polish the main SwiftUI workflow.
- Add clearer no-camera onboarding.
- Add status chips for camera/catalog/PTP scan/destination readiness.
- Improve inspector hierarchy.
- Add preview cache policy.
- Add diagnostics export.

### 1.0

- Developer ID signing.
- Notarization and stapling.
- CI enabled and green.
- Sparkle 2 with signed appcast.
- Public name/trademark decision completed.
- Compatibility tested on at least one additional Nikon body.

## UI Direction

The app should feel like a premium native macOS camera/media utility:

- graphite/neutral foundation
- one restrained warm accent
- visually dominant thumbnails
- calm no-camera state
- obvious import progress
- technical metadata available but not visually dumped into the primary workflow

Avoid logos, copied trade dress, or anything implying official manufacturer affiliation.
