//
//  LocationsSettingsViewController.swift
//  dewey
//

import Cocoa

/// Edits the directories searched for apps and for folders.
final class LocationsSettingsViewController: NSViewController {
    private let edit: (SettingsWindowController.Edit) -> Void

    private lazy var applicationDirectoriesView = PathListView(
        openPanelMessage: "Choose folders to search for apps."
    )
    private lazy var searchedDirectoriesView = PathListView(
        openPanelMessage: "Choose folders whose subfolders are searched."
    )

    init(edit: @escaping (SettingsWindowController.Edit) -> Void) {
        self.edit = edit
        super.init(nibName: nil, bundle: nil)
        title = "Locations"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        applicationDirectoriesView.onChange = { [weak self] paths in
            self?.edit { $0.applicationDirectories = paths }
        }
        searchedDirectoriesView.onChange = { [weak self] paths in
            self?.edit { $0.searchedDirectories = paths }
        }

        let gridView = NSGridView(views: [
            [
                NSTextField(labelWithString: "Apps:"),
                applicationDirectoriesView,
            ],
            [
                NSGridCell.emptyContentView,
                caption(string: "Apps in these folders and their subfolders."),
            ],
            [
                NSTextField(labelWithString: "Folders:"),
                searchedDirectoriesView,
            ],
            [
                NSGridCell.emptyContentView,
                caption(string: "The subfolders of these folders."),
            ],
        ])
        gridView.rowSpacing = 8
        gridView.column(at: 0).xPlacement = .trailing
        gridView.row(at: 0).yPlacement = .top
        gridView.row(at: 2).yPlacement = .top
        gridView.row(at: 2).topPadding = 12

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
        applicationDirectoriesView.paths = config.applicationDirectories
        searchedDirectoriesView.paths = config.searchedDirectories
    }

    // MARK: -

    private func caption(string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabelColor
        return label
    }
}
