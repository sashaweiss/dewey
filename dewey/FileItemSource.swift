//
//  FileItemSource.swift
//  dewey
//

import Cocoa
import UniformTypeIdentifiers

/// Finds the given files.
struct FileItemSource: LauncherItemSource {
    let fileURLs: [URL]

    func loadItems() -> [LauncherItem] {
        let icon = NSWorkspace.shared.icon(for: UTType.data)

        return fileURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { url in
                LauncherItem(
                    kind: .file,
                    name: url.lastPathComponent,
                    url: url,
                    customIcon: icon
                )
            }
    }
}
