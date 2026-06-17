# Security Policy

Open Nikon Importer touches local camera media and filesystem paths, so reports about unsafe writes, unexpected deletion, or update-signing weaknesses matter.

## Supported Versions

Until the first public release, only the `main` branch is supported.

## Reporting

Please open a GitHub issue for non-sensitive bugs. For sensitive reports, avoid attaching private media, serial numbers, or personal folder listings publicly. Share the smallest reproduction steps possible.

## Project Rules

- The app must not delete camera files unless a future explicit, opt-in delete workflow is added.
- The app must not upload media or metadata.
- Auto-update must not ship without signed releases and a documented release process.
