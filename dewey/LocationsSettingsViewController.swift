//
//  LocationsSettingsViewController.swift
//  dewey
//

import Cocoa

/// Edits the locations searched for apps, folders, and files.
final class LocationsSettingsViewController: NSViewController {
    private let edit: (SettingsWindowController.Edit) -> Void

    private lazy var applicationDirectoriesView = PathListView(
        openPanelMessage: "Choose folders to search for apps.",
        choosesFiles: false
    )
    private lazy var searchedDirectoriesView = PathListView(
        openPanelMessage: "Choose folders whose subfolders are searched.",
        choosesFiles: false
    )
    private lazy var filesView = PathListView(
        openPanelMessage: "Choose files to include.",
        choosesFiles: true
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
        filesView.onChange = { [weak self] paths in
            self?.edit { $0.files = paths }
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
            [
                NSTextField(labelWithString: "Files:"),
                filesView,
            ],
            [
                NSGridCell.emptyContentView,
                caption(string: "These files themselves."),
            ],
        ])
        gridView.rowSpacing = 8
        gridView.column(at: 0).xPlacement = .trailing
        gridView.row(at: 0).yPlacement = .top
        gridView.row(at: 2).yPlacement = .top
        gridView.row(at: 2).topPadding = 12
        gridView.row(at: 4).yPlacement = .top
        gridView.row(at: 4).topPadding = 12

        view = NSView()
        view.addSubview(gridView)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: 20
            ),
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
        filesView.paths = config.files
    }

    // MARK: -

    private func caption(string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabelColor
        return label
    }
}
