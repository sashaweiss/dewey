//
//  ICloudDriveItemSource.swift
//  dewey
//

import Foundation

/// Finds iCloud Drive, so it can be opened in Finder. It lives under
/// `~/Library`, which `HomeDirectoryItemSource` never sees because the
/// system marks that directory hidden.
struct ICloudDriveItemSource: LauncherItemSource {
    private static let relativePath = "Library/Mobile Documents/com~apple~CloudDocs"

    func loadItems() -> [LauncherItem] {
        let fileManager = FileManager.default
        let url = fileManager.homeDirectoryForCurrentUser
            .appending(path: Self.relativePath)

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        )
        // Absent when the user isn't signed in to iCloud, or has iCloud
        // Drive switched off.
        guard exists, isDirectory.boolValue else { return [] }

        // Finder shows this as a localized "iCloud Drive" rather than the
        // on-disk "com~apple~CloudDocs"; match that where the system
        // offers it.
        let displayName = fileManager.displayName(atPath: url.path)
        let name = displayName == url.lastPathComponent
            ? "iCloud Drive"
            : displayName

        return [LauncherItem(kind: .directory, name: name, url: url)]
    }
}
