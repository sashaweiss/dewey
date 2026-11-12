//
//  XcodeApplicationItemSource.swift
//  dewey
//

import Cocoa

/// Finds the apps inside Xcode's bundle, like Instruments and Simulator.
struct XcodeApplicationItemSource: LauncherItemSource {
    private static let xcodeBundleIdentifier = "com.apple.dt.Xcode"

    /// Where the vendored apps sit within an Xcode bundle.
    private static let applicationDirectoryPaths = [
        "Contents/Applications",
        "Contents/Developer/Applications",
    ]

    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default
        var itemsByURL = [URL: LauncherItem]()

        // Ask LaunchServices rather than scanning, so every installed Xcode
        // counts however it's named and wherever it was dragged to.
        let xcodeURLs = NSWorkspace.shared.urlsForApplications(
            withBundleIdentifier: Self.xcodeBundleIdentifier
        )

        for xcodeURL in xcodeURLs {
            let xcodeName = fileManager.displayName(atPath: xcodeURL.path)

            for directoryPath in Self.applicationDirectoryPaths {
                let directoryURL = xcodeURL.appending(path: directoryPath)
                let contents = (try? fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []

                for url in contents where url.pathExtension == "app" {
                    let resolvedURL = url.resolvingSymlinksInPath()
                    guard itemsByURL[resolvedURL] == nil else { continue }

                    itemsByURL[resolvedURL] = LauncherItem(
                        kind: .application,
                        name: fileManager.displayName(atPath: resolvedURL.path),
                        alternateNames: [xcodeName],
                        url: resolvedURL
                    )
                }
            }
        }

        return Array(itemsByURL.values)
    }
}
