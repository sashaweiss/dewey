//
//  LauncherItemCellView.swift
//  dewey
//

import Cocoa

final class LauncherItemCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LauncherItemCellView")

    private typealias Metrics = LauncherPanelController.Metrics

    private lazy var iconView: NSImageView = {
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        return iconView
    }()

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 15)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        // Wire the standard outlets so selection restyles the title.
        imageView = iconView
        textField = titleLabel

        for subview in [iconView, titleLabel, subtitleLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        // Center the title/subtitle pair on the row without hardcoding the
        // fonts' heights.
        let above = titleLabel.topAnchor.anchorWithOffset(to: centerYAnchor)
        let below = centerYAnchor.anchorWithOffset(to: subtitleLabel.bottomAnchor)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Metrics.contentInset
            ),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconColumnWidth),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconColumnWidth),

            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Metrics.textLeading
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.contentInset
            ),
            above.constraint(equalTo: below),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Metrics.contentInset
            ),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            switch backgroundStyle {
            case .emphasized:
                subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
            default:
                subtitleLabel.textColor = .secondaryLabelColor
            }
        }
    }

    func configure(with item: LauncherItem) {
        iconView.image = item.icon
        titleLabel.stringValue = item.title
        subtitleLabel.stringValue = item.subtitle
    }
}
