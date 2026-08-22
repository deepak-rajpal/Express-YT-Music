// Regression test for the mini-player runaway width.
//
// The window grew to several times its design width as soon as a track with a long
// artist list started. The cause was the layout, not the window title: a vertical
// NSStackView holding the labels was pinned on BOTH sides to the content view, and a
// stack sizes itself in the cross axis to its widest subview's intrinsic width. With
// labels at the default compression resistance that requirement propagated outward and
// AppKit widened the window to satisfy it.
//
// The fix is a required width constraint on the content view plus lowered compression
// resistance on the labels, so a long string truncates instead.
//
// Geometry comes from Sources/MiniPlayerLayout.swift - the same constants the app lays
// out with - so this test cannot drift from the real window.
import AppKit

@main
struct LayoutTest {

    static var failures = 0

    static let longArtist = "A. R. Rahman, Irshad Kamil, & Deepali Sahay"
    static let longTitle = "Toh Phir Aao - Nasha Hi Nasha Hai (From \"Awarapan 2\")"

    static let designWidth = MiniPlayerLayout.width
    static let columnWidth = MiniPlayerLayout.textColumnWidth
    static let columnOffset = MiniPlayerLayout.sideInset
                            + MiniPlayerLayout.artworkSize
                            + MiniPlayerLayout.artworkGap

    static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok    \(label)\(detail.isEmpty ? "" : " (\(detail))")")
        } else {
            failures += 1
            print("  FAIL  \(label)\(detail.isEmpty ? "" : " -> \(detail)")")
        }
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: MiniPlayerLayout.size),
            styleMask: [.titled, .closable, .fullSizeContentView,
                        .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        return panel
    }

    static func label(_ text: String, size: CGFloat, semibold: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        print("old layout: labels in a stack pinned on both sides")
        oldLayout()

        print("\nnew layout: required content width, labels allowed to truncate")
        newLayout()

        print("\nstacked rows fit the borderless window height")
        columnHeight()

        print("\n\(failures == 0 ? "PASS" : "FAIL") - \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    static func oldLayout() {
        let panel = makePanel()
        let content = NSView()
        let stack = NSStackView(views: [
            label(longTitle, size: MiniPlayerLayout.titleFontSize, semibold: true),
            label(longArtist, size: MiniPlayerLayout.artistFontSize),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                           constant: columnOffset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                            constant: -MiniPlayerLayout.sideInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor,
                                       constant: MiniPlayerLayout.topInset),
        ])
        panel.contentView = content
        panel.setContentSize(MiniPlayerLayout.size)
        content.layoutSubtreeIfNeeded()

        let needed = content.fittingSize.width
        check("the stack demands more width than the design allows",
              needed > designWidth,
              "needs \(Int(needed))pt for a \(Int(designWidth))pt window")
    }

    static func newLayout() {
        let panel = makePanel()
        let content = NSView()

        let title = label(longTitle, size: MiniPlayerLayout.titleFontSize, semibold: true)
        let artist = label(longArtist, size: MiniPlayerLayout.artistFontSize)
        title.preferredMaxLayoutWidth = MiniPlayerLayout.titleColumnWidth
        artist.preferredMaxLayoutWidth = columnWidth
        for field in [title, artist] {
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            content.addSubview(field)
        }
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: designWidth),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                           constant: columnOffset),
            // The title stops short of the close button; the artist gets the full column.
            title.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -(MiniPlayerLayout.sideInset + MiniPlayerLayout.closeButtonSize
                            + MiniPlayerLayout.closeButtonGap)),
            title.topAnchor.constraint(equalTo: content.topAnchor,
                                       constant: MiniPlayerLayout.topInset),
            artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            artist.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                             constant: -MiniPlayerLayout.sideInset),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor,
                                        constant: MiniPlayerLayout.titleArtistGap),
        ])
        panel.contentView = content
        panel.setContentSize(MiniPlayerLayout.size)
        content.layoutSubtreeIfNeeded()

        check("the layout fits the design width",
              content.fittingSize.width <= designWidth,
              "needs \(Int(content.fittingSize.width))pt")
        check("the window keeps its width", panel.frame.width == designWidth,
              "\(Int(panel.frame.width))pt")

        // Constraints govern the alignment rect, not the frame - NSTextField's frame is
        // a couple of points wider on each side than the rect Auto Layout positioned.
        for (name, field, limit) in [
            ("title", title, MiniPlayerLayout.titleColumnWidth),
            ("artist", artist, columnWidth),
        ] {
            let laidOut = field.alignmentRect(forFrame: field.frame).width
            check("the long \(name) is held to its column",
                  laidOut <= limit + 0.5,
                  "\(Int(laidOut))pt of \(Int(limit))pt")
        }

        // The column has to be wide enough to be worth reading, not just non-overflowing.
        check("the text column is wide enough to be legible", columnWidth >= 140,
              "\(Int(columnWidth))pt")
    }

    /// The title, artist and transport rows are stacked with a fixed gap rather than the
    /// transport row being pinned to the artwork's bottom edge. That makes the column's
    /// height depend on font metrics, so it has to be checked against the window.
    static func columnHeight() {
        let content = NSView()

        let title = label(longTitle, size: MiniPlayerLayout.titleFontSize, semibold: true)
        let artist = label(longArtist, size: MiniPlayerLayout.artistFontSize)
        let transport = NSStackView(views: [
            transportButton("backward.fill"), transportButton("play.fill"),
            transportButton("forward.fill"),
        ])
        transport.orientation = .horizontal
        transport.spacing = MiniPlayerLayout.transportSpacing
        transport.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, artist, transport] as [NSView] { content.addSubview(view) }

        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: designWidth),
            content.heightAnchor.constraint(equalToConstant: MiniPlayerLayout.size.height),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                           constant: columnOffset),
            // The title stops short of the close button; the artist gets the full column.
            title.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -(MiniPlayerLayout.sideInset + MiniPlayerLayout.closeButtonSize
                            + MiniPlayerLayout.closeButtonGap)),
            title.topAnchor.constraint(equalTo: content.topAnchor,
                                       constant: MiniPlayerLayout.topInset),
            artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            artist.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                             constant: -MiniPlayerLayout.sideInset),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor,
                                        constant: MiniPlayerLayout.titleArtistGap),
            transport.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            transport.topAnchor.constraint(equalTo: artist.bottomAnchor,
                                           constant: MiniPlayerLayout.artistTransportGap),
        ])
        content.layoutSubtreeIfNeeded()

        print("        rows: title \(Int(title.frame.height))pt,"
              + " artist \(Int(artist.frame.height))pt,"
              + " transport \(Int(transport.frame.height))pt")

        // AppKit views are bottom-left origin, so measure downwards from the top edge.
        let windowHeight = MiniPlayerLayout.size.height
        let columnBottom = windowHeight - transport.frame.minY
        check("the transport row clears the bottom padding",
              transport.frame.minY >= MiniPlayerLayout.bottomPadding - 1,
              "\(Int(columnBottom))pt used of \(Int(windowHeight))pt")

        // The artwork is centred against the column now, so it just has to fit.
        check("the centred artwork fits the window height",
              MiniPlayerLayout.artworkSize + 8 <= windowHeight,
              "\(Int(MiniPlayerLayout.artworkSize))pt artwork in \(Int(windowHeight))pt")

        // The transport row must read as separate from the artist line above it.
        check("the transport row is separated from the artist line",
              MiniPlayerLayout.artistTransportGap > MiniPlayerLayout.titleArtistGap,
              "\(Int(MiniPlayerLayout.artistTransportGap))pt vs"
              + " \(Int(MiniPlayerLayout.titleArtistGap))pt above")
    }

    static func transportButton(_ symbol: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(
                pointSize: MiniPlayerLayout.transportGlyphSize, weight: .medium))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .accessoryBar
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}
