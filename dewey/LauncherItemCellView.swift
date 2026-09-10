//
//  LauncherItemCellView.swift
//  dewey
//

import Cocoa

final class LauncherItemCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("LauncherItemCellView")

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

        NSLayoutConstraint.activate([
            // Matches the search icon's leading inset, so the icon column
            // lines up with the field above.
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: -18),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            switch backgroundStyle {
            case .emphasized:
                subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
            default:
                subtitleLabel.textColor = .secondaryLabelColor
            }
        }
    }

    func configure(with item: LauncherItem) {
        iconView.image = item.icon
        titleLabel.stringValue = item.name
        subtitleLabel.stringValue = item.subtitle
    }
}
