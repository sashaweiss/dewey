//
//  GeneralSettingsViewController.swift
//  dewey
//

import Cocoa

/// Edits the hot key and which optional sources are searched.
final class GeneralSettingsViewController: NSViewController {
    private let edit: (SettingsWindowController.Edit) -> Void

    private lazy var hotKeyField: NSTextField = {
        let field = NSTextField()
        field.placeholderString = HotKeyChord.default.rawValue
        // Not per keystroke, so partial chords aren't registered.
        field.cell?.sendsActionOnEndEditing = true
        field.target = self
        field.action = #selector(didEditHotKey)
        return field
    }()

    /// An example chord, or a warning when the field's isn't one.
    private lazy var hotKeyHintLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.preferredFont(forTextStyle: .callout)
        return label
    }()

    private lazy var openWindowsCheckbox = checkbox(title: "Open windows")
    private lazy var xcodeApplicationsCheckbox = checkbox(
        title: "Apps inside Xcode"
    )
    private lazy var iCloudDriveCheckbox = checkbox(title: "iCloud Drive")

    init(edit: @escaping (SettingsWindowController.Edit) -> Void) {
        self.edit = edit
        super.init(nibName: nil, bundle: nil)
        title = "General"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        let gridView = NSGridView(views: [
            [NSTextField(labelWithString: "Hot key:"), hotKeyField],
            [NSGridCell.emptyContentView, hotKeyHintLabel],
            [NSTextField(labelWithString: "Search:"), openWindowsCheckbox],
            [NSGridCell.emptyContentView, iCloudDriveCheckbox],
            [NSGridCell.emptyContentView, xcodeApplicationsCheckbox],
        ])
        gridView.rowSpacing = 8
        gridView.column(at: 0).xPlacement = .trailing
        gridView.rowAlignment = .firstBaseline
        gridView.row(at: 2).topPadding = 12
        hotKeyField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        view = NSView()
        view.addSubview(gridView)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            gridView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -20
            ),
            gridView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 20
            ),
            gridView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -20
            ),
        ])
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    func reload(config: DeweyConfig) {
        loadViewIfNeeded()
        hotKeyField.stringValue = config.hotKey.rawValue
        updateHotKeyHint(isValid: true)
        openWindowsCheckbox.state = config.includeOpenWindows ? .on : .off
        xcodeApplicationsCheckbox.state = config.includeXcodeApplications
            ? .on
            : .off
        iCloudDriveCheckbox.state = config.includeICloudDrive ? .on : .off
    }

    // MARK: - Actions

    @objc
    private func didEditHotKey() {
        guard let chord = HotKeyChord(rawValue: hotKeyField.stringValue) else {
            updateHotKeyHint(isValid: false)
            return
        }
        updateHotKeyHint(isValid: true)
        hotKeyField.stringValue = chord.rawValue
        edit { $0.hotKey = chord }
    }

    @objc
    private func didToggleCheckbox() {
        let includeOpenWindows = openWindowsCheckbox.state == .on
        let includeXcodeApplications = xcodeApplicationsCheckbox.state == .on
        let includeICloudDrive = iCloudDriveCheckbox.state == .on
        edit {
            $0.includeOpenWindows = includeOpenWindows
            $0.includeXcodeApplications = includeXcodeApplications
            $0.includeICloudDrive = includeICloudDrive
        }
    }

    // MARK: -

    private func updateHotKeyHint(isValid: Bool) {
        if isValid {
            hotKeyHintLabel.stringValue = "e.g. \"control+option+d\""
            hotKeyHintLabel.textColor = .secondaryLabelColor
        } else {
            hotKeyHintLabel.stringValue =
                "Not a hot key. Try e.g. \"control+option+d\"."
            hotKeyHintLabel.textColor = .systemOrange
        }
    }

    private func checkbox(title: String) -> NSButton {
        NSButton(
            checkboxWithTitle: title,
            target: self,
            action: #selector(didToggleCheckbox)
        )
    }
}
