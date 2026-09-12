//
//  WindowServer.swift
//  dewey
//

import ApplicationServices
import Cocoa

/// What dewey needs from the window server that has no public API. All
/// of it is looked up with `dlsym` rather than declared, so a symbol
/// that goes away in a later macOS costs the feature that wanted it
/// instead of stopping the app from launching — and every caller has an
/// answer for the symbol not being there, always the answer that keeps
/// a row rather than drops one.
enum WindowServer {
    /// The window an accessibility element stands for. Matching on this
    /// is exact, where matching on a frame and a title is a guess: every
    /// maximized window shares a frame, and the window server and the
    /// accessibility APIs don't always word a title the same way.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow = axWindowID else { return nil }

        var windowID = CGWindowID(0)
        guard getWindow(element, &windowID) == .success else { return nil }

        return windowID
    }

    /// The spaces a window is on. Nil when the question can't be asked;
    /// empty when the window server puts it on no space at all.
    ///
    /// Not a test for whether a window is real: one an app has ordered
    /// out still names the space it was last on. It's only good for
    /// collecting the spaces to ask `windowIDs(inSpaces:)` about.
    static func spaceIDs(of windowID: CGWindowID) -> [Int]? {
        guard let mainConnectionID, let copySpacesForWindows else { return nil }

        let spaces = copySpacesForWindows(
            mainConnectionID(),
            Self.allSpacesMask,
            [Int(windowID)] as CFArray
        )
        guard let spaces else { return [] }

        // Private ABI: nothing is taken on trust about what came back
        // beyond its being an array.
        return (spaces as NSArray).compactMap { ($0 as? NSNumber)?.intValue }
    }

    /// The windows the window server places in `spaceIDs`. A window an
    /// app has ordered out is in none of these lists — not even for the
    /// space it claims — which is what tells it from a window that's
    /// merely on a space you aren't looking at. Nil when the question
    /// can't be asked.
    static func windowIDs(inSpaces spaceIDs: [Int]) -> Set<CGWindowID>? {
        guard let mainConnectionID,
              let copyWindowsWithOptionsAndTags,
              !spaceIDs.isEmpty
        else {
            return nil
        }

        // Bits 0 and 2 of the options argument take in the invisible
        // windows, which is exactly what this is here to leave out, so
        // it asks plainly. Measured, no options value ever brought back
        // an ordered-out window.
        var setTags = 0
        var clearTags = 0
        let windows = copyWindowsWithOptionsAndTags(
            mainConnectionID(),
            0,
            spaceIDs as CFArray,
            0,
            &setTags,
            &clearTags
        )
        guard let windows else { return [] }

        return Set((windows as NSArray).compactMap { ($0 as? NSNumber)?.uint32Value })
    }

    /// Tells the window server which of an application's windows should
    /// be its focused one — including a window on another space, which
    /// nothing public can name.
    ///
    /// Nothing visible happens on its own: the window is designated, not
    /// shown. What it buys is that the app's `kAXFocusedWindow` then
    /// points at it, handing back an accessibility element for a window
    /// `kAXWindows` flatly refuses to list. Raising *that* is what moves
    /// macOS to the window's space, through the same channels it uses
    /// itself — where switching spaces directly would leave the Dock's
    /// idea of them inconsistent.
    static func designateFocusedWindow(windowID: CGWindowID, processID: pid_t) -> Bool {
        guard let setFrontProcessWithOptions, let getProcessForPID else {
            return false
        }

        var psn = ProcessSerialNumber()
        guard getProcessForPID(processID, &psn) == noErr else { return false }

        // Neither call is trusted to say whether it did anything. An app
        // that's already frontmost gives the first nothing to do, and it
        // reports that as failure — which says nothing about whether the
        // window was designated. Only looking settles that, so the
        // caller checks `kAXFocusedWindow` rather than a return code.
        _ = setFrontProcessWithOptions(&psn, windowID, Self.userGeneratedMode)
        postMakeKeyEvent(to: &psn, windowID: windowID)
        return true
    }

    /// Puts dewey at the front, showing nothing of its own.
    ///
    /// macOS follows a window to its space when the window's app comes
    /// *to* the front. An app that's already there has nothing to
    /// follow — raising one of its windows on another space then works
    /// without taking you to it — so this stands in front for an
    /// instant to give the app somewhere to come from.
    static func takeFrontShowingNothing() {
        guard let setFrontProcessWithOptions, let getProcessForPID else { return }

        var psn = ProcessSerialNumber()
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        guard getProcessForPID(ownProcessID, &psn) == noErr else { return }

        // No window is named because none is wanted: dewey has nothing
        // to show, and the point is only to be somewhere else first.
        _ = setFrontProcessWithOptions(&psn, 0, Self.noWindowsMode)
    }

    /// A synthetic left mouse down naming the window it's meant for, at
    /// a point far outside any window so it can't come down on a
    /// control. This is what settles which window the app considers
    /// focused.
    ///
    /// The offsets are into an event record nobody documents, and are
    /// the most fragile thing dewey does.
    private static func postMakeKeyEvent(
        to psn: inout ProcessSerialNumber,
        windowID: CGWindowID
    ) {
        guard let postEventRecordTo else { return }

        var windowID = windowID
        var point = MakeKeyEvent.offContentPoint
        var bytes = [UInt8](repeating: 0, count: MakeKeyEvent.bufferSize)
        bytes[MakeKeyEvent.lengthOffset] = MakeKeyEvent.recordLength
        bytes[MakeKeyEvent.unknownFlagOffset] = MakeKeyEvent.unknownFlagValue
        memcpy(
            &bytes[MakeKeyEvent.windowIDOffset],
            &windowID,
            MemoryLayout<CGWindowID>.size
        )
        memcpy(
            &bytes[MakeKeyEvent.windowLocationOffset],
            &point,
            MemoryLayout<CGPoint>.size
        )
        bytes[MakeKeyEvent.eventTypeOffset] = MakeKeyEvent.leftMouseDown
        _ = postEventRecordTo(&psn, &bytes)
    }

    // MARK: - Symbols

    /// Current, other, and user spaces alike.
    private static let allSpacesMask: CGSSpaceMask = 7
    /// The window server treats the change as something a person asked
    /// for rather than something an app did to itself.
    private static let userGeneratedMode: UInt32 = 0x200
    /// Front, but bring nothing up.
    private static let noWindowsMode: UInt32 = 0x400

    private static let axWindowID = symbol(
        "_AXUIElementGetWindow",
        as: AXWindowIDFunction.self
    )
    private static let mainConnectionID = symbol(
        "CGSMainConnectionID",
        as: CGSMainConnectionIDFunction.self
    )
    private static let copySpacesForWindows = symbol(
        "CGSCopySpacesForWindows",
        as: CGSCopySpacesForWindowsFunction.self
    )
    private static let copyWindowsWithOptionsAndTags = symbol(
        "CGSCopyWindowsWithOptionsAndTags",
        as: CGSCopyWindowsWithOptionsAndTagsFunction.self
    )
    private static let setFrontProcessWithOptions = symbol(
        "_SLPSSetFrontProcessWithOptions",
        as: SLPSSetFrontProcessWithOptionsFunction.self
    )
    private static let postEventRecordTo = symbol(
        "SLPSPostEventRecordTo",
        as: SLPSPostEventRecordToFunction.self
    )
    /// Swift marks this unavailable rather than deprecated, so it can't
    /// be called by name at all — but the symbol is still there to ask
    /// for, and it's the only way to a process's serial number.
    private static let getProcessForPID = symbol(
        "GetProcessForPID",
        as: GetProcessForPIDFunction.self
    )

    private static func symbol<Function>(
        _ name: String,
        as type: Function.Type
    ) -> Function? {
        // RTLD_DEFAULT.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }

        return unsafeBitCast(pointer, to: type)
    }
}

// MARK: -

private typealias CGSConnectionID = UInt32
private typealias CGSSpaceMask = Int32

private typealias AXWindowIDFunction = @convention(c) (
    AXUIElement, UnsafeMutablePointer<CGWindowID>
) -> AXError
private typealias CGSMainConnectionIDFunction = @convention(c) () -> CGSConnectionID
private typealias CGSCopySpacesForWindowsFunction = @convention(c) (
    CGSConnectionID, CGSSpaceMask, CFArray
) -> CFArray?
private typealias CGSCopyWindowsWithOptionsAndTagsFunction = @convention(c) (
    CGSConnectionID,
    Int,
    CFArray,
    Int,
    UnsafeMutablePointer<Int>,
    UnsafeMutablePointer<Int>
) -> CFArray?
private typealias SLPSSetFrontProcessWithOptionsFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
) -> CGError
private typealias SLPSPostEventRecordToFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
) -> CGError
private typealias GetProcessForPIDFunction = @convention(c) (
    pid_t, UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

// MARK: -

/// The shape of the event record `SLPSPostEventRecordTo` takes.
private enum MakeKeyEvent {
    static let bufferSize = 0x100
    static let lengthOffset = 0x04
    static let recordLength: UInt8 = 0xf8
    static let eventTypeOffset = 0x08
    static let leftMouseDown: UInt8 = 0x01
    static let windowLocationOffset = 0x20
    static let offContentPoint = CGPoint(x: 300_000, y: 300_000)
    static let windowIDOffset = 0x3c
    static let unknownFlagOffset = 0x3a
    static let unknownFlagValue: UInt8 = 0x10
}
