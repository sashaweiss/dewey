//
//  AppDelegate.swift
//  dewey
//
//  Created by Sasha Weiss on 9/9/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var launcherPanelController = LauncherPanelController(
        sources: []
    )
    private var hotKey: GlobalHotKey?
    private var hotKeyChord: HotKeyChord?
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Menu bar app: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)

        setUpStatusItem()

        let config: DeweyConfig
        do {
            config = try DeweyConfig.load()
        } catch {
            Logger.error("Ignoring unreadable config: \(error)")
            config = DeweyConfig()
        }
        apply(config: config)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Config

    private func apply(config: DeweyConfig) {
        var sources: [LauncherItemSource] = []
        if config.includeOpenWindows {
            sources.append(OpenWindowSource())
        }
        sources.append(ApplicationItemSource(
            directoryURLs: config.applicationDirectories.map {
                DeweyConfig.directoryURL(path: $0)
            }
        ))
        if config.includeXcodeApplications {
            sources.append(XcodeApplicationItemSource())
        }
        sources += config.searchedDirectories.map {
            DirectoryItemSource(
                directoryURL: DeweyConfig.directoryURL(path: $0)
            )
        }
        if config.includeICloudDrive {
            sources.append(ICloudDriveItemSource())
        }
        launcherPanelController.sources = sources

        guard config.hotKey != hotKeyChord else { return }

        // Unregister first, in case it's the same chord.
        hotKey = nil
        hotKey = GlobalHotKey(
            keyCode: config.hotKey.keyCode,
            modifierFlags: config.hotKey.modifierFlags
        ) { [weak launcherPanelController] in
            launcherPanelController?.toggle()
        }
        if hotKey == nil {
            Logger.error(
                "Failed to register global hot key " +
                    "\(config.hotKey.displayString)!"
            )
        }
        hotKeyChord = config.hotKey
        toggleMenuItem?.title =
            "Toggle \(Bundle.main.appName) (\(config.hotKey.displayString))"
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        statusItem.button?.image = NSImage.emoji(
            "📚",
            side: 18,
            accessibilityDescription: Bundle.main.appName
        )

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle \(Bundle.main.appName)",
            action: #selector(didSelectToggleMenuItem),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit \(Bundle.main.appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func didSelectToggleMenuItem() {
        launcherPanelController.toggle()
    }

    /// Also sent by the launcher panel's ⌘,.
    @objc
    func showSettings(_ sender: Any?) {
        launcherPanelController.hide()

        let settingsWindowController = settingsWindowController
            ?? SettingsWindowController { [weak self] config in
                self?.apply(config: config)
            }
        self.settingsWindowController = settingsWindowController
        settingsWindowController.show()
    }
}

// MARK: -

private extension Bundle {
    /// The app's name, which is suffixed in debug builds so a debug
    /// instance is distinguishable from a release one.
    var appName: String {
        return object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "dewey"
    }
}
