//
//  Logger.swift
//  dewey
//

import Foundation
import os

/// Logging to Xcode's console and the system log, via `os.Logger`.
enum Logger {
    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dewey",
        category: "dewey"
    )

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func warn(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}
