//
//  DeweyConfig.swift
//  dewey
//

import Foundation

/// App configuration, read once at launch from a JSON file. The app never
/// writes the file; a missing config, or any invalid part of one, falls
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
