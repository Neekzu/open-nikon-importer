# Claude Audit Handoff: Open Nikon Importer

Date: 2026-06-17

Repository: `https://github.com/Neekzu/open-nikon-importer`

Current public release: `v0.2.1` preview

## Mission

Audit Open Nikon Importer as if it were about to become a small public free/open-source macOS utility for Nikon camera users.

Please focus on:

1. Correctness and safety of camera import behavior.
2. Beginner-proof installation and first-run experience.
3. Public-release readiness.
4. UI/UX polish: make it feel like a serious premium camera/media tool.
5. Clear next steps for auto-update, signing/notarization, and broader camera compatibility.

Output should be findings-first, ordered by severity. If you implement changes, keep them scoped and verify them.

## Product Context

Open Nikon Importer exists because macOS Image Capture can show Nikon ZR N-RAW `.NEV` files but fail to import them with `com.apple.ImageCaptureCore` error `-9934`.

The app is currently a native SwiftUI macOS app. It uses:

- `ImageCaptureCore` for normal camera media exposed by macOS.
- Raw PTP commands through `ICCameraDevice.requestSendPTPCommand` for Nikon ZR N-RAW `.NEV` files.
- A visible public app name of `Open Nikon Importer`.
- A SwiftPM executable target still named `ZRImporter`.

It is explicitly not affiliated with Nikon Corporation. Nikon names are used only to describe compatibility.

## Known Proven Test Case

Tested with Nikon ZR connected over USB-C.

The app successfully imported four Nikon ZR N-RAW `.NEV` files:

- `NKZ_2848.NEV` - `18,612,589,568` bytes
- `A001_C139_0616D4.NEV` - `9,087,961,600` bytes
- `A001_C140_0616BE.NEV` - `2,575,298,560` bytes
- `A001_C141_0616XS.NEV` - `8,505,957,888` bytes

Important PTP learning:

- Known-size `.NEV` files can use standard `GetPartialObject`.
- Large files reported as `0xFFFFFFFF` need Nikon `GetObjectSize` (`0x9421`) and Nikon `GetPartialObjectEx` (`0x9431`) with 64-bit offsets.
- Nikon ZR did not advertise Android/MTP-style `GetPartialObject64` (`0x95C1`) in testing.

## Current Release State

`v0.2.1` preview release includes:

- `.dmg` installer.
- App bundle zip.
- SHA-256 checksum file.
- DMG content:
  - `Open Nikon Importer.app`
  - `Applications` symlink
  - `READ ME FIRST.txt`
- Beginner install guide in `docs/INSTALL.md`.

The app is ad-hoc signed only. It is not Developer ID signed or notarized yet, so macOS Gatekeeper friction is expected.

## Important Open Issues

- `#1` Enable Sparkle 2 auto-updates.
- `#2` Activate GitHub Actions build checks.
- `#3` Clean up Swift warnings before first stable release.
- `#4` Make public macOS install fully Gatekeeper-friendly.

## First Commands To Run

```sh
git status --short --branch
swift build --package-path App -c release --product ZRImporter
./Scripts/package-release.sh
```

Expected:

- Swift release build succeeds.
- `Build/Open Nikon Importer.app` is created.
- `Build/Open Nikon Importer-<version>-macos.zip` is created.
- `Build/Open Nikon Importer-<version>-macos.dmg` is created.
- `Build/checksums-<version>.txt` is created.
- `hdiutil verify` passes for the DMG.

## Code Areas To Inspect

- `App/Sources/ZRImporter/CameraImportModel.swift`
  - app state
  - ImageCaptureCore browser/session behavior
  - import queue
  - preview caching
  - thumbnail request mapping
- `App/Sources/ZRImporter/PTPTransferEngine.swift`
  - PTP command construction
  - chunking
  - size verification
  - partial-file handling
  - error handling
- `App/Sources/ZRImporter/CameraFileItem.swift`
  - media classification
  - N-RAW/R3D/proxy logic
- `App/Sources/ZRImporter/ContentView.swift`
  - UI layout and workflow ergonomics
- `App/Sources/ZRImporter/QuickLookPreviewer.swift`
  - Quick Look integration
- `Packaging/Info.plist`
  - bundle identity
  - permissions strings
  - versioning
- `Scripts/package-*.sh`
  - packaging reproducibility
  - DMG layout
  - signing assumptions

## Safety / Correctness Audit Checklist

Please look specifically for:

- Any path that could delete files from the camera.
- Imports that can leave corrupted final files instead of `.partial` files.
- Missing final byte-size verification.
- Race conditions between camera refresh, selection, and active imports.
- Bad behavior when the camera disconnects mid-import.
- Bad behavior when the destination folder disappears or is read-only.
- Duplicate filename handling.
- Disk-space failure handling for huge N-RAW files.
- Progress behavior for multi-file imports.
- Whether preview caching could accidentally fill disk.
- Whether PTP errors are understandable for normal users.
- Whether app state recovers after permission denial.
- Whether same-basename proxy matching can mismatch files in edge cases.
- Whether `.R3D` classification is useful or misleading before actual RED workflow support.

## Public Release Audit Checklist

Please inspect:

- Does `README.md` communicate clearly to normal users?
- Does `docs/INSTALL.md` reduce support burden?
- Are release artifacts named clearly?
- Is the DMG layout clear enough for non-technical users?
- Is the lack of notarization stated without sounding scary?
- Is the Nikon non-affiliation disclaimer visible enough?
- Should the app name stay `Open Nikon Importer`, or should it become more generic to avoid trademark risk?
- Should GitHub issue templates ask for the right compatibility data?
- Are private machine paths, personal data, or misleading proof claims exposed?

## UI/UX Design Brief

The current UI is functional but should feel more like a polished camera/media workflow tool.

Design direction:

- Premium native macOS.
- Camera-grade, serious, precise.
- Dark graphite / neutral material base.
- Subtle warm yellow accent is acceptable as a camera-inspired cue, but do not copy Nikon brand assets or trade dress.
- Avoid Nikon logos, copied Nikon UI, copied Nikon yellow/black marketing layout, or anything implying official affiliation.
- Avoid marketing-page hero fluff; the first screen should remain the usable importer.
- Dense enough for professional media review, but not intimidating.
- Thumbnails should be visually dominant because the user recognizes shoots by thumbnails.
- Inspector should feel useful, not like debug output dumped into the UI.
- Empty/no-camera state should be calm and actionable.
- Import progress should be extremely obvious.

Possible UI improvements:

- Better no-camera onboarding state:
  - Connect camera by USB-C.
  - Set camera to MTP/PTP transfer mode.
  - Allow macOS removable-media permission.
- Clearer status rail:
  - Camera connected
  - Catalog loaded
  - N-RAW PTP scan done
  - Destination writable
- More premium thumbnail cards:
  - fixed aspect ratios
  - stronger selected state
  - visible raw/proxy pairing
  - duration/resolution badges where known
- Better right inspector:
  - top preview
  - file identity
  - import readiness
  - proxy relation
  - technical metadata collapsed/secondary
- Safer import controls:
  - disabled states with reasons
  - global import progress
  - reveal last import
  - duplicate warning before overwriting/renaming
- First-run permission education that is visible only when needed.

## UX Copy Guidance

Keep copy plain and reassuring.

Good:

- "Connect a camera by USB-C."
- "Allow removable-media access so the app can read the camera."
- "Files stay on the camera. Import copies them to your Mac."

Avoid:

- Overly technical PTP jargon in the main UI.
- Anything that sounds like official Nikon software.
- Scary warnings unless there is real user action needed.

## Implementation Boundaries

Please do not:

- Add analytics.
- Add account login.
- Add cloud upload.
- Add camera deletion.
- Enable Sparkle auto-update without completing signing/appcast security.
- Replace the proven Nikon PTP path with a speculative rewrite.
- Introduce heavyweight dependencies unless there is a clear benefit.

Reasonable improvements:

- UI polish in SwiftUI.
- Better local diagnostics export.
- Better user-visible error states.
- Safer duplicate handling.
- Cleaner packaging scripts.
- Swift warning cleanup.
- GitHub Actions activation after token scope is available.
- Better issue templates.

## Desired Audit Output

Please return:

1. Findings first, ordered by severity.
2. Concrete file references.
3. What you verified locally.
4. What you could not verify without a real camera.
5. Suggested next release plan:
   - `0.2.x` quick fixes
   - `0.3.0` design/workflow improvements
   - `1.0` public/stable requirements

If implementing changes, also include:

- A short change summary.
- Build/package verification output.
- Screenshots if UI changed.
- Any new or updated GitHub issues needed.

## Suggested "First Pass" Scope

If time is limited, do this first:

1. Build/package verification.
2. Safety audit of import and PTP write paths.
3. Install/DMG audit.
4. UI polish proposal with 5-10 concrete changes.
5. One small implemented UI improvement that is low-risk.

## Current Maintainer Preference

The maintainer likes practical, high-signal work:

- Do not stop at vibes.
- Name risks directly.
- Keep public-user workflows simple.
- Prefer tested local improvements over broad speculative rewrites.
- If a claim says "works", verify it with build, packaging, logs, or a real camera test.
