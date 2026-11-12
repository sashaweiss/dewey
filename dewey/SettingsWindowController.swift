//
//  SettingsWindowController.swift
//  dewey
//

import Cocoa

/// The Settings window: a tab for each pane, which edits the config file.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// A change to make to the config.
    typealias Edit = (inout DeweyConfig) -> Void

    /// Puts a loaded or saved config to use.
    private let applyConfig: (DeweyConfig) -> Void
    private var config = DeweyConfig()

    private lazy var generalPane = GeneralSettingsViewController(
        edit: { [weak self] change in self?.edit(change: change) }
    )
    private lazy var locationsPane = LocationsSettingsViewController(
        edit: { [weak self] change in self?.edit(change: change) }
    )

    init(applyConfig: @escaping (DeweyConfig) -> Void) {
        self.applyConfig = applyConfig

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar
        let panes: [(NSViewController, String)] = [
            (generalPane, "gearshape"),
            (locationsPane, "folder"),
        ]
        for (pane, systemImage) in panes {
            let item = NSTabViewItem(viewController: pane)
            item.label = pane.title ?? ""
            item.image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: pane.title
            )
            tabViewController.addTabViewItem(item)
        }
        window.contentViewController = tabViewController
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Rereads the config file first, unless the window is already showing.
    func show() {
        guard let window else { return }

        // An accessory app can't reliably bring itself forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if window.isVisible {
            showWindow(nil)
            return
        }

        var loadError: (any Error)?
        do {
            config = try DeweyConfig.load()
            applyConfig(config)
        } catch {
            NSLog("Couldn't reload config: \(error)")
            loadError = error
        }
        generalPane.reload(config: config)
        locationsPane.reload(config: config)
        showWindow(nil)
        if let loadError {
            presentAlert(
                message: "dewey couldn't read its config.",
                error: loadError
            )
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Commits any text field edit in progress.
        window?.makeFirstResponder(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: -

    private func edit(change: Edit) {
        var newConfig = config
        change(&newConfig)
        guard newConfig != config else { return }

        do {
            try newConfig.save()
        } catch {
            NSLog("Couldn't save config: \(error)")
            presentAlert(message: "dewey couldn't save its config.", error: error)
            return
        }
        config = newConfig
        applyConfig(newConfig)
    }

    /// Does nothing if a sheet is already showing.
    private func presentAlert(message: String, error: any Error) {
        guard let window, window.attachedSheet == nil else { return }

        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
