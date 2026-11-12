//
//  LauncherPanel.swift
//  dewey
//

import Cocoa

/// A borderless, non-activating panel that can take keyboard focus without
/// activating the app, so the frontmost app keeps focus while the launcher
/// is up.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The app is never active while this panel is key, so main-menu key
    // equivalents may not fire. Handle the essential editing ones here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command else { return false }

        switch event.charactersIgnoringModifiers {
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case ",":
            return NSApp.sendAction(
                #selector(AppDelegate.showSettings(_:)),
                to: nil,
                from: self
            )
        default:
            return false
        }
    }
}
