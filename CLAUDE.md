# dewey

A Spotlight-replacement launcher. Native AppKit (no SwiftUI), macOS only.

## Rules

These are non-negotiable.

- We make no network requests, ever.
- We don't persist anything ourselves, besides the config JSON.
    - All other filesystem access must be read-only.

## Inspiration from other projects

- Many other open-source projects exist that have implemented similar features. Feel free to explore them for inspiration.
    - For example, AltTab: `src/macos/api-wrappers/SkyLight.framework.swift`.
    - These are references, never dependencies, and should never be copied wholesale.

## Search results

A typed search query searches a variety of locations, including:

- Open application windows (via Accessibility and ScreenCapture APIs)
- `/Applications`
- `$HOME`
- Xcode-vendored applications

## window-dump.swift

A testbed for exploring the Accessibility and Screen Capture APIs.

## Config

- A JSON file, read once at launch.
- Default location: `~/.config/dewey/config.json`, overridable via `DEWEY_CONFIG`.
- Symlinks must work everywhere: the config path may be a symlink.
- Seeded on first run if none exists, using `default-config.json`.
