// Generates AppIcon.icns without needing any binary assets in the repo.
// Draws a rounded-rect gradient tile with a music note, writes the iconset PNGs,
// and leaves iconutil to assemble them (see the Makefile).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect,
                            xRadius: size * 0.225,
                            yRadius: size * 0.225)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.94, green: 0.20, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.70, green: 0.09, blue: 0.36, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -90)

    // Music note from the system symbol, tinted white.
    // The tint has to happen in a separate transparent image: compositing
    // .sourceAtop straight onto the opaque gradient would flood the whole glyph box.
    let glyphPoint = size * 0.44
    if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: glyphPoint, weight: .medium)
        let glyph = symbol.withSymbolConfiguration(config) ?? symbol

        let tinted = NSImage(size: glyph.size)
        tinted.lockFocus()
        let glyphRect = NSRect(origin: .zero, size: glyph.size)
        glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        glyphRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let target = NSRect(
            x: (size - glyph.size.width) / 2,
            y: (size - glyph.size.height) / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, to file: String) {
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
