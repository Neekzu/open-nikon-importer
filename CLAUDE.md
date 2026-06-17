# Claude Handoff

This repository is a public macOS SwiftUI utility called **Open Nikon Importer**.

Start with:

- [docs/handoffs/2026-06-17-claude-audit-handoff.md](docs/handoffs/2026-06-17-claude-audit-handoff.md)
- [README.md](README.md)
- [docs/INSTALL.md](docs/INSTALL.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)

Primary request from the project owner:

> Audit the app end to end, identify what is still risky or missing before a broader public release, and propose or implement a more polished premium camera-importer UI. The UI may feel Nikon-adjacent in quality and photographic seriousness, but must not copy Nikon logos, official trade dress, or imply affiliation.

Important constraints:

- Do not delete camera files by default.
- Do not add analytics, account login, cloud upload, or telemetry.
- Do not enable auto-update until signing/notarization/Sparkle appcast security is complete.
- Keep install flow simple for non-technical users.
- Preserve the proven Nikon ZR N-RAW `.NEV` transfer path unless you can verify a safer improvement.
