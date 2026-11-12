//
//  PathListView.swift
//  dewey
//

import Cocoa

/// An editable list of file or directory paths, with add and remove buttons.
final class PathListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private enum Metrics {
        static let width: CGFloat = 420
        static let visibleRows = 5
        static let rowHeight: CGFloat = 22
        static let buttonWidth: CGFloat = 24
    }

    private enum Segment: Int {
        case add
        case remove
    }

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("path")

    var paths = [String]() {
        didSet {
            tableView.reloadData()
            updateRemoveButton()
        }
    }

    /// Called after the user adds or removes paths.
    var onChange: ([String]) -> Void = { _ in }

    private let openPanelMessage: String
    private let choosesFiles: Bool

    private lazy var tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: Self.cellIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        return tableView
    }()

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }()

    private lazy var buttons: NSSegmentedControl = {
        let buttons = NSSegmentedControl(
            images: [
                NSImage(named: NSImage.addTemplateName)!,
                NSImage(named: NSImage.removeTemplateName)!,
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(didClickButton)
        )
        buttons.segmentStyle = .smallSquare
        for segment in 0..<buttons.segmentCount {
            buttons.setWidth(Metrics.buttonWidth, forSegment: segment)
        }
        return buttons
    }()

    init(openPanelMessage: String, choosesFiles: Bool) {
        self.openPanelMessage = openPanelMessage
        self.choosesFiles = choosesFiles
        super.init(frame: .zero)

        addSubview(scrollView)
        addSubview(buttons)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let height = Metrics.rowHeight * CGFloat(Metrics.visibleRows)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: Metrics.width),
            scrollView.heightAnchor.constraint(equalToConstant: height),
            // Overlap the scroll view's border.
            buttons.topAnchor.constraint(
                equalTo: scrollView.bottomAnchor,
                constant: -1
            ),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateRemoveButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        paths.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let label = tableView.makeView(
            withIdentifier: Self.cellIdentifier,
            owner: self
        ) as? NSTextField ?? {
            let label = NSTextField(labelWithString: "")
            label.identifier = Self.cellIdentifier
            label.lineBreakMode = .byTruncatingMiddle
            return label
        }()
        label.stringValue = paths[row]
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }

    // MARK: - Actions

    @objc
    private func didClickButton() {
        switch Segment(rawValue: buttons.selectedSegment) {
        case .add:
            Task { await addPaths() }
        case .remove:
            removeSelectedPaths()
        case nil:
            break
        }
    }

    private func addPaths() async {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = choosesFiles
        panel.canChooseDirectories = !choosesFiles
        panel.allowsMultipleSelection = true
        panel.message = openPanelMessage
        let response = await panel.beginSheetModal(for: window)
        switch response {
        case .OK:
            break
        default:
            return
        }

        // Portable between Macs.
        let newPaths = panel.urls
            .map { ($0.path as NSString).abbreviatingWithTildeInPath }
            .filter { !paths.contains($0) }
        guard !newPaths.isEmpty else { return }

        paths += newPaths
        onChange(paths)
    }

    private func removeSelectedPaths() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        paths = paths.enumerated()
            .filter { !selectedRows.contains($0.offset) }
            .map { $0.element }
        onChange(paths)
    }

    private func updateRemoveButton() {
        buttons.setEnabled(
            !tableView.selectedRowIndexes.isEmpty,
            forSegment: Segment.remove.rawValue
        )
    }
}
