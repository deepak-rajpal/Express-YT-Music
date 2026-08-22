import AppKit
import CoreText

/// Builds the menu-bar glyph: a filled rounded tile with the treble clef knocked
/// out of it, matching the app icon's shape.
///
/// Why knocked out rather than an outlined square with a clef inside, which would
/// mirror the app icon more literally: at the ~18pt the menu bar allows, a border
/// plus a thin clef inside it collapses into an unreadable smudge. A solid tile
/// keeps enough mass to stay legible, and the clef punches through cleanly.
///
/// The image is a template, so macOS tints it for the current menu bar - dark on a
/// light bar, light on a dark one - and no colour from the app icon carries over.
enum MenuBarIcon {

    private static let clef = "\u{1D11E}"   // MUSICAL SYMBOL G CLEF
    private static let side: CGFloat = 18   // points; the menu bar's usable height

    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let full = NSRect(x: 0, y: 0, width: side, height: side)
            let tile = full.insetBy(dx: side * 0.03, dy: side * 0.03)
            let radius = side * 0.22
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius).fill()

            // Knock the clef out of the tile so it reads as a hole, not an overlay.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            drawClef(in: tile.insetBy(dx: side * 0.10, dy: side * 0.10))
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Express YT Music"
        return image
    }

    /// Centres the clef on its ink rather than its typographic box - the font
    /// reserves ascent and descent for staff lines this glyph never draws, so
    /// laying it out naively sits it high and renders it small.
    private static func drawClef(in rect: NSRect) {
        let font = NSFont.systemFont(ofSize: rect.height, weight: .medium)
        let attributed = NSAttributedString(string: clef, attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard ink.width > 0, ink.height > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scale = min(rect.width, rect.height) / max(ink.width, ink.height)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -ink.midX, y: -ink.midY)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
