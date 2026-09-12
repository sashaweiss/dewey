//
//  WindowRaiser.swift
//  dewey
//

import ApplicationServices
import Cocoa

/// Brings one specific window of another application to the front.
///
/// No public API raises a window by its window ID, so this goes through
/// the accessibility APIs, matching on the ID the window server gives
/// for each element they report.
///
/// A window on the space being looked at is listed there and can simply
/// be raised. A window anywhere else isn't listed at all, and takes a
/// detour: the window server is asked to name it the app's focused
/// window, which is the one way accessibility will hand over an element
/// for it. Raising that element leaves the space switch to macOS.
enum WindowRaiser {
    /// How long an accessibility call to another app may take before
    /// giving up. The default is several seconds, which is a long time
    /// to spend on an app that's wedged.
    private static let messagingTimeout: Float = 0.5

    /// How long to keep looking for the window to become the focused
    /// one. It's usually true immediately, but not when the app was
    /// already frontmost and only its window is changing.
    private static let designationAttempts = 10
    private static let designationInterval: useconds_t = 20_000

    static func raise(_ window: OpenWindow) {
        guard let application = NSRunningApplication(
            processIdentifier: window.processID
        ) else {
            return
        }

        // Accessibility calls block on the app being asked, so they stay
        // off the main thread. The panel is already dismissed by now, so
        // there's nothing of ours left to hold up.
        DispatchQueue.global(qos: .userInitiated).async {
            if application.isHidden {
                application.unhide()
            }

            let needsActivating = window.isOnScreen
                ? raiseOnThisSpace(window)
                : !raiseFromAnotherSpace(window)

            guard needsActivating else { return }

            DispatchQueue.main.async {
                application.activate()
            }
        }
    }

    /// A window on the space being looked at. Always wants the app
    /// activated afterwards: raising a window within its app doesn't
    /// bring the app forward.
    private static func raiseOnThisSpace(_ window: OpenWindow) -> Bool {
        guard isTrusted(), let element = axWindow(matching: window) else { return true }

        // Being the main window is what survives the app coming forward;
        // raising puts it above that app's others.
        _ = AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return true
    }

    /// A window on another space, which accessibility won't list. Having
    /// the window server name it as focused is what makes it reachable;
    /// raising it from there moves macOS to its space.
    ///
    /// Returns whether that worked, because when it does the app is
    /// already frontmost — and activating it again drags its other
    /// windows up on the space being left behind.
    private static func raiseFromAnotherSpace(_ window: OpenWindow) -> Bool {
        guard isTrusted() else { return false }

        // The space only follows an app coming *to* the front, so an app
        // that's already there needs somewhere to come from.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == window.processID {
            WindowServer.takeFrontShowingNothing()
        }

        guard WindowServer.designateFocusedWindow(
            windowID: window.windowID,
            processID: window.processID
        ) else {
            return false
        }

        let application = AXUIElementCreateApplication(window.processID)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)

        for attempt in 0..<Self.designationAttempts {
            if attempt > 0 {
                usleep(Self.designationInterval)
            }
            guard let element = focusedWindow(of: application),
                  WindowServer.windowID(of: element) == window.windowID
            else {
                continue
            }

            return AXUIElementPerformAction(
                element,
                kAXRaiseAction as CFString
            ) == .success
        }

        return false
    }

    /// An app's focused window — the one attribute that names a window
    /// on another space, where `kAXWindows` leaves it out entirely.
    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        var copied: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &copied
        ) == .success,
              let copied,
              CFGetTypeID(copied) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (copied as! AXUIElement)
    }

    /// Whether dewey is allowed to drive other apps' windows, asking for
    /// permission the first time it isn't.
    private static func isTrusted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// The accessibility element for `window`, matched on window ID. Nil
    /// when the window isn't in the app's list at all, which is what a
    /// window on another space looks like from here.
    private static func axWindow(matching window: OpenWindow) -> AXUIElement? {
        let application = AXUIElementCreateApplication(window.processID)
        _ = AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var copied: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &copied
        ) == .success,
              let elements = copied as? [AXUIElement]
        else {
            return nil
        }

        return elements.first { element in
            WindowServer.windowID(of: element) == window.windowID
        }
    }
}
