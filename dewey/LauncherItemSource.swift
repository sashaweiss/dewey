//
//  LauncherItemSource.swift
//  dewey
//

import Foundation

/// A provider of launchable items, rescanned each time the panel is shown.
protocol LauncherItemSource {
    func loadItems() -> [LauncherItem]
}
