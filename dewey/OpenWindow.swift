//
//  OpenWindow.swift
//  dewey
//

import Cocoa

/// One window of a running application.
struct OpenWindow {
    let windowID: CGWindowID
    let processID: pid_t
    /// Always something: a window with no title of its own can't be told
    /// apart from its app's others, so it doesn't get a row at all.
    let title: String
    /// False for a window on a space you'd have to switch to. Still
    /// worth a row; it just sorts below what's in front of you.
    let isOnScreen: Bool
    /// The window's place in the front-to-back order when the list was
    /// gathered, so one app's rows stay in a stable, front-first order.
    let stackOrder: Int
}
