import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var popup: PopupController!
    private var miniPlayer: MiniPlayerController!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        // Build the web view up front so playback state is available before the
        // window is ever opened, and so media keys work straight away.
        WebPlayerController.shared.loadHomeIfNeeded()

        popup = PopupController()
        miniPlayer = MiniPlayerController()
        statusBar = StatusBarController(popup: popup, miniPlayer: miniPlayer)

        NowPlayingBridge.shared.start()

        HotKeyManager.shared.onTrigger = { [weak self] action in
            self?.perform(action)
        }
        HotKeyManager.shared.start()

        if Preferences.miniPlayerOpen {
            miniPlayer.show()
        }

        // `--show-player` opens the window straight away. Handy for testing, and for
        // users who want a launch agent to bring the player up.
        if CommandLine.arguments.contains("--show-player") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.popup.show(relativeTo: nil)
            }
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .toggleWindow:
            popup.toggle(relativeTo: nil)
        case .togglePlayPause:
            WebPlayerController.shared.togglePlayPause()
        case .nextTrack:
            WebPlayerController.shared.nextTrack()
        case .previousTrack:
            WebPlayerController.shared.previousTrack()
        }
    }

    /// Re-launching the app (double-clicking it in Finder, or `open -a`) brings the
    /// player up rather than silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        Diagnostics.log("reopen requested")
        popup.show(relativeTo: nil)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // Menu-bar app: closing every window must not quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
