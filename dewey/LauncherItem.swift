//
//  LauncherItem.swift
//  dewey
//

import Cocoa

/// A single openable result in the launcher: an application or a directory.
struct LauncherItem {
    enum Kind {
        case application
        case directory
    }

    let kind: Kind
    let name: String
    let url: URL

    var subtitle: String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
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
        }
    }
}
