# dewey

A Spotlight-replacement launcher. Native AppKit (no SwiftUI), macOS only.

## Rules

- **No network requests, ever.** No URLSession, no sockets, no third-party
  dependencies.
- **Filesystem access is limited to:**
  - the config JSON, and
  - the directories scanned to produce launcher results (application
    folders, the home directory, iCloud Drive).

  Access is read-only with exactly one exception: seeding the config file
  on first run (see below). No UserDefaults, caches, or state files.

## Config

- A JSON file, read once at launch.
- Default location: `~/.config/dewey/config.json`. Overridable via the
  `DEWEY_CONFIG` environment variable (tilde-expanded).
- Symlinks must work everywhere: the config path may be a symlink
  (dotfiles setups), and directory scans follow symlinks.
- A missing config, or any invalid part of one, falls back to defaults.
- On first run the app seeds the file by copying the bundled
  `default-config.json`, and only when nothing exists at the resolved
  path. An existing config is never read-modified-written, never
  reformatted, and never overwritten.

The reference config lives at `dewey/default-config.json`. It ships as a
bundle resource (the app copies it when seeding), and is also suitable for
symlinking to `~/.config/dewey/config.json`. Example:

```json
{
  "hotKey": "command+space"
}
```

`hotKey` is `+`-separated modifiers then a key. Modifiers: `command`/`cmd`,
`option`/`opt`/`alt`, `control`/`ctrl`, `shift` (at least one required).
Keys: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`. Default:
`option+space`.
