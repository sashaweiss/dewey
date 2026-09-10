# dewey

A Spotlight-replacement launcher. Native AppKit (no SwiftUI), macOS only.

## Rules

- **No network requests, ever.** No URLSession, no sockets, no third-party
  dependencies.
- **Filesystem access is read-only**, and limited to:
  - the config JSON, and
  - the directories scanned to produce launcher results (application
    folders, the home directory).

  The app must never write to disk: no UserDefaults, caches, or state
  files.

## Config

- A JSON file, read once at launch. Never written by the app.
- Default location: `~/.config/dewey/config.json`. Overridable via the
  `DEWEY_CONFIG` environment variable (tilde-expanded).
- Symlinks must work everywhere: the config path may be a symlink
  (dotfiles setups), and directory scans follow symlinks.
- A missing config, or any invalid part of one, falls back to defaults.

A reference config lives at `default-config.json` in the repo root,
suitable for symlinking to `~/.config/dewey/config.json`. Example:

```json
{
  "hotKey": "command+space"
}
```

`hotKey` is `+`-separated modifiers then a key. Modifiers: `command`/`cmd`,
`option`/`opt`/`alt`, `control`/`ctrl`, `shift` (at least one required).
Keys: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`. Default:
`option+space`.
