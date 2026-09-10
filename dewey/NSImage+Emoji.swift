//
//  NSImage+Emoji.swift
//  dewey
//

import Cocoa

extension NSImage {
    /// Renders an emoji into an image exactly `side` points square. Not a
    /// template image: color emoji would come out as a solid blob if
    /// something tinted it.
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
