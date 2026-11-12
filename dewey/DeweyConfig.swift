//
//  DeweyConfig.swift
//  dewey
//

import Foundation

/// App configuration, stored as JSON. Missing settings use defaults.
struct DeweyConfig: Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case hotKey
        case includeOpenWindows
        case includeXcodeApplications
        case includeICloudDrive
        case applicationDirectories
        case searchedDirectories
    }

    var hotKey = HotKeyChord.default
    var includeOpenWindows = true
    var includeXcodeApplications = true
    var includeICloudDrive = true
    /// Searched for apps.
    var applicationDirectories = [
        "/Applications",
        "~/Applications",
        "/System/Applications",
        // Safari and friends live in a cryptex.
        "/System/Cryptexes/App/System/Applications",
    ]
    /// Their subdirectories are searched.
    var searchedDirectories = ["~"]

    static let fileURL = URL(
        fileURLWithPath: NSHomeDirectory() + "/.config/dewey/config.json"
    )

    init() {}

    /// Ignores an unparseable hot key and relative paths.
    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let rawHotKey = try container.decodeIfPresent(
            String.self,
            forKey: .hotKey
        ) {
            if let chord = HotKeyChord(rawValue: rawHotKey) {
                hotKey = chord
            } else {
                NSLog("Ignoring unparseable hotKey in config: \(rawHotKey)")
            }
        }
        includeOpenWindows = try container
            .decodeIfPresent(Bool.self, forKey: .includeOpenWindows)
            ?? includeOpenWindows
        includeXcodeApplications = try container
            .decodeIfPresent(Bool.self, forKey: .includeXcodeApplications)
            ?? includeXcodeApplications
        includeICloudDrive = try container
            .decodeIfPresent(Bool.self, forKey: .includeICloudDrive)
            ?? includeICloudDrive
        applicationDirectories = try container
            .decodeIfPresent([String].self, forKey: .applicationDirectories)
            .map { Self.absolutePaths(paths: $0) }
            ?? applicationDirectories
        searchedDirectories = try container
            .decodeIfPresent([String].self, forKey: .searchedDirectories)
            .map { Self.absolutePaths(paths: $0) }
            ?? searchedDirectories
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotKey.rawValue, forKey: .hotKey)
        try container.encode(includeOpenWindows, forKey: .includeOpenWindows)
        try container.encode(
            includeXcodeApplications,
            forKey: .includeXcodeApplications
        )
        try container.encode(includeICloudDrive, forKey: .includeICloudDrive)
        try container.encode(
            applicationDirectories,
            forKey: .applicationDirectories
        )
        try container.encode(searchedDirectories, forKey: .searchedDirectories)
    }

    /// Returns the defaults if there's no config file.
    static func load() throws -> DeweyConfig {
        let url = fileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DeweyConfig()
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(DeweyConfig.self, from: data)
    }

    func save() throws {
        let url = Self.fileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Expands a leading `~`.
    static func directoryURL(path: String) -> URL {
        URL(
            fileURLWithPath: (path as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    private static func absolutePaths(paths: [String]) -> [String] {
        paths.filter { path in
            guard (path as NSString).expandingTildeInPath.hasPrefix("/") else {
                NSLog("Ignoring non-absolute path in config: \(path)")
                return false
            }
            return true
        }
    }
}
