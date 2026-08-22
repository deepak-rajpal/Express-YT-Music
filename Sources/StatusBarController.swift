import AppKit

/// The menu-bar item: icon, optional track title, and the right-click menu.
final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!

    /// Optional second menu-bar item holding just a Next button.
    private var nextItem: NSStatusItem?
    private let popup: PopupController
    private let miniPlayer: MiniPlayerController
    private var shortcutWindow: ShortcutSettingsController?

    init(popup: PopupController, miniPlayer: MiniPlayerController) {
        self.popup = popup
        self.miniPlayer = miniPlayer
        super.init()

        // Menu-bar items sit right-to-left in creation order - the newest is furthest
        // left - so the Next button is created first to end up as [music note][next].
        refreshNextButton()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Lets macOS remember where the user Command-dragged each item to.
        statusItem.autosaveName = "ExpressYTMusicMain"

        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged), name: .playerStateChanged, object: nil)
        refreshTitle()
    }

    // MARK: - Click handling

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            showMenu()
        } else {
            popup.toggle(relativeTo: statusItem.button)
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // restore left-click behaviour
    }

    // MARK: - Next button

    private static let nextButtonConfig =
        NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

    /// Adds or removes a dedicated Next item so a skip is one click, with no menu.
    private func refreshNextButton() {
        guard Preferences.showNextButton else {
            if let item = nextItem {
                NSStatusBar.system.removeStatusItem(item)
                nextItem = nil
            }
            return
        }
        guard nextItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "ExpressYTMusicNext"
        let image = NSImage(systemSymbolName: "forward.end.fill", accessibilityDescription: "Next Track")?
            .withSymbolConfiguration(Self.nextButtonConfig)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(nextTrack)
        item.button?.toolTip = "Next Track"
        nextItem = item
    }

    // MARK: - Title

    @objc private func stateChanged() {
        refreshTitle()
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        let state = PlayerStore.shared.state

        guard Preferences.showTrackTitle, state.hasTrack else {
            button.title = ""
            return
        }

        // Title only - the artist made this long and pushed the clock around.
        let text = state.title
        let limit = Preferences.titleMaxLength
        let truncated = text.count > limit
            ? String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
            : text
        button.title = " " + truncated
        button.toolTip = state.summary
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let state = PlayerStore.shared.state
        let menu = NSMenu()
        menu.autoenablesItems = false

        if state.hasTrack {
            let track = NSMenuItem(title: state.title, action: nil, keyEquivalent: "")
            track.isEnabled = false
            menu.addItem(track)
            if !state.artist.isEmpty {
                let artist = NSMenuItem(title: state.artist, action: nil, keyEquivalent: "")
                artist.isEnabled = false
                menu.addItem(artist)
            }
            menu.addItem(.separator())
        }

        add(menu, state.isPlaying ? "Pause" : "Play", #selector(togglePlayPause))
        add(menu, "Next Track", #selector(nextTrack))
        add(menu, "Previous Track", #selector(previousTrack))
        menu.addItem(.separator())

        add(menu, "Shuffle", #selector(toggleShuffle))
        add(menu, "Repeat", #selector(toggleRepeat))
        menu.addItem(.separator())

        add(menu, popup.isVisible ? "Hide Player" : "Show Player", #selector(togglePopup))
        add(menu, miniPlayer.isVisible ? "Hide Mini Player" : "Show Mini Player", #selector(toggleMiniPlayer))
        add(menu, "Keep Mini Player on Top", #selector(toggleMiniOnTop),
            checked: Preferences.miniPlayerAlwaysOnTop)
        add(menu, "Reload Player", #selector(reloadPlayer))
        add(menu, "Go to YouTube Music", #selector(goHome))
        menu.addItem(.separator())

        add(menu, "Launch at Login", #selector(toggleLaunchAtLogin), checked: Preferences.launchAtLogin)
        add(menu, "Show Track Title in Menu Bar", #selector(toggleShowTitle), checked: Preferences.showTrackTitle)
        add(menu, "Show Next Button in Menu Bar", #selector(toggleNextButton), checked: Preferences.showNextButton)
        add(menu, "Close Player When It Loses Focus", #selector(toggleHideOnFocusLoss), checked: Preferences.hideOnFocusLoss)
        add(menu, "Keyboard Shortcuts…", #selector(openShortcuts))
        menu.addItem(.separator())

        add(menu, "Sign Out of YouTube Music…", #selector(signOut))
        add(menu, "Open Diagnostics Log", #selector(openDiagnostics))
        add(menu, "About Express YT Music", #selector(showAbout))
        add(menu, "Quit Express YT Music", #selector(quit), key: "q")

        return menu
    }

    private func add(_ menu: NSMenu,
                     _ title: String,
                     _ action: Selector,
                     key: String = "",
                     checked: Bool = false) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    // MARK: - Menu actions

    @objc private func togglePlayPause() { WebPlayerController.shared.togglePlayPause() }
    @objc private func nextTrack()       { WebPlayerController.shared.nextTrack() }
    @objc private func previousTrack()   { WebPlayerController.shared.previousTrack() }
    @objc private func toggleShuffle()   { WebPlayerController.shared.toggleShuffle() }
    @objc private func toggleRepeat()    { WebPlayerController.shared.toggleRepeat() }
    @objc private func reloadPlayer()    { WebPlayerController.shared.reload() }

    /// Escape hatch if the player is ever left on a sign-in or blank page.
    @objc private func goHome() {
        WebPlayerController.shared.goHome()
        popup.show(relativeTo: statusItem.button)
    }

    @objc private func togglePopup() {
        popup.toggle(relativeTo: statusItem.button)
    }

    @objc private func toggleMiniPlayer() {
        miniPlayer.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        Preferences.launchAtLogin.toggle()
    }

    @objc private func toggleShowTitle() {
        Preferences.showTrackTitle.toggle()
        refreshTitle()
    }

    @objc private func toggleMiniOnTop() {
        miniPlayer.toggleAlwaysOnTop()
    }

    @objc private func toggleNextButton() {
        Preferences.showNextButton.toggle()
        refreshNextButton()
    }

    @objc private func toggleHideOnFocusLoss() {
        Preferences.hideOnFocusLoss.toggle()
    }

    @objc private func openShortcuts() {
        if shortcutWindow == nil {
            shortcutWindow = ShortcutSettingsController()
        }
        shortcutWindow?.show()
    }

    @objc private func signOut() {
        let alert = NSAlert()
        alert.messageText = "Sign out of YouTube Music?"
        alert.informativeText = """
        This clears the cookies and site data stored by Express YT Music. \
        Your Safari and Chrome sessions are not touched.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WebPlayerController.shared.signOut()
    }

    @objc private func openDiagnostics() {
        let url = Diagnostics.logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            Diagnostics.log("diagnostics log opened from the menu")
            // Give the write a moment to land before handing the file to Console.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "Express YT Music \(version)"
        alert.informativeText = """
        A menu-bar controller for YouTube Music.

        Your session stays in this app's own storage. No telemetry, no analytics, \
        and no access to other browsers' data. Global shortcuts use the system hot-key \
        API, so no Accessibility permission is required.

        YouTube and YouTube Music are trademarks of Google LLC. This app is not \
        affiliated with or endorsed by Google.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
