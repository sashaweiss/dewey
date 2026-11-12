//
//  DirectoryItemSource.swift
//  dewey
//

import Foundation

/// Finds a directory's non-hidden subdirectories.
struct DirectoryItemSource: LauncherItemSource {
    let directoryURL: URL

    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
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
