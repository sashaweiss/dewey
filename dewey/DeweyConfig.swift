//
//  DeweyConfig.swift
//  dewey
//

import Foundation

/// App configuration, read once at launch from a JSON file. The only write
/// the app ever makes is seeding this file on first run, and only when
/// nothing is there; a missing config, or any invalid part of one, falls
/// back to defaults.
struct DeweyConfig {
    var hotKey: HotKeyChord = HotKeyChord.default

    /// The config file location: $DEWEY_CONFIG if set (tilde-expanded),
    /// else ~/.config/dewey/config.json. The path may be a symlink.
    static func fileURL() -> URL {
        let path: String
        if let overridePath = ProcessInfo.processInfo.environment["DEWEY_CONFIG"] {
            path = (overridePath as NSString).expandingTildeInPath
        } else {
            path = NSHomeDirectory() + "/.config/dewey/config.json"
        }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    /// Seeds the config file by copying the bundled `default-config.json`,
    /// so there's something to edit after a first launch. Does nothing at
    /// all if a file is already at the path — an existing config is never
    /// touched.
    static func installDefaultIfAbsent() {
        let url = fileURL()
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: url.path) else { return }

        guard let bundledURL = Bundle.main.url(
            forResource: "default-config",
            withExtension: "json"
        ) else {
            NSLog("No bundled default-config.json to seed the config from")
            return
        }

        do {
            let contents = try Data(contentsOf: bundledURL)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Write the bytes rather than `copyItem`, so the new file gets
            // normal permissions instead of inheriting the bundle's.
            // `withoutOverwriting` closes the gap between the check above
            // and this write.
            try contents.write(to: url, options: .withoutOverwriting)
        } catch {
            NSLog("Couldn't write a default config to \(url.path): \(error)")
        }
    }

    static func load() -> DeweyConfig {
        var config = DeweyConfig()

        guard let data = try? Data(contentsOf: fileURL()) else {
            return config
        }

        let file: ConfigFile
        do {
            file = try JSONDecoder().decode(ConfigFile.self, from: data)
        } catch {
            NSLog("Ignoring malformed config JSON: \(error)")
            return config
        }

        if let rawHotKey = file.hotKey {
            if let chord = HotKeyChord(rawValue: rawHotKey) {
                config.hotKey = chord
            } else {
                NSLog("Ignoring unparseable hotKey in config: \(rawHotKey)")
            }
        }

        return config
    }
}

// MARK: -

/// The raw shape of the JSON file, prior to parsing and validation.
private struct ConfigFile: Decodable {
    var hotKey: String?
}
