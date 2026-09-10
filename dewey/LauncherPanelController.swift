//
//  LauncherPanelController.swift
//  dewey
//

import Cocoa

final class LauncherPanelController: NSWindowController, NSWindowDelegate,
    NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private enum Metrics {
        static let panelWidth: CGFloat = 640
        static let searchAreaHeight: CGFloat = 56
        static let separatorHeight: CGFloat = 1
        static let rowHeight: CGFloat = 44
        static let maxVisibleRows = 8
        static let listVerticalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 14
    }

    private let sources: [LauncherItemSource]
    private var allItems = [LauncherItem]()
    private var results = [LauncherItem]()

    /// The y-coordinate the top edge of the panel is pinned to while visible,
    /// so the search field stays put as the result list grows and shrinks.
    private var panelTopY: CGFloat = 0

    // MARK: - Views

    private lazy var searchIconView: NSImageView = {
        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: nil
        )
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 18,
            weight: .medium
        )
        iconView.contentTintColor = .secondaryLabelColor
        return iconView
    }()

    private lazy var searchField: NSTextField = {
        let field = NSTextField()
        field.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        field.placeholderString = "Search"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        return field
    }()

    private lazy var separatorBox: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    private lazy var tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.backgroundColor = .clear
        tableView.refusesFirstResponder = true
        tableView.target = self
        tableView.action = #selector(didClickTableRow)
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("result")
        )
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        return tableView
    }()

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Metrics.listVerticalPadding / 2,
            left: 0,
            bottom: Metrics.listVerticalPadding / 2,
            right: 0
        )
        return scrollView
    }()

    // MARK: - Init

    init(sources: [LauncherItemSource]) {
        self.sources = sources

        let panel = LauncherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Metrics.panelWidth,
                height: Metrics.searchAreaHeight + Metrics.separatorHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)

        panel.delegate = self
        panel.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContentView() -> NSView {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Metrics.cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        for subview in [searchIconView, searchField, separatorBox, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            effectView.addSubview(subview)
        }

        let searchCenterY = effectView.topAnchor.anchorWithOffset(
            to: searchIconView.centerYAnchor
        )
        let fieldCenterY = effectView.topAnchor.anchorWithOffset(
            to: searchField.centerYAnchor
        )

        NSLayoutConstraint.activate([
            searchCenterY.constraint(equalToConstant: Metrics.searchAreaHeight / 2),
            searchIconView.leadingAnchor.constraint(
                equalTo: effectView.leadingAnchor,
                constant: 18
            ),

            fieldCenterY.constraint(equalToConstant: Metrics.searchAreaHeight / 2),
            searchField.leadingAnchor.constraint(
                equalTo: searchIconView.trailingAnchor,
                constant: 10
            ),
            searchField.trailingAnchor.constraint(
                equalTo: effectView.trailingAnchor,
                constant: -18
            ),

            separatorBox.topAnchor.constraint(
                equalTo: effectView.topAnchor,
                constant: Metrics.searchAreaHeight
            ),
            separatorBox.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            separatorBox.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            separatorBox.heightAnchor.constraint(
                equalToConstant: Metrics.separatorHeight
            ),

            scrollView.topAnchor.constraint(equalTo: separatorBox.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        return effectView
    }

    // MARK: - Showing and hiding

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let panel = window, let screen = NSScreen.main else { return }

        allItems = sources.flatMap { $0.loadItems() }

        searchField.stringValue = ""
        updateResults()

        let screenFrame = screen.visibleFrame
        panelTopY = screenFrame.maxY - screenFrame.height * 0.25
        layoutPanel(centeringOn: screenFrame)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Resizes the panel to fit the current results, keeping its top edge
    /// (and thus the search field) fixed at `panelTopY`.
    private func layoutPanel(centeringOn screenFrame: NSRect? = nil) {
        guard let panel = window else { return }

        let listHeight: CGFloat
        if results.isEmpty {
            listHeight = 0
        } else {
            let visibleRows = min(results.count, Metrics.maxVisibleRows)
            listHeight = CGFloat(visibleRows) * Metrics.rowHeight
                + Metrics.listVerticalPadding
        }
        let panelHeight = Metrics.searchAreaHeight + Metrics.separatorHeight
            + listHeight

        separatorBox.isHidden = results.isEmpty
        scrollView.isHidden = results.isEmpty

        var frame = panel.frame
        frame.size = NSSize(width: Metrics.panelWidth, height: panelHeight)
        frame.origin.y = panelTopY - panelHeight
        if let screenFrame {
            frame.origin.x = screenFrame.midX - Metrics.panelWidth / 2
        }
        panel.setFrame(frame, display: true)
    }

    // MARK: - Search

    private func updateResults() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            results = []
        } else {
            let scoredItems = allItems.compactMap { item -> (LauncherItem, Int)? in
                guard let score = FuzzyMatch.score(query: query, candidate: item.name) else {
                    return nil
                }
                return (item, score)
            }
            results = scoredItems
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 {
                        return lhs.1 > rhs.1
                    }
                    return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name)
                        == .orderedAscending
                }
                .map(\.0)
        }

        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        layoutPanel()
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }

        let currentRow = tableView.selectedRow
        let newRow = max(0, min(results.count - 1, currentRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    private func openSelection() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < results.count else { return }

        hide()
        results[selectedRow].open()
    }

    @objc
    private func didClickTableRow() {
        guard tableView.clickedRow >= 0 else { return }

        tableView.selectRowIndexes(
            IndexSet(integer: tableView.clickedRow),
            byExtendingSelection: false
        )
        openSelection()
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        updateResults()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cellView = tableView.makeView(
            withIdentifier: LauncherItemCellView.reuseIdentifier,
            owner: nil
        ) as? LauncherItemCellView ?? LauncherItemCellView()

        cellView.configure(with: results[row])
        return cellView
    }
}
