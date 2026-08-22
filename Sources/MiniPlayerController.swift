import AppKit

/// Content view that reports hover, so the close button can stay out of the way until
/// the pointer is over the window.
private final class HoverView: NSVisualEffectView {

    var onHover: ((Bool) -> Void)?

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Small floating window with artwork, track text and transport buttons.
///
/// Borderless on purpose: a titled panel spends a whole ~22pt row on a titlebar strip
/// that exists only to hold a close button. Here the close button is a hover-revealed
/// badge on the artwork, the window is dragged by its background, and right-clicking
/// anywhere gives the same options.
///
/// Fixed size: the content view carries a required width constraint and the labels have
/// lowered compression resistance, so a long track name truncates instead of stretching
/// the window. Do not put the labels in an NSStackView pinned on both sides - a stack
/// sizes itself in the cross axis to its widest subview, which demands well over 400pt
/// for a long artist list and drags the window wider with it. Tools/layouttest.swift
/// asserts against exactly that regression.
final class MiniPlayerController: NSObject, NSWindowDelegate {

    private var panel: NSPanel!
    private var container: HoverView!
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Nothing playing")
    private let artistLabel = NSTextField(labelWithString: "")
    private let playPauseButton = NSButton()
    private let closeButton = NSButton()

    /// Always on screen; hovering only makes it more prominent.
    private static let closeIdleAlpha: CGFloat = 0.45
    private static let closeHoverAlpha: CGFloat = 0.95

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        build()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .playerStateChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .artworkChanged, object: nil)
        refresh()
    }

    private func build() {
        let L = MiniPlayerLayout.self
        let size = L.size

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Mini Player"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        // Borderless windows draw no background of their own, so the rounded, blurred
        // material is the content view's job.
        container = HoverView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = L.cornerRadius
        container.layer?.masksToBounds = true
        container.onHover = { [weak self] inside in
            self?.setCloseButtonVisible(inside)
        }

        artworkView.imageScaling = .scaleProportionallyDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 5
        artworkView.layer?.masksToBounds = true
        artworkView.layer?.backgroundColor =
            NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        // Not tertiaryLabelColor: inside a vibrant NSVisualEffectView it blends into the
        // backdrop and the placeholder glyph disappears entirely.
        artworkView.contentTintColor = .secondaryLabelColor
        artworkView.image = Self.placeholderArtwork
        artworkView.translatesAutoresizingMaskIntoConstraints = false

        for label in [titleLabel, artistLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
            label.preferredMaxLayoutWidth = L.textColumnWidth
            label.translatesAutoresizingMaskIntoConstraints = false
            // Long track names must truncate rather than force the window wider.
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        titleLabel.font = .systemFont(ofSize: L.titleFontSize, weight: .semibold)
        artistLabel.font = .systemFont(ofSize: L.artistFontSize)
        artistLabel.textColor = .secondaryLabelColor
        titleLabel.preferredMaxLayoutWidth = L.titleColumnWidth

        let prev = transportButton("backward.fill", action: #selector(previous), tip: "Previous")
        configureTransport(playPauseButton, symbol: "play.fill", action: #selector(togglePlayPause))
        playPauseButton.toolTip = "Play / Pause"
        let next = transportButton("forward.fill", action: #selector(nextTrack), tip: "Next")

        let transport = NSStackView(views: [prev, playPauseButton, next])
        transport.orientation = .horizontal
        transport.spacing = L.transportSpacing
        transport.translatesAutoresizingMaskIntoConstraints = false

        // Top-right corner, sharing the title's row rather than occupying one of its own.
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close")?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: L.closeButtonSize - 1, weight: .semibold))
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.bezelStyle = .accessoryBar
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Hide Mini Player"
        closeButton.alphaValue = Self.closeIdleAlpha
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(artworkView)
        container.addSubview(titleLabel)
        container.addSubview(artistLabel)
        container.addSubview(transport)
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Required, and the reason a long track name cannot stretch this window:
            // the labels lose this argument and truncate.
            container.widthAnchor.constraint(equalToConstant: L.width),
            container.heightAnchor.constraint(equalToConstant: L.height),

            artworkView.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                                 constant: L.sideInset),
            // Centred: the artwork is now shorter than the text column beside it.
            artworkView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: L.artworkSize),
            artworkView.heightAnchor.constraint(equalToConstant: L.artworkSize),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor,
                                                constant: L.artworkGap),
            // Stops short of the close button rather than running under it.
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor,
                                                 constant: -L.closeButtonGap),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor,
                                            constant: L.topInset),

            artistLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            artistLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                  constant: -L.sideInset),
            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                                             constant: L.titleArtistGap),

            transport.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            transport.topAnchor.constraint(equalTo: artistLabel.bottomAnchor,
                                           constant: L.artistTransportGap),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                  constant: -L.sideInset + 2),
            closeButton.topAnchor.constraint(equalTo: container.topAnchor,
                                             constant: L.topInset - 1),
        ])

        panel.contentView = container
        panel.setContentSize(size)
        panel.minSize = size
        panel.maxSize = size
        container.menu = buildContextMenu()
        applyWindowLevel()
        panel.center()
    }

    /// Right-click anywhere on the window - the borderless panel has no titlebar menu.
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let onTop = NSMenuItem(title: "Keep on Top",
                               action: #selector(toggleAlwaysOnTopFromMenu),
                               keyEquivalent: "")
        onTop.target = self
        onTop.state = Preferences.miniPlayerAlwaysOnTop ? .on : .off
        menu.addItem(onTop)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Mini Player",
                              action: #selector(closeClicked),
                              keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }

    private func setCloseButtonVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            closeButton.animator().alphaValue =
                visible ? Self.closeHoverAlpha : Self.closeIdleAlpha
        }
    }

    /// Sized so `.scaleProportionallyDown` centres it instead of filling the tile.
    private static let placeholderArtwork: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        return NSImage(systemSymbolName: "music.note", accessibilityDescription: "No artwork")?
            .withSymbolConfiguration(config)
    }()

    private static let transportConfig = NSImage.SymbolConfiguration(
        pointSize: MiniPlayerLayout.transportGlyphSize, weight: .medium)

    private func transportButton(_ symbol: String, action: Selector, tip: String) -> NSButton {
        let button = NSButton()
        configureTransport(button, symbol: symbol, action: action)
        button.toolTip = tip
        return button
    }

    private func configureTransport(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(Self.transportConfig)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .accessoryBar
        button.target = self
        button.action = action
        button.contentTintColor = .labelColor
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Actions

    @objc private func togglePlayPause() { WebPlayerController.shared.togglePlayPause() }
    @objc private func nextTrack()       { WebPlayerController.shared.nextTrack() }
    @objc private func previous()        { WebPlayerController.shared.previousTrack() }
    @objc private func closeClicked()    { hide() }

    @objc private func toggleAlwaysOnTopFromMenu() { toggleAlwaysOnTop() }

    // MARK: - Always on top

    /// `.floating` keeps the panel above other applications' windows; `.normal` lets it
    /// fall behind them like an ordinary window.
    private func applyWindowLevel() {
        panel.level = Preferences.miniPlayerAlwaysOnTop ? .floating : .normal
    }

    func toggleAlwaysOnTop() {
        Preferences.miniPlayerAlwaysOnTop.toggle()
        applyWindowLevel()
        container.menu = buildContextMenu()
        if panel.isVisible {
            if Preferences.miniPlayerAlwaysOnTop {
                panel.orderFrontRegardless()
            } else {
                panel.orderFront(nil)
            }
        }
    }

    // MARK: - Visibility

    func show() {
        applyWindowLevel()
        panel.orderFrontRegardless()
        Preferences.miniPlayerOpen = true
    }

    func hide() {
        panel.orderOut(nil)
        Preferences.miniPlayerOpen = false
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    // MARK: - Rendering

    @objc private func refresh() {
        let state = PlayerStore.shared.state

        titleLabel.stringValue = state.hasTrack ? state.title : "Nothing playing"
        artistLabel.stringValue = state.artist

        // The labels truncate, so put the full text where it stays reachable.
        container.toolTip = state.hasTrack ? state.summary : nil

        playPauseButton.image = NSImage(
            systemSymbolName: state.isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: state.isPlaying ? "Pause" : "Play"
        )?.withSymbolConfiguration(Self.transportConfig)

        if let image = ArtworkStore.shared.image,
           ArtworkStore.shared.url == state.artworkURL,
           !state.artworkURL.isEmpty {
            artworkView.image = image
            artworkView.contentTintColor = nil
        } else if !state.hasTrack {
            artworkView.image = Self.placeholderArtwork
            artworkView.contentTintColor = .secondaryLabelColor
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
