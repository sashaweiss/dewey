//
//  ApplicationItemSource.swift
//  dewey
//

import Cocoa

/// Finds `.app` bundles in the standard application directories, descending
/// one level into subfolders (e.g. /Applications/Utilities).
struct ApplicationItemSource: LauncherItemSource {
    private static let searchDirectoryPaths: [String] = [
        "/Applications",
        "/System/Applications",
        // Safari and friends live in a cryptex, not /System/Applications.
        "/System/Cryptexes/App/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default
        var itemsByURL = [URL: LauncherItem]()

        for path in Self.searchDirectoryPaths {
            let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    enumerator.skipDescendants()

                    let resolvedURL = url.resolvingSymlinksInPath()
                    guard itemsByURL[resolvedURL] == nil else { continue }

                    itemsByURL[resolvedURL] = LauncherItem(
                        kind: .application,
                        name: fileManager.displayName(atPath: resolvedURL.path),
                        url: resolvedURL
                    )
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }

        return Array(itemsByURL.values)
    }
}
