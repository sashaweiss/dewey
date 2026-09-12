#!/usr/bin/env swift
//
//  window-dump.swift
//  dewey
//
//  The bench for dewey's open-window rows, kept outside `dewey/` so the
//  project's synchronized group doesn't compile it into the app. It
//  isn't built or shipped; it's run by hand.
//
//  Reach for it when:
//
//  * a macOS update lands, to check the private calls still answer the
//    way the rules in `OpenWindowSource` assume;
//  * a window turns up as a row that you can't see anywhere, or one you
//    can see doesn't turn up;
//  * a new private call is being considered — try it here first, in a
//    process worth nothing, because a signature recited wrong crashes
//    rather than failing gracefully.
//
//  It prints the windows dewey would row, what the accessibility APIs
//  make of each, which spaces each is on, and which the window server
//  would actually draw.
//
//  What it said when the current rules were written, on macOS 26.6 —
//  a deviation here is the thing to look at first:
//
//  * Every on-screen row matched an AX window on `idMatches`, via
//    `_AXUIElementGetWindow`. That's what `WindowRaiser` relies on.
//    Titles did *not* always match ("00 Pro" against Device Hub's
//    "00 Pro – iOS 26.5"), and frames matched windows that weren't the
//    right one, since every maximized window shares a frame.
//  * No offscreen row matched an AX window at all: the accessibility
//    APIs only report the space being looked at. An app whose windows
//    were all elsewhere reported zero AX windows.
//  * `CGSCopySpacesForWindows` named a space for every window except an
//    ordered-out one, which named none. But an ordered-out window that
//    had once been shown still named the space it was last on, so a
//    space ID alone doesn't identify one.
//  * `CGSCopyWindowsWithOptionsAndTags` left ordered-out windows out of
//    every space's list — including the space they claimed. That is the
//    filter `OpenWindowSource.isShown(_:among:)` uses. Varying the
//    options argument changed which other windows came back but never
//    that, which is why it's passed as zero.
//  * `kAXFocusedWindow` named a window on another space that
//    `kAXWindows` refused to list, once the window server had been
//    asked to designate it. That one attribute is the whole of how
//    `WindowRaiser` reaches across a space.
//  * The `space` variant switched spaces and left Mission Control
//    inconsistent, because it moves the window server without telling
//    Dock.app. It's kept as a record of what not to do. `killall Dock`
//    puts it right.
//
//  Careful what a green result means: this runs from a terminal, so the
//  app being raised is never already frontmost, and `slps3` passes here
//  where dewey fails. See the front-transition note in CLAUDE.md.
//
//  Run it as `swift window-dump.swift`, or `./window-dump.swift`. The
//  *terminal* needs Screen Recording, or every title comes back empty
//  and every window filters out, and Accessibility for the AX sections.

import ApplicationServices
import Cocoa

// MARK: - dewey's filters, mirrored by hand

let minimumWindowSide: CGFloat = 120
let ordinaryWindowLayer = 0

struct Window {
    let windowID: Int
    let processID: pid_t
    let applicationName: String
    let title: String
    let layer: Int
    /// Screen coordinates, origin at the top left of the primary
    /// display — the convention `SCWindow.frame` uses too.
    let bounds: CGRect
    let alpha: Double
    let sharingState: Int
    let isOnScreen: Bool

    var sharingStateName: String {
        switch sharingState {
        case 0: return "none"
        case 1: return "readOnly"
        case 2: return "readWrite"
        default: return "?(\(sharingState))"
        }
    }
}

/// The same gauntlet `OpenWindowSource.candidates(in:)` runs: an
/// ordinary window layer, big enough to be somewhere you'd switch to,
/// titled, and owned by a real application bundle.
func passesDeweyFilters(_ window: Window) -> Bool {
    return window.layer == ordinaryWindowLayer
        && window.bounds.width >= minimumWindowSide
        && window.bounds.height >= minimumWindowSide
        && !window.title.isEmpty
}

// MARK: - Reading the window list

func parse(_ entry: [String: Any]) -> Window? {
    guard let windowID = entry[kCGWindowNumber as String] as? Int,
          let processID = entry[kCGWindowOwnerPID as String] as? pid_t,
          let layer = entry[kCGWindowLayer as String] as? Int,
          let boundsDictionary = entry[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(
            dictionaryRepresentation: boundsDictionary as CFDictionary
          )
    else {
        return nil
    }

    // dewey resolves the owner through NSWorkspace and ignores anything
    // that isn't a bundled app, so daemons' windows never become rows.
    let application = NSRunningApplication(processIdentifier: processID)
    guard let application, application.bundleURL != nil else { return nil }

    let title = (entry[kCGWindowName as String] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return Window(
        windowID: windowID,
        processID: processID,
        applicationName: application.localizedName ?? "(unnamed)",
        title: title ?? "",
        layer: layer,
        bounds: bounds,
        alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
        sharingState: entry[kCGWindowSharingState as String] as? Int ?? -1,
        isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
    )
}

/// Every display's frame, flipped into the window server's coordinates so
/// it can be compared against a window's bounds.
func displayFrames() -> [CGRect] {
    guard let primary = NSScreen.screens.first else { return [] }

    let primaryHeight = primary.frame.height
    return NSScreen.screens.map { screen in
        var frame = screen.frame
        frame.origin.y = primaryHeight - frame.maxY
        return frame
    }
}

// MARK: - Accessibility

struct AXWindow {
    let title: String
    let isMinimized: Bool
    let frame: CGRect?
    /// From `_AXUIElementGetWindow`, when that symbol is there.
    let windowID: CGWindowID?
}

/// Kept apart so "the query failed" can't be mistaken for "the app has
/// no windows" — the distinction the last run couldn't make.
enum AXWindowsResult {
    case windows([AXWindow])
    case queryFailed(AXError)
    case unexpectedValue
}

func axErrorName(_ error: AXError) -> String {
    switch error {
    case .success: return "success"
    case .failure: return "failure"
    case .illegalArgument: return "illegalArgument"
    case .invalidUIElement: return "invalidUIElement"
    case .invalidUIElementObserver: return "invalidUIElementObserver"
    case .cannotComplete: return "cannotComplete"
    case .attributeUnsupported: return "attributeUnsupported"
    case .actionUnsupported: return "actionUnsupported"
    case .notificationUnsupported: return "notificationUnsupported"
    case .notImplemented: return "notImplemented"
    case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
    case .notificationNotRegistered: return "notificationNotRegistered"
    case .apiDisabled: return "apiDisabled"
    case .noValue: return "noValue"
    case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: return "notEnoughPrecision"
    @unknown default: return "unknown(\(error.rawValue))"
    }
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var copied: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &copied
    ) == .success else {
        return nil
    }

    return (copied as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var copied: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &copied
    ) == .success else {
        return nil
    }

    return copied as? Bool
}

func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    var copied: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &copied
    ) == .success,
          let copied,
          CFGetTypeID(copied) == AXValueGetTypeID()
    else {
        return nil
    }

    return (copied as! AXValue)
}

/// The same position-and-size pair `WindowRaiser` matches against.
func axFrame(_ element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = axValue(element, kAXPositionAttribute),
          AXValueGetValue(positionValue, .cgPoint, &position),
          let sizeValue = axValue(element, kAXSizeAttribute),
          AXValueGetValue(sizeValue, .cgSize, &size)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

// MARK: - Private symbols
//
// Looked up with dlsym rather than declared, so a symbol that's gone is
// a skipped section instead of a process that won't start.

typealias CGSConnectionID = Int32
typealias CGSSpaceMask = Int32

/// Current | others | user.
let cgsAllSpacesMask: CGSSpaceMask = 7

typealias AXGetWindowFunction = @convention(c) (
    AXUIElement, UnsafeMutablePointer<CGWindowID>
) -> AXError
typealias CGSMainConnectionFunction = @convention(c) () -> CGSConnectionID
typealias CGSCopySpacesFunction = @convention(c) (
    CGSConnectionID, CGSSpaceMask, CFArray
) -> CFArray?
typealias GetProcessForPIDFunction = @convention(c) (
    pid_t, UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus
typealias SLPSSetFrontFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32
) -> CGError
typealias SLPSPostEventFunction = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>
) -> CGError
typealias CGSCopyDisplayForSpaceFunction = @convention(c) (
    CGSConnectionID, UInt64
) -> CFString?
typealias CGSSetCurrentSpaceFunction = @convention(c) (
    CGSConnectionID, CFString, UInt64
) -> Void
typealias CGSCopyWindowsFunction = @convention(c) (
    CGSConnectionID,
    Int,
    CFArray,
    Int,
    UnsafeMutablePointer<Int64>,
    UnsafeMutablePointer<Int64>
) -> CFArray?

func privateSymbol<Function>(_ name: String, as type: Function.Type) -> Function? {
    // RTLD_DEFAULT.
    guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
        return nil
    }

    return unsafeBitCast(pointer, to: type)
}

let axGetWindow = privateSymbol("_AXUIElementGetWindow", as: AXGetWindowFunction.self)
let cgsMainConnection = privateSymbol(
    "CGSMainConnectionID",
    as: CGSMainConnectionFunction.self
)
let cgsCopySpaces = privateSymbol(
    "CGSCopySpacesForWindows",
    as: CGSCopySpacesFunction.self
)
let cgsCopyWindows = privateSymbol(
    "CGSCopyWindowsWithOptionsAndTags",
    as: CGSCopyWindowsFunction.self
)
let getProcessForPID = privateSymbol(
    "GetProcessForPID",
    as: GetProcessForPIDFunction.self
)
let slpsSetFront = privateSymbol(
    "_SLPSSetFrontProcessWithOptions",
    as: SLPSSetFrontFunction.self
)
let slpsPostEvent = privateSymbol(
    "SLPSPostEventRecordTo",
    as: SLPSPostEventFunction.self
)
let cgsCopyDisplayForSpace = privateSymbol(
    "CGSCopyManagedDisplayForSpace",
    as: CGSCopyDisplayForSpaceFunction.self
)
let cgsSetCurrentSpace = privateSymbol(
    "CGSManagedDisplaySetCurrentSpace",
    as: CGSSetCurrentSpaceFunction.self
)

/// The event record that tells an app to treat a window as key. Same
/// offsets the app uses.
enum MakeKeyEvent {
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

func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    guard let axGetWindow else { return nil }

    var windowID = CGWindowID(0)
    guard axGetWindow(element, &windowID) == .success else { return nil }

    return windowID
}

/// The spaces a window belongs to. Nil means the call couldn't be made
/// at all; empty means the window server places it on no space, which is
/// what an ordered-out window looks like.
func spaceIDs(of windowID: Int) -> [Int]? {
    guard let cgsMainConnection, let cgsCopySpaces else { return nil }

    let result = cgsCopySpaces(
        cgsMainConnection(),
        cgsAllSpacesMask,
        [windowID] as CFArray
    )
    guard let result else { return [] }

    // Deliberately defensive: this is unverified ABI, so nothing is
    // assumed about what came back beyond its being a CFArray.
    return (result as NSArray).compactMap { ($0 as? NSNumber)?.intValue }
}

/// The windows the window server places in `spaceIDs`. `options` is the
/// interesting part: 0 asks for all of them, 2 asks only for the ones
/// that are ordered in — the ones it would actually draw on their space.
/// That second answer doesn't depend on which space the question is
/// asked from, which is what makes it a filter rather than a coincidence.
func windowIDs(inSpaces spaceIDs: [Int], options: Int) -> [Int]? {
    guard let cgsMainConnection, let cgsCopyWindows, !spaceIDs.isEmpty else {
        return nil
    }

    var setTags = Int64(0)
    var clearTags = Int64(0)
    let result = cgsCopyWindows(
        cgsMainConnection(),
        0,
        spaceIDs as CFArray,
        options,
        &setTags,
        &clearTags
    )
    guard let result else { return [] }

    return (result as NSArray).compactMap { ($0 as? NSNumber)?.intValue }
}

/// `kAXWindows` read through the ranged accessor instead of the plain
/// one. Some apps hand the plain `AXUIElementCopyAttributeValue` a
/// truncated list, so this asks how many there are and then asks for
/// exactly that many.
func axWindowsRanged(ofProcess processID: pid_t) -> AXWindowsResult {
    let application = AXUIElementCreateApplication(processID)
    _ = AXUIElementSetMessagingTimeout(application, 2)

    var count: CFIndex = 0
    let countError = AXUIElementGetAttributeValueCount(
        application,
        kAXWindowsAttribute as CFString,
        &count
    )
    guard countError == .success else { return .queryFailed(countError) }
    guard count > 0 else { return .windows([]) }

    var values: CFArray?
    let error = AXUIElementCopyAttributeValues(
        application,
        kAXWindowsAttribute as CFString,
        0,
        count,
        &values
    )
    guard error == .success else { return .queryFailed(error) }
    guard let elements = values as? [AXUIElement] else { return .unexpectedValue }

    return .windows(elements.map { element in
        AXWindow(
            title: axString(element, kAXTitleAttribute) ?? "",
            isMinimized: axBool(element, kAXMinimizedAttribute) ?? false,
            frame: axFrame(element),
            windowID: axWindowID(element)
        )
    })
}

/// How many windows the app says it has, which needn't match how many
/// either accessor hands over.
func axWindowCount(ofProcess processID: pid_t) -> CFIndex? {
    let application = AXUIElementCreateApplication(processID)
    _ = AXUIElementSetMessagingTimeout(application, 2)

    var count: CFIndex = 0
    guard AXUIElementGetAttributeValueCount(
        application,
        kAXWindowsAttribute as CFString,
        &count
    ) == .success else {
        return nil
    }

    return count
}

func axWindows(ofProcess processID: pid_t) -> AXWindowsResult {
    let application = AXUIElementCreateApplication(processID)
    _ = AXUIElementSetMessagingTimeout(application, 2)

    var copied: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
        application,
        kAXWindowsAttribute as CFString,
        &copied
    )
    guard error == .success else { return .queryFailed(error) }
    guard let elements = copied as? [AXUIElement] else { return .unexpectedValue }

    return .windows(elements.map { element in
        AXWindow(
            title: axString(element, kAXTitleAttribute) ?? "",
            isMinimized: axBool(element, kAXMinimizedAttribute) ?? false,
            frame: axFrame(element),
            windowID: axWindowID(element)
        )
    })
}

/// `WindowRaiser`'s own tolerance.
func isWithinTolerance(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    return abs(lhs.minX - rhs.minX) <= 1
        && abs(lhs.minY - rhs.minY) <= 1
        && abs(lhs.width - rhs.width) <= 1
        && abs(lhs.height - rhs.height) <= 1
}

// MARK: - Formatting

func describe(_ rect: CGRect) -> String {
    return String(
        format: "(%.0f, %.0f) %.0f x %.0f",
        rect.origin.x,
        rect.origin.y,
        rect.width,
        rect.height
    )
}

func describe(_ window: Window, intersectsDisplay: Bool) -> String {
    return [
        "id=\(window.windowID)",
        "bounds=\(describe(window.bounds))",
        String(format: "alpha=%.2f", window.alpha),
        "sharing=\(window.sharingStateName)",
        "onDisplay=\(intersectsDisplay ? "yes" : "NO")",
    ].joined(separator: "  ")
}

func printGroup(_ heading: String, _ windows: [Window], _ frames: [CGRect]) {
    print("")
    print("\(heading) (\(windows.count))")
    guard !windows.isEmpty else {
        print("  --")
        return
    }

    let byApplication = Dictionary(grouping: windows, by: \.applicationName)
    for name in byApplication.keys.sorted() {
        print("  \(name)")
        let group = (byApplication[name] ?? [])
            .sorted { $0.windowID < $1.windowID }
        for window in group {
            let intersects = frames.contains { $0.intersects(window.bounds) }
            print("    \"\(window.title)\"")
            print("      \(describe(window, intersectsDisplay: intersects))")
        }
    }
}

// MARK: - Report

if !CGPreflightScreenCaptureAccess() {
    print("!! This terminal hasn't got Screen Recording, so every title")
    print("!! will be empty and every window will filter out. Grant it in")
    print("!! System Settings > Privacy & Security > Screen Recording.")
    print("")
}

let frames = displayFrames()
print("displays, in window-server coordinates")
for frame in frames {
    print("  \(describe(frame))")
}

let entries = CGWindowListCopyWindowInfo(
    [.optionAll, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let all = entries.compactMap(parse)
let rows = all.filter(passesDeweyFilters)
print("")
print("\(all.count) windows owned by apps; dewey would row \(rows.count)")

let onScreen = rows.filter(\.isOnScreen)
let offScreen = rows.filter { !$0.isOnScreen }
printGroup("on screen", onScreen, frames)
printGroup(
    "offscreen -- other spaces, minimized, and ordered out alike",
    offScreen,
    frames
)

// MARK: - What accessibility makes of every row

print("")
guard AXIsProcessTrusted() else {
    print("This terminal isn't trusted for Accessibility, which is the")
    print("whole point of this run. Grant it in System Settings >")
    print("Privacy & Security > Accessibility and try again.")
    exit(0)
}

var applicationNamesByProcessID = [pid_t: String]()
for row in rows {
    applicationNamesByProcessID[row.processID] = row.applicationName
}

var axResultsByProcessID = [pid_t: AXWindowsResult]()
for processID in applicationNamesByProcessID.keys {
    axResultsByProcessID[processID] = axWindows(ofProcess: processID)
}

print("every AX window of every app that owns a row")
for (processID, name) in applicationNamesByProcessID.sorted(by: { $0.value < $1.value }) {
    switch axResultsByProcessID[processID] {
    case .queryFailed(let error):
        print("  \(name) (pid \(processID)): QUERY FAILED -- \(axErrorName(error))")
    case .unexpectedValue:
        print("  \(name) (pid \(processID)): kAXWindows WASN'T AN ELEMENT ARRAY")
    case .windows(let windows):
        print("  \(name) (pid \(processID)): \(windows.count) AX windows")
        for window in windows {
            let windowID = window.windowID.map { "\($0)" } ?? "(no _AXUIElementGetWindow)"
            print("    \"\(window.title)\"")
            print(
                "      wid=\(windowID)  minimized=\(window.isMinimized)"
                    + "  frame=\(window.frame.map(describe) ?? "(none)")"
            )
        }
    case nil:
        print("  \(name) (pid \(processID)): not queried")
    }
}

// On-screen rows are the control: if they don't match either, the
// matching is broken rather than the offscreen windows being special.
print("")
print("every row matched against its app's AX windows")
let ordered = rows.sorted {
    ($0.applicationName, $0.title) < ($1.applicationName, $1.title)
}
for row in ordered {
    let place = row.isOnScreen ? "on screen" : "offscreen"
    print("  [\(place)] \(row.applicationName) -- \"\(row.title)\"")

    guard case .windows(let axWindows)? = axResultsByProcessID[row.processID] else {
        print("      no AX window list to match against")
        continue
    }

    let byTitle = axWindows.filter { $0.title == row.title }
    let byFrame = axWindows.filter { window in
        guard let frame = window.frame else { return false }

        return isWithinTolerance(frame, row.bounds)
    }
    let byWindowID = axWindows.filter { $0.windowID.map(Int.init) == row.windowID }
    let matched = byWindowID.first ?? byFrame.first ?? byTitle.first
    print(
        "      idMatches=\(byWindowID.count)  titleMatches=\(byTitle.count)"
            + "  frameMatches=\(byFrame.count)"
            + "  minimized=\(matched.map { "\($0.isMinimized)" } ?? "?")"
    )
}

// MARK: - Does the ranged accessor see more windows?

func windowCount(_ result: AXWindowsResult?) -> String {
    switch result {
    case .windows(let windows): return "\(windows.count)"
    case .queryFailed(let error): return "failed(\(axErrorName(error)))"
    case .unexpectedValue: return "not an element array"
    case nil: return "?"
    }
}

print("")
print("plain vs ranged kAXWindows, per app that owns a row")
var rangedResultsByProcessID = [pid_t: AXWindowsResult]()
for (processID, name) in applicationNamesByProcessID.sorted(by: { $0.value < $1.value }) {
    let ranged = axWindowsRanged(ofProcess: processID)
    rangedResultsByProcessID[processID] = ranged
    let claimed = axWindowCount(ofProcess: processID).map { "\($0)" } ?? "?"
    print(
        "  \(name): claims \(claimed)"
            + ", plain \(windowCount(axResultsByProcessID[processID]))"
            + ", ranged \(windowCount(ranged))"
    )
}

// The question this is all for: would the row's window be reachable?
print("")
print("each row's window, looked for through the ranged accessor")
for row in ordered {
    let place = row.isOnScreen ? "on screen" : "offscreen"
    var found = false
    if case .windows(let windows)? = rangedResultsByProcessID[row.processID] {
        found = windows.contains { $0.windowID.map(Int.init) == row.windowID }
    }
    print(
        "  [\(place)] \(row.applicationName) -- \"\(row.title)\": "
            + (found ? "FOUND" : "not found")
    )
}

// MARK: - Which space each row's window is on

print("")
guard cgsMainConnection != nil, cgsCopySpaces != nil else {
    print("CGSMainConnectionID or CGSCopySpacesForWindows is missing, so")
    print("there's no way to ask about spaces. That rules out the only")
    print("filter left for the ordered-out windows.")
    exit(0)
}

print("the spaces each row's window belongs to")
var spaceIDsByWindowID = [Int: [Int]]()
for row in ordered {
    let place = row.isOnScreen ? "on screen" : "offscreen"
    let spaces = spaceIDs(of: row.windowID)
    spaceIDsByWindowID[row.windowID] = spaces ?? []
    let description: String
    switch spaces {
    case nil:
        description = "couldn't ask"
    case let spaces? where spaces.isEmpty:
        description = "NO SPACE -- ordered out"
    case let spaces?:
        description = spaces.map { "\($0)" }.joined(separator: ", ")
    }
    print("  [\(place)] \(row.applicationName) -- \"\(row.title)\": \(description)")
}

// MARK: - Which of them the window server would actually draw

print("")
if cgsCopyWindows == nil {
    print("CGSCopyWindowsWithOptionsAndTags is missing, so there's no way")
    print("to ask which windows are ordered in. Without it, an ordered-out")
    print("window can't be told from one on another space.")
}

let involvedSpaceIDs = Array(Set(spaceIDsByWindowID.values.flatMap { $0 })).sorted()
print("spaces in play: \(involvedSpaceIDs)")

let everyWindow = windowIDs(inSpaces: involvedSpaceIDs, options: 0)
let orderedInWindows = windowIDs(inSpaces: involvedSpaceIDs, options: 2)

// If these two counts are equal, the options flag doesn't mean what it's
// being asked to mean, and the whole approach is out.
print("windows in those spaces: options 0 -> \(everyWindow?.count ?? -1)"
    + ", options 2 -> \(orderedInWindows?.count ?? -1)")

print("")
print("is each row's window ordered in?")
for row in ordered {
    let place = row.isOnScreen ? "on screen" : "offscreen"
    let inEvery = everyWindow?.contains(row.windowID)
    let inOrderedIn = orderedInWindows?.contains(row.windowID)
    let verdict: String
    switch inOrderedIn {
    case true: verdict = "ordered in"
    case false: verdict = "NOT ORDERED IN"
    case nil: verdict = "couldn't ask"
    }
    print("  [\(place)] \(row.applicationName) -- \"\(row.title)\"")
    print("      \(verdict)  (listed by options 0: \(inEvery.map { "\($0)" } ?? "?"))")
}

// MARK: - Can a window actually be focused?

print("")
print("focus symbols")
print("  GetProcessForPID: \(getProcessForPID == nil ? "MISSING" : "found")")
print("  _SLPSSetFrontProcessWithOptions: \(slpsSetFront == nil ? "MISSING" : "found")")
print("  SLPSPostEventRecordTo: \(slpsPostEvent == nil ? "MISSING" : "found")")

print("")
print("process serial number per app that owns a row")
var serialNumbersByProcessID = [pid_t: ProcessSerialNumber]()
for (processID, name) in applicationNamesByProcessID.sorted(by: { $0.value < $1.value }) {
    guard let getProcessForPID else { break }

    var psn = ProcessSerialNumber()
    let status = getProcessForPID(processID, &psn)
    if status == noErr {
        serialNumbersByProcessID[processID] = psn
    }
    // A serial number of 0,0 came back empty however the status reads,
    // and would name no process at all to the window server.
    print(
        "  \(name) (pid \(processID)): status=\(status)"
            + "  psn=(\(psn.highLongOfPSN), \(psn.lowLongOfPSN))"
            + ((psn.highLongOfPSN == 0 && psn.lowLongOfPSN == 0) ? "  EMPTY" : "")
    )
}

// Opt-in, because unlike everything else here it changes what's in
// front of you:
//
//   ./window-dump.swift --focus [--variant slps|slps2|space] [--window <id>]
//
// It picks its own target: a window on another space, preferring one
// whose app has other windows too, since merely activating an app with
// a single window would look like success whatever the call did. Run it
// from a space that window ISN'T on. The printed return codes say only
// whether each call was accepted; whether the right window actually
// came forward is for your eyes.

/// The most telling window to try to focus: on another space, and
/// ideally one of several its app owns.
///
/// Ordered-out windows are excluded, and not as a nicety — one is drawn
/// on no space at all, so nothing can bring it forward, and picking one
/// makes the test look like a failure of the focus call rather than of
/// the choice of window.
func focusTarget(
    among rows: [Window],
    orderedIn: [Int]?
) -> (window: Window, isStrongTest: Bool)? {
    var rowsPerApp = [String: Int]()
    for row in rows {
        rowsPerApp[row.applicationName, default: 0] += 1
    }

    let elsewhere = rows.filter { row in
        guard !row.isOnScreen else { return false }
        guard let orderedIn else { return true }

        return orderedIn.contains(row.windowID)
    }
    if let strong = elsewhere.first(where: { (rowsPerApp[$0.applicationName] ?? 0) > 1 }) {
        return (strong, true)
    }
    guard let any = elsewhere.first else { return nil }

    return (any, false)
}

/// The event that tells an app to treat a window as key, as AltTab
/// writes it: a point far outside any window, posted once.
func makeKeyWindowAltTab(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
    guard let slpsPostEvent else { return }

    var windowID = windowID
    var point = MakeKeyEvent.offContentPoint
    var bytes = [UInt8](repeating: 0, count: MakeKeyEvent.bufferSize)
    bytes[MakeKeyEvent.lengthOffset] = MakeKeyEvent.recordLength
    bytes[MakeKeyEvent.unknownFlagOffset] = MakeKeyEvent.unknownFlagValue
    memcpy(&bytes[MakeKeyEvent.windowIDOffset], &windowID, MemoryLayout<CGWindowID>.size)
    memcpy(&bytes[MakeKeyEvent.windowLocationOffset], &point, MemoryLayout<CGPoint>.size)
    bytes[MakeKeyEvent.eventTypeOffset] = MakeKeyEvent.leftMouseDown
    let error = slpsPostEvent(&psn, &bytes)
    print("  post (AltTab shape): \(error.rawValue)")
}

/// The same idea as yabai writes it: 0xFF through the location field,
/// and two events rather than one.
func makeKeyWindowYabai(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
    guard let slpsPostEvent else { return }

    var windowID = windowID
    var bytes = [UInt8](repeating: 0, count: MakeKeyEvent.bufferSize)
    bytes[MakeKeyEvent.lengthOffset] = MakeKeyEvent.recordLength
    bytes[MakeKeyEvent.unknownFlagOffset] = MakeKeyEvent.unknownFlagValue
    memcpy(&bytes[MakeKeyEvent.windowIDOffset], &windowID, MemoryLayout<CGWindowID>.size)
    memset(&bytes[MakeKeyEvent.windowLocationOffset], 0xFF, 0x10)
    bytes[MakeKeyEvent.eventTypeOffset] = 0x02
    let first = slpsPostEvent(&psn, &bytes)
    bytes[MakeKeyEvent.eventTypeOffset] = 0x01
    let second = slpsPostEvent(&psn, &bytes)
    print("  post (yabai shape): \(first.rawValue), \(second.rawValue)")
}

/// An accessibility attribute that holds a single element rather than a
/// list — `kAXMainWindow`, `kAXFocusedWindow`. The interesting question
/// is whether these name a window `kAXWindows` refuses to list.
func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var copied: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &copied
    ) == .success,
          let copied,
          CFGetTypeID(copied) == AXUIElementGetTypeID()
    else {
        return nil
    }

    return (copied as! AXUIElement)
}

/// Looks for the window in its app's accessibility list, giving the
/// window server time to catch up with a space change.
func waitForAXWindow(
    processID: pid_t,
    windowID: Int,
    seconds: Double
) -> AXUIElement? {
    let application = AXUIElementCreateApplication(processID)
    _ = AXUIElementSetMessagingTimeout(application, 2)
    let deadline = seconds * 20

    for attempt in 0...Int(deadline) {
        var copied: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &copied
        ) == .success, let elements = copied as? [AXUIElement] {
            for element in elements where axWindowID(element).map(Int.init) == windowID {
                print("  accessibility saw it after \(attempt * 50)ms")
                return element
            }
        }
        usleep(50_000)
    }

    print("  accessibility never saw it")
    return nil
}

func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          index + 1 < CommandLine.arguments.count
    else {
        return nil
    }

    return CommandLine.arguments[index + 1]
}

if CommandLine.arguments.contains("--focus") {
    let variant = argument(after: "--variant") ?? "slps"

    let chosen: Window?
    let isStrongTest: Bool
    if let requested = argument(after: "--window").flatMap(Int.init) {
        chosen = ordered.first { $0.windowID == requested }
        isStrongTest = true
    } else {
        let target = focusTarget(among: ordered, orderedIn: orderedInWindows)
        chosen = target?.window
        isStrongTest = target?.isStrongTest ?? false
    }

    print("")
    guard let row = chosen else {
        print("nothing to focus: no window the window server draws is on")
        print("another space right now. Put one somewhere else and re-run.")
        exit(0)
    }

    let requestedID = row.windowID
    print("focusing \(row.applicationName) -- \"\(row.title)\" (id \(requestedID))")
    print("  variant \(variant), on screen: \(row.isOnScreen)"
        + ", spaces: \(spaceIDsByWindowID[requestedID] ?? [])")
    print("  ordered in: \(orderedInWindows?.contains(requestedID).description ?? "?")")
    if !isStrongTest {
        print("  NOTE: its app owns no other window, so activating the app")
        print("  alone would look like success. A weak test.")
    }

    switch variant {
    case "slps", "slps2":
        guard let getProcessForPID, let slpsSetFront else {
            print("  the symbols for this aren't here")
            exit(0)
        }

        var psn = ProcessSerialNumber()
        let status = getProcessForPID(row.processID, &psn)
        print("  GetProcessForPID: status=\(status)"
            + "  psn=(\(psn.highLongOfPSN), \(psn.lowLongOfPSN))")

        let error = slpsSetFront(&psn, CGWindowID(requestedID), 0x200)
        print("  _SLPSSetFrontProcessWithOptions: \(error.rawValue)"
            + (error == .success ? " (accepted)" : " (REFUSED)"))

        if variant == "slps" {
            makeKeyWindowAltTab(&psn, CGWindowID(requestedID))
        } else {
            makeKeyWindowYabai(&psn, CGWindowID(requestedID))
        }

    case "space":
        // Known bad, kept as a record of it: this moves the window
        // server without telling Dock.app, which switches the space but
        // leaves macOS's own idea of the space layout inconsistent, as
        // Mission Control then shows. `killall Dock` puts it right.
        print("  WARNING: this leaves Mission Control inconsistent.")
        guard let cgsMainConnection, let cgsCopyDisplayForSpace, let cgsSetCurrentSpace
        else {
            print("  the space-switching symbols aren't here")
            exit(0)
        }
        guard let spaceID = spaceIDs(of: requestedID)?.first else {
            print("  the window names no space to switch to")
            exit(0)
        }

        let connection = cgsMainConnection()
        guard let display = cgsCopyDisplayForSpace(connection, UInt64(spaceID)) else {
            print("  CGSCopyManagedDisplayForSpace gave nothing for space \(spaceID)")
            exit(0)
        }
        print("  space \(spaceID) is on display \(display)")

        cgsSetCurrentSpace(connection, display, UInt64(spaceID))
        print("  CGSManagedDisplaySetCurrentSpace: returned")

        if let element = waitForAXWindow(
            processID: row.processID,
            windowID: requestedID,
            seconds: 1.5
        ) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            let raise = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            print("  kAXRaise: \(axErrorName(raise))")
        }

    case "slps3":
        // Designate the window through the window server first, then go
        // looking for an accessibility element that names it. Raising
        // one of those is what lets macOS move spaces itself, through
        // the channels that keep the Dock's bookkeeping straight.
        guard let getProcessForPID, let slpsSetFront else {
            print("  the symbols for this aren't here")
            exit(0)
        }

        var psn = ProcessSerialNumber()
        _ = getProcessForPID(row.processID, &psn)
        let error = slpsSetFront(&psn, CGWindowID(requestedID), 0x200)
        print("  _SLPSSetFrontProcessWithOptions: \(error.rawValue)")
        makeKeyWindowAltTab(&psn, CGWindowID(requestedID))

        let application = AXUIElementCreateApplication(row.processID)
        _ = AXUIElementSetMessagingTimeout(application, 2)

        var raised: AXUIElement?
        for attempt in 0...20 {
            for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                guard let element = axElement(application, attribute) else { continue }

                let windowID = axWindowID(element).map(Int.init)
                if attempt == 0 || windowID == requestedID {
                    print("  \(attribute) -> wid=\(windowID.map(String.init) ?? "?")"
                        + (windowID == requestedID ? "  MATCHES" : ""))
                }
                if windowID == requestedID {
                    raised = element
                }
            }
            if raised != nil {
                print("  found it after \(attempt * 50)ms")
                break
            }
            usleep(50_000)
        }

        if let raised {
            let raise = AXUIElementPerformAction(raised, kAXRaiseAction as CFString)
            print("  kAXRaise: \(axErrorName(raise))")
        } else {
            print("  no single-element attribute ever named the window")
        }

    default:
        print("  unknown variant; use slps, slps2, slps3, or space")
        exit(0)
    }

    if let application = NSRunningApplication(processIdentifier: row.processID) {
        application.activate()
        print("  activated the app")
    }
    // Give whatever was set in motion a moment before the process ends.
    usleep(500_000)
}
