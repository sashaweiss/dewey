//
//  OpenWindowSource.swift
//  dewey
//

import Cocoa

/// Finds titled, visible windows of running apps, across every space,
/// matched by their app's name.
struct OpenWindowSource: LauncherItemSource {
    /// Smaller windows are palettes, HUDs, and the like.
    private static let minimumWindowSide: CGFloat = 120

    /// Screen Recording, needed for window titles, is asked for once a run.
    private static var hasAskedForScreenRecording = false

    func loadItems() -> [LauncherItem] {
        guard Self.hasScreenRecordingAccess() else { return [] }

        let candidates = Self.candidates()
        let shownWindowIDs = Self.shownWindowIDs(among: candidates)

        return candidates
            .filter { Self.isShown($0, among: shownWindowIDs) }
            .map { candidate in
                LauncherItem(
                    kind: .applicationWindow(candidate.window),
                    name: candidate.applicationName,
                    // The app's own URL, so the row shows the app's icon
                    // and so the app's own row knows to step aside.
                    url: candidate.applicationURL
                )
            }
    }

    // MARK: - Permission

    private static func hasScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        guard !hasAskedForScreenRecording else { return false }

        hasAskedForScreenRecording = true
        Logger.info(
            "Asking for Screen Recording; without it there are no window rows."
        )
        return CGRequestScreenCaptureAccess()
    }

    // MARK: - Gathering

    /// A window that's cleared the cheap tests, waiting on the question
    /// only the window server can answer: is it being shown anywhere?
    private struct Candidate {
        let window: OpenWindow
        let applicationName: String
        let applicationURL: URL
    }

    private static func candidates() -> [Candidate] {
        let entries = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        var applicationsByProcessID = [pid_t: NSRunningApplication]()
        for application in NSWorkspace.shared.runningApplications
        where application.processIdentifier != ownProcessID {
            applicationsByProcessID[application.processIdentifier] = application
        }

        var candidates = [Candidate]()

        // Best-effort front-to-back: the list's order isn't guaranteed,
        // but it's the only ordering on offer, and a wrong guess only
        // shuffles one app's rows among themselves.
        for (stackOrder, entry) in entries.enumerated() {
            // Layer zero is the ordinary document window layer; anything
            // above it is a panel, HUD, or status window.
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let processID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let bounds = boundsOf(entry),
                  bounds.width >= minimumWindowSide,
                  bounds.height >= minimumWindowSide,
                  let title = (entry[kCGWindowName as String] as? String)?.strippedOrNil,
                  let application = applicationsByProcessID[processID],
                  let applicationName = application.localizedName,
                  let bundleURL = application.bundleURL
            else {
                continue
            }

            candidates.append(Candidate(
                window: OpenWindow(
                    windowID: windowID,
                    processID: processID,
                    title: title,
                    isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
                    stackOrder: stackOrder
                ),
                applicationName: applicationName,
                applicationURL: bundleURL.resolvingSymlinksInPath()
            ))
        }

        return candidates
    }

    private static func boundsOf(_ entry: [String: Any]) -> CGRect? {
        guard let dictionary = entry[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }

        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    // MARK: - Is it being shown?

    /// The windows the window server is actually drawing, out of the
    /// spaces the candidates live on. Nil when it couldn't be asked.
    private static func shownWindowIDs(among candidates: [Candidate]) -> Set<CGWindowID>? {
        let spaceIDs = candidates
            .compactMap { WindowServer.spaceIDs(of: $0.window.windowID) }
            .flatMap { $0 }
        return WindowServer.windowIDs(inSpaces: Array(Set(spaceIDs)))
    }

    /// Whether the window server would draw this window anywhere. One an
    /// app has ordered out — a hidden menu-bar panel, a preview kept
    /// warm — is in no space's window list, whatever space it claims to
    /// be on, and there's nothing for a row to take you to.
    private static func isShown(
        _ candidate: Candidate,
        among shownWindowIDs: Set<CGWindowID>?
    ) -> Bool {
        // Never drop a window that's in front of you, and never drop
        // anything at all if the window server couldn't be asked.
        guard let shownWindowIDs, !candidate.window.isOnScreen else { return true }

        return shownWindowIDs.contains(candidate.window.windowID)
    }
}

// MARK: -

private extension String {
    var strippedOrNil: String? {
        let stripped = trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
