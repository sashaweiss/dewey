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
- **Two permissions, both optional**, used only for the open-window rows
  (below):
  - *Screen Recording*, to read window titles. The window list won't ask
    for it on its own the way ScreenCaptureKit would, so dewey asks.
  - *Accessibility*, to raise the particular window a row stands for.

  Both degrade to less, never to broken: without Screen Recording there
  are no window rows at all, and without Accessibility a window row
  activates its app the way an app row does.
- **Private window-server calls are allowed**, and confined to
  `WindowServer.swift`: `_AXUIElementGetWindow`,
  `CGSCopySpacesForWindows`, `CGSCopyWindowsWithOptionsAndTags`,
  `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, and
  `GetProcessForPID` (which Swift marks unavailable rather than merely
  deprecated, so it can only be reached this way).

  Other open-source projects have solved much of this and are worth
  reading — AltTab, for one:
  `src/macos/api-wrappers/SkyLight.framework.swift`. Take signatures,
  constants, and flag meanings from them; write the code here. They're
  references, never dependencies (AltTab is GPL-3.0, dewey unlicensed).

## Open windows

Each window of a running app gets its own row, titled with the window's
title but *scored against the app's name*, so "safari" finds every
Safari window. Every space counts; windows you can't see sort last. An
app with no rows of its own — not running, or every window untitled or
hidden — keeps its plain app row.

A window earns a row if it has a title and the window server would
actually draw it somewhere. A window an app has ordered out — a hidden
menu-bar panel, a preview kept warm — is in no space's window list, and
that is the only thing separating it from a window on a space you
simply aren't looking at. It still *names* the space it was last on, so
space IDs alone won't identify one.

Raising has two cases. On the current space `kAXWindows` lists the
window, so it can be raised directly. Anywhere else it isn't listed at
all: the window server is asked to designate it, `kAXFocusedWindow`
then yields an element for it — the only attribute that will — and
raising that leaves the space switch to macOS.

macOS follows a window to its space only when its app comes *to* the
front, so an app already frontmost has nowhere to come from and
`takeFrontShowingNothing` supplies one. That's the same-app,
different-space case, and it's easy to miss.

Four traps, all of them hit:

- `CGSManagedDisplaySetCurrentSpace` does switch spaces, but bypasses
  Dock.app and leaves Mission Control visibly wrong. `killall Dock`
  puts it right.
- Activating the app after a successful cross-space raise drags its
  other windows up on the space being left. On the current space that
  activate is still needed — raising doesn't bring an app forward.
- `_SLPSSetFrontProcessWithOptions` reports failure when the app is
  already frontmost, which says nothing about whether the window was
  designated. Verify by checking `kAXFocusedWindow`, never by return
  code.
- `window-dump.swift` runs from a terminal, so the app being raised is
  never already frontmost. It passes where dewey fails.

## Building

`./build-release.sh` builds Release and installs to `/Applications`. It
errors out rather than replacing the bundle under a running dewey, so
quit it first. The fixed install path is the point: the Screen Recording
and Accessibility grants are keyed to the bundle identifier and code
signature, so installing there each time keeps them, where running a
copy from somewhere else means granting them again.

`./window-dump.swift` is the bench for the open-window rows — see its
header for what it checks and what it said when the current rules were
written.

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
