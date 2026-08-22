// Generates AppIcon.icns without needing any binary assets in the repo.
// Draws the app icon - a dark green tile with a white inner border and a treble
// clef - and writes the iconset PNGs; the Makefile leaves iconutil to assemble them.
import AppKit
import CoreText

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(calibratedRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

private let inkGreen = rgb(43, 94, 26)      // #2B5E1A
private let topGreen = rgb(61, 133, 37)     // gradient highlight
private let clef = "\u{1D11E}"              // MUSICAL SYMBOL G CLEF

private let cornerFactor: CGFloat = 0.225   // matches Apple's squircle closely enough
private let borderFactor: CGFloat = 0.030
private let glyphFill: CGFloat = 0.60       // fraction of the tile the clef's ink occupies

/// Draws a text glyph centred on its actual ink and scaled to fill the tile.
///
/// Centring on the typographic box instead would sit the mark high and render it
/// small, because the font's ascent and descent reserve room for staff lines this
/// glyph does not draw.
private func drawClef(size: CGFloat) {
    let font = NSFont.systemFont(ofSize: size * 0.6, weight: .medium)
    let attributed = NSAttributedString(string: clef, attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
    ])
    let line = CTLineCreateWithAttributedString(attributed)

    // .useGlyphPathBounds gives tight ink bounds, and handles the surrogate pair
    // and font substitution (the clef comes from AppleSymbols) for us.
    let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    guard ink.width > 0, ink.height > 0,
          let ctx = NSGraphicsContext.current?.cgContext else { return }

    let scale = (size * glyphFill) / max(ink.width, ink.height)
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -ink.midX, y: -ink.midY)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

private func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * cornerFactor
    let tile = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [topGreen, inkGreen])?.draw(in: tile, angle: -90)

    // Inner border, inset far enough that its own stroke width does not clip the tile edge.
    let width = max(1, size * borderFactor)
    let borderInset = inset + width * 1.9
    let borderRect = NSRect(x: borderInset, y: borderInset,
                            width: size - borderInset * 2, height: size - borderInset * 2)
    let borderRadius = max(1, radius - width * 1.9)
    let border = NSBezierPath(roundedRect: borderRect, xRadius: borderRadius, yRadius: borderRadius)
    border.lineWidth = width
    NSColor.white.setStroke()
    border.stroke()

    drawClef(size: size)

    image.unlockFocus()
    return image
}

private func write(_ image: NSImage, to file: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: file))
}

// The set iconutil expects for a complete .icns
let variants: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"),      (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),      (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),   (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),   (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),   (512, 2, "icon_512x512@2x.png"),
]

for (base, scale, name) in variants {
    let pixels = CGFloat(base * scale)
    let image = drawIcon(size: pixels)
    // Report the pixel dimensions so the PNG has the resolution iconutil wants.
    image.size = NSSize(width: pixels, height: pixels)
    write(image, to: "\(outDir)/\(name)")
}

print("wrote iconset to \(outDir)")
