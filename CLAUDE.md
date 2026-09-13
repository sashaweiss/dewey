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

## Xcode's vendored apps

Xcode ships applications of its own (Instruments, Simulator, Create ML)
inside its bundle, under `Contents/Applications` and
`Contents/Developer/Applications`. The ordinary application scan doesn't
descend into packages, so they get their own source, which asks
LaunchServices for every installed Xcode rather than guessing at names
and locations.

They answer to "Xcode" as well as to their own names, via a
`LauncherItem`'s `alternateNames`. An alternate name is only consulted
when the name itself doesn't match, and always ranks below every match
on a name, so "xcode" turns up Xcode's own windows and row first and the
vendored apps after. A vendored app that's running steps aside for its
window rows the way any app does, handing them its alternate names on
the way out.

## Building

`./build-release.sh` archives Release, exports it signed for Developer
ID, notarizes it, staples the ticket, and leaves `dist/dewey.app` and a
zip of it. It installs nothing — where the app goes is yours to decide,
but decide once: the Screen Recording and Accessibility grants are keyed
to the bundle identifier and code signature, so a copy run from
somewhere else asks for both again.

A Developer ID signature is not the one Xcode's own builds carry, so
those two are separate apps as far as the grants are concerned. Running
from Xcode and running a build from here means granting each of them.

The archive action needs a scheme where the old plain build didn't, and
gets one without a scheme file in the repo: with Xcode set to autocreate
schemes, both it and `xcodebuild` conjure a `dewey` scheme from the
target. Ticking Shared doesn't write one out — an autocreated scheme is
never persisted — which is also why archiving logs that the scheme's
supported platforms are empty. The archive is correct regardless.

Export is left on automatic signing: it picks the Developer ID identity
from the export method, and `-allowProvisioningUpdates` fetches the
profile carrying the enhanced-security entitlements rather than making
one a checked-in file that expires.

Notarizing reads credentials from a keychain profile named `dewey`
(`NOTARY_PROFILE` overrides), stored once by running `xcrun notarytool
store-credentials dewey` and answering its prompts. A rejection reports
only "Invalid"; `xcrun notarytool log <id>`, with the submission id the
script prints, says what was wrong.

Every step there is one the app can't ship without. Checks on top of
them earned nothing and cost twice: `notarytool history --limit`, which
doesn't take that flag and so condemned working credentials, and
`spctl --assess`, which called an app "Unnotarized Developer ID"
minutes after Apple accepted it. Notarization succeeding and
`stapler staple` succeeding are the signals — stapling validates the
ticket against the bundle on its way, so there's nothing left to
confirm afterwards.

`./window-dump.swift` is the bench for the open-window rows — see its
header for what it checks and what it said when the current rules were
written.

## Enhanced security

`ENABLE_ENHANCED_SECURITY` is on for the project. It's an umbrella
setting: pointer authentication, stack zero-init, typed allocators and
the security warnings all default from it, so a newer Xcode adding
another one turns it on here too. Don't pin them one by one.

`dewey/dewey.entitlements` opts into the runtime half. It follows the
set Xcode's Enhanced Security capability writes, plus
`checked-allocations` for memory tagging. That last one needs EMTE
hardware to do anything, and a VM doesn't report it however capable the
host is, so it goes untested unless someone builds on the metal. The
`WindowServer.swift` calls are what would trip it first, and
`...checked-allocations.soft-mode` downgrades a kill to a report if it
comes to that.

Entitlements aren't part of what the Screen Recording and Accessibility
grants are keyed to, so adding them doesn't cost the permissions.
Automatic signing does have to put them in a profile, which is a new way
for a build to fail.

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
