//
//  ApplicationItemSource.swift
//  dewey
//

import Cocoa

/// Finds apps in the given directories, one level deep.
struct ApplicationItemSource: LauncherItemSource {
    let directoryURLs: [URL]

    /// Apps outside the searched directories.
    private static let applicationPaths: [String] = [
        "/System/Library/CoreServices/Finder.app",
    ]

    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default
        var itemsByURL = [URL: LauncherItem]()

        for path in Self.applicationPaths where fileManager.fileExists(atPath: path) {
            let resolvedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            itemsByURL[resolvedURL] = LauncherItem(
                kind: .application,
                name: fileManager.displayName(atPath: resolvedURL.path),
                url: resolvedURL
            )
        }

        for directoryURL in directoryURLs {
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
