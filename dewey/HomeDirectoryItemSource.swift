//
//  HomeDirectoryItemSource.swift
//  dewey
//

import Foundation

/// Finds non-hidden directories at the top level of the home directory.
struct HomeDirectoryItemSource: LauncherItemSource {
    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser

        guard let contents = try? fileManager.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url in
            // fileExists(atPath:) traverses symlinks, so symlinked
            // directories are included; .isDirectoryKey would exclude them.
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            )
            guard exists, isDirectory.boolValue else { return nil }

            return LauncherItem(
                kind: .directory,
                name: url.lastPathComponent,
                url: url
            )
        }
    }
}
