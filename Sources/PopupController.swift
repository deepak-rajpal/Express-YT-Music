import AppKit
import WebKit

/// The panel that drops down from the menu-bar icon and hosts the web player.
///
/// It is a real key window (not a non-activating panel) because you have to be able
/// to type into Google's sign-in form.
final class PopupController: NSObject, NSWindowDelegate {

    private var panel: NSPanel!
    private weak var anchorButton: NSStatusBarButton?

    var isVisible: Bool { panel.isVisible }

    override init() {
        super.init()
        build()
    }

    /// Never let a restored (or zoomed) size come back larger than the screen can
    /// sensibly hold - the panel is a menu-bar dropdown, not a full window.
    private static func clampedSize(_ size: NSSize) -> NSSize {
        let minSize = NSSize(width: 360, height: 420)
        guard let screen = NSScreen.main else { return size }
        let limit = screen.visibleFrame.size
        return NSSize(
            width: min(max(size.width, minSize.width), limit.width * 0.7),
            height: min(max(size.height, minSize.height), limit.height * 0.85)
        )
    }

    private func build() {
        let size = Self.clampedSize(Preferences.popupSize)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Express YT Music"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // YouTube Music's UI is always dark, so match it - otherwise the transparent
        // title-bar strip flashes white above the page.
        panel.backgroundColor = NSColor(calibratedWhite: 0.012, alpha: 1.0)
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 420)
        panel.delegate = self
        // Must be able to become key: the Google sign-in form needs keyboard input.
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true

        // The minimise button is inert on a panel and would strand the window in a Dock
        // this app has no icon in; zoom is what previously left it stuck at full width.
        // Only close remains - the panel is still resizable by dragging its edges.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let web = WebPlayerController.shared.webView!
        web.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            // leave a slim strip below the traffic lights so the window stays draggable
            web.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
        ])
        panel.contentView = content
    }

    // MARK: - Show / hide

    /// Passing `nil` reuses the last anchor, so a global hot key opens the panel
    /// in the same place a click on the menu-bar icon would.
    func toggle(relativeTo button: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton?) {
        if let button { anchorButton = button }
        // Re-clamp in case the window was zoomed, or the display changed since last time.
        let clamped = Self.clampedSize(panel.frame.size)
        if clamped != panel.frame.size {
            panel.setContentSize(clamped)
        }
        WebPlayerController.shared.loadHomeIfNeeded()
        position(relativeTo: button ?? anchorButton)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        WebPlayerController.shared.refreshState()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position(relativeTo button: NSStatusBarButton?) {
        guard let button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            // No anchor yet (first open came from a hot key): fall back to the
            // top-centre of the main screen.
            if let screen = NSScreen.main {
                let size = panel.frame.size
                let visible = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                             y: visible.maxY - size.height - 8))
            }
            return
        }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let gap: CGFloat = 6

        var x = buttonRect.midX - size.width / 2
        var y = buttonRect.minY - size.height - gap

        let visible = screen.visibleFrame
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        if y < visible.minY + 8 { y = visible.minY + 8 }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard Preferences.hideOnFocusLoss else { return }
        // Do not vanish while a sheet or modal (e.g. a JS alert) is up.
        guard panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        // Give focus a moment to settle - clicking our own mini player or menu should
        // not count as "the user looked away".
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if !self.panel.isKeyWindow && NSApp.keyWindow == nil {
                self.hide()
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        // Persist what the user chose, but only within the sane range, so a zoom does
        // not become the permanent size.
        Preferences.popupSize = Self.clampedSize(panel.frame.size)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
