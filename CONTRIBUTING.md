# Contributing

Thanks for helping improve Open Nikon Importer.

## Useful Reports

Camera compatibility is the most useful contribution right now. Please include:

- macOS version
- camera model and firmware version
- connection mode selected on the camera
- file extensions that work or fail
- whether a same-basename proxy file exists
- the exact error shown by the app

Do not upload private media files unless you intentionally want them public.

## Development

```sh
cd App
swift build -c release --product ZRImporter
```

Package a local `.app` bundle:

```sh
./Scripts/package-app.sh
```

## Pull Requests

- Keep camera import behavior conservative: never delete media from the camera by default.
- Keep privacy local-first: no analytics, no account system, no background uploads.
- Prefer small, reproducible camera probes over broad refactors.
- Include the camera model and macOS version used for verification.
