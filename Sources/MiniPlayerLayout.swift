import Foundation

/// Mini-player geometry, kept in one place so `Tools/layouttest.swift` asserts against
/// exactly the numbers the app lays out with, rather than a copy that can drift.
enum MiniPlayerLayout {

    static let width: CGFloat = 236

    /// Set explicitly rather than derived from the artwork, because the text column is
    /// now the taller side. `Tools/layouttest.swift` asserts the rows actually fit.
    static let height: CGFloat = 55

    static let artworkSize: CGFloat = 35
    static let sideInset: CGFloat = 12
    static let artworkGap: CGFloat = 10
    static let topInset: CGFloat = 7
    static let bottomPadding: CGFloat = 7

    /// Title and artist sit close together; the transport row needs visible separation
    /// from the text above it, or the buttons read as part of the artist line.
    static let titleArtistGap: CGFloat = 1
    static let artistTransportGap: CGFloat = 5

    /// Font and glyph sizes live here too, because the row heights - and therefore
    /// whether the stack fits `height` - depend on them. Tools/layouttest.swift builds
    /// its labels with these, so its measurements match the real window.
    static let titleFontSize: CGFloat = 12
    static let artistFontSize: CGFloat = 9.5
    static let transportGlyphSize: CGFloat = 10.5
    static let transportSpacing: CGFloat = 13

    static let closeButtonSize: CGFloat = 13
    static let closeButtonGap: CGFloat = 5
    static let cornerRadius: CGFloat = 12

    /// Space left for the artist and transport rows.
    static var textColumnWidth: CGFloat {
        width - sideInset * 2 - artworkSize - artworkGap
    }

    /// The title shares its row with the always-visible close button, so it stops short.
    static var titleColumnWidth: CGFloat {
        textColumnWidth - closeButtonSize - closeButtonGap
    }

    static var size: NSSize {
        NSSize(width: width, height: height)
    }
}
