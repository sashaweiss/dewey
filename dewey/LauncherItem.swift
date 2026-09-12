//
//  LauncherItem.swift
//  dewey
//

import Cocoa

/// A single openable result in the launcher: an application, one of a
/// running application's windows, or a directory.
struct LauncherItem {
    enum Kind {
        case application
        case directory
        case applicationWindow(OpenWindow)
    }

    let kind: Kind
    /// What the fuzzy matcher scores against. A window is scored by its
    /// application's name, so "safari" turns up Safari's windows however
    /// they happen to be titled.
    let name: String
    /// The application bundle or directory. A window carries its
    /// application's, so it shows the same icon, and so the
    /// application's own row knows to step aside for it.
    let url: URL
    /// Stands in for the file's own icon when set, for items that deserve
    /// something more distinctive than a generic folder.
    var customIcon: NSImage?

    /// Set for the rows that stand for a window rather than a file.
    var window: OpenWindow? {
        switch kind {
        case .application, .directory:
            return nil
        case .applicationWindow(let window):
            return window
        }
    }

    /// The row's headline. A window leads with its title, since that's
    /// what distinguishes it from its app's other windows.
    var title: String {
        switch kind {
        case .application, .directory:
            return name
        case .applicationWindow(let window):
            return window.title
        }
    }

    var subtitle: String {
        switch kind {
        case .application, .directory:
            return (url.path as NSString).abbreviatingWithTildeInPath
        case .applicationWindow:
            return name
        }
    }

    var icon: NSImage {
        customIcon ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    func open() {
        switch kind {
        case .application:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration,
                completionHandler: nil
            )
        case .directory:
            NSWorkspace.shared.open(url)
        case .applicationWindow(let window):
            WindowRaiser.raise(window)
        }
    }
}
