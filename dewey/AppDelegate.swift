//
//  AppDelegate.swift
//  dewey
//
//  Created by Sasha Weiss on 9/9/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var launcherPanelController: LauncherPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Menu bar app: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)

        let launcherPanelController = LauncherPanelController(sources: [
            ApplicationItemSource(),
            HomeDirectoryItemSource(),
            ICloudDriveItemSource(),
        ])
        self.launcherPanelController = launcherPanelController

        DeweyConfig.installDefaultIfAbsent()
        let config = DeweyConfig.load()
        hotKey = GlobalHotKey(
            keyCode: config.hotKey.keyCode,
            modifierFlags: config.hotKey.modifierFlags
        ) { [weak launcherPanelController] in
            launcherPanelController?.toggle()
        }
        if hotKey == nil {
            NSLog("Failed to register global hot key \(config.hotKey.displayString)!")
        }

        setUpStatusItem(hotKeyChord: config.hotKey)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Status item

    private func setUpStatusItem(hotKeyChord: HotKeyChord) {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        statusItem.button?.image = NSImage.emoji(
            "📚",
            side: 18,
            accessibilityDescription: "dewey"
        )

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle dewey (\(hotKeyChord.displayString))",
            action: #selector(didSelectToggleMenuItem),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit dewey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc
    private func didSelectToggleMenuItem() {
        launcherPanelController?.toggle()
    }
}

// MARK: -

private extension NSImage {
    /// Renders an emoji into an image exactly `side` points square. Not a
    /// template image: color emoji would come out as a solid blob if the
    /// status bar tinted it.
    static func emoji(
        _ emoji: String,
        side: CGFloat,
        accessibilityDescription: String
    ) -> NSImage {
        // Apple Color Emoji lays out well above its point size, so derive
        // the point size that actually fills `side` rather than assuming
        // the two match.
        let probeSize: CGFloat = 100
        let probe = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: probeSize)]
        ).size()
        let pointSize = probeSize * side / max(probe.width, probe.height)

        let attributedString = NSAttributedString(
            string: emoji,
            attributes: [.font: NSFont.systemFont(ofSize: pointSize)]
        )
        let textSize = attributedString.size()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        attributedString.draw(
            at: NSPoint(
                x: (side - textSize.width) / 2,
                y: (side - textSize.height) / 2
            )
        )
        image.unlockFocus()

        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
