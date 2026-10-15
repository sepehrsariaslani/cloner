# Cloner

A small native macOS app for creating and managing renamed copies of `.app` bundles. Cloner leaves the source app untouched and stores copies under `~/Applications/Cloner/`.

## Features

- Select an installed macOS app and create a copy with a new bundle identifier.
- Re-sign the copy ad hoc while removing Team ID, App ID, Keychain group, and App Group entitlements that macOS cannot honor on an ad hoc signature.
- Give Electron and Chromium based apps a separate `--user-data-dir` profile so they can start beside the original instance.
- Open, reveal, and move managed copies to Trash.
- Use the custom Cloner app icon from `Resources/AppIcon.png` (or `.jpg`); the build script converts it to the `.icns` file in the app bundle.

The interface and Persian usage guide are in [README.fa.md](README.fa.md).

## Build

Requires Swift 5.9+ and the macOS SDK. Full Xcode is not needed.

```sh
swift build --package-path . --configuration release
./scripts/build-app.sh
```

## Limits

Ad hoc signing does not replace Developer ID signing or notarization. App-specific capabilities that require the original Team ID, App ID, Keychain group, or App Group are removed and may stop working. Cloner does not copy account data, transfer settings, or fully isolate Keychain and shared containers. New Chromium based profiles start clean.

This is an independent implementation informed by local static analysis with [REA](https://github.com/morluto/rea); it contains no MacDupl code or assets.
