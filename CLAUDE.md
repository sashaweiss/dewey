# dewey

A launcher app like Spotlight. Native AppKit (no SwiftUI), macOS only.

## Rules

These are non-negotiable.

- No network requests, ever.
- Persistence is limited to the config JSON.
    - All other filesystem access must be read-only.

## Inspiration from other projects

- Many other open-source projects exist that have implemented similar features. They may be helpful as a reference.
    - For example, AltTab: `src/macos/api-wrappers/SkyLight.framework.swift`.

## Config

- A JSON file, read once at launch.
- Symlinks must work everywhere: the config path may be a symlink.
