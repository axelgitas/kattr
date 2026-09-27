# Kattr

Customizable search

![kattr with custom images](.github/screenshot.png)

A customization-focused fork of Search with personalized backgrounds, frosted glass atmosphere, custom artwork, and native Liquid Glass styling.

## Features & Customization

- **Custom Appearance:** Configure Light and Dark mode background colors, adjust Blur Surface frosted glass diffusion, and fine-tune Glass Tint overlays.
- **Artwork System:** Set custom New Tab and Chrome artwork with independent opacity and atmosphere controls.
- **Liquid Glass:** Native macOS 26 Liquid Glass optical refraction layers positioned above or below artwork.
- **Search 1.0.4 Capabilities:** Multi-window browsing, tab groups, right-side sidebar, custom keyboard shortcuts, AppleScript automation, bookmark folders, and tab switching.

## Building

- macOS 14 or later, Xcode 16 / Swift 6 toolchain
- `swift build` — builds the app binary
- `./build.sh` — builds and signs double-clickable `Kattr.app` in `build/`
- `./build.sh release dmg` — packages `Kattr.dmg` and `Kattr.zip`
