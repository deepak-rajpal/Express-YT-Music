import AppKit
import WebKit

/// Owns the WKWebView that runs music.youtube.com, injects the page bridge, and turns
/// bridge messages into `PlayerStore` updates.
///
/// Two deliberate choices worth stating up front:
///  * The user agent is *truthful* - this really is WebKit, so we append the Safari
///    version token via `applicationNameForUserAgent` and keep the real engine version.
///    Nothing pretends to be Chrome, and navigator.webdriver / plugins / userAgentData
///    are left exactly as WebKit reports them.
///  * Signing in is a normal Google sign-in inside this app. Cookies live in this app's
///    own persistent WKWebsiteDataStore. No other browser's profile is ever read.
final class WebPlayerController: NSObject {

    static let shared = WebPlayerController()

    private(set) var webView: WKWebView!

    private let homeURL = URL(string: "https://music.youtube.com/")!
    private let bridgeName = "eymBridge"

    /// Child windows opened by `window.open()` - Google's account and channel pickers
    /// use these. Keyed by the child web view so `webViewDidClose` can find them.
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]

    private override init() {
        super.init()
        build()
    }

    private func build() {
        let config = WKWebViewConfiguration()

        // Persistent (default) store: the sign-in survives relaunch. `signOut()` clears it.
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false

        let controller = WKUserContentController()
        controller.add(self, name: bridgeName)
        if let source = Self.loadBridgeScript() {
            controller.addUserScript(
                WKUserScript(source: source,
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: true)
            )
        }
        config.userContentController = controller

        // Truthful: WKWebView *is* Safari's engine. This only adds the version token that
        // WKWebView omits by default, which is what makes sites treat it as a real browser.
        config.applicationNameForUserAgent = "Version/18.3 Safari/605.1.15"

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 620), configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        if #available(macOS 13.3, *) {
            webView.isInspectable = Preferences.webInspectorEnabled
        }
    }

    private static func loadBridgeScript() -> String? {
        guard let url = Bundle.main.url(forResource: "inject", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            Diagnostics.log("inject.js missing from bundle")
            return nil
        }
        return source
    }

    // MARK: - First-party hosts

    /// True when the web view is somewhere we can recover the player from - the player
    /// itself, or any point in Google's sign-in flow.
    private var isOnFirstPartyPage: Bool {
        guard let url = webView.url else { return false }
        if url.absoluteString == "about:blank" { return false }
        return FirstPartyHosts.matches(url.host)
    }

    // MARK: - Lifecycle

    /// Loads the player if the web view is empty, blank, or has been left stranded on
    /// some unrelated page. Called every time the window is shown, so a broken state
    /// always recovers on the next click of the menu-bar icon.
    func loadHomeIfNeeded() {
        guard !isOnFirstPartyPage else { return }
        Diagnostics.log("recovering blank/stranded web view (was \(webView.url?.absoluteString ?? "nil"))")
        goHome()
    }

    func reload() {
        if isOnFirstPartyPage {
            webView.reloadFromOrigin()
        } else {
            goHome()
        }
    }

    func goHome() {
        webView.load(URLRequest(url: homeURL))
    }

    /// Clears the app's own cookies and site data, i.e. signs out of YouTube Music.
    /// Only touches this app's data store - nothing outside the WebKit storage it owns.
    func signOut(completion: (() -> Void)? = nil) {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Diagnostics.log("signed out, site data cleared")
            PlayerStore.shared.clear()
            self?.goHome()
            completion?()
        }
    }

    // MARK: - Commands

    private func run(_ js: String) {
        webView.evaluateJavaScript(js) { _, error in
            if let error = error as NSError?,
               error.domain != WKErrorDomain || error.code != WKError.javaScriptResultTypeIsUnsupported.rawValue {
                Diagnostics.log("JS error for `\(js)`: \(error.localizedDescription)")
            }
        }
    }

    func togglePlayPause() { run("window.__eym && window.__eym.playPause()") }
    func play()            { run("window.__eym && window.__eym.play()") }
    func pause()           { run("window.__eym && window.__eym.pause()") }
    func nextTrack()       { run("window.__eym && window.__eym.next()") }
    func previousTrack()   { run("window.__eym && window.__eym.previous()") }
    func toggleShuffle()   { run("window.__eym && window.__eym.toggleShuffle()") }
    func toggleRepeat()    { run("window.__eym && window.__eym.toggleRepeat()") }
    func refreshState()    { run("window.__eym && window.__eym.refresh()") }

    func seek(to seconds: Double) {
        run("window.__eym && window.__eym.seek(\(seconds))")
    }

    func setVolume(_ level: Double) {
        run("window.__eym && window.__eym.setVolume(\(level))")
    }
}

// MARK: - Bridge messages

extension WebPlayerController: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard message.name == bridgeName,
              let body = message.body as? [String: Any] else { return }

        // The bridge script also runs on Google's sign-in pages and inside any popup
        // window. Only the player itself may report state, otherwise a login page with
        // no <video> would wipe the current track.
        let host = message.frameInfo.securityOrigin.host
        guard message.frameInfo.isMainFrame, host == "music.youtube.com" else { return }

        switch body["type"] as? String {
        case "state":
            if let state = PlayerState(message: body) {
                PlayerStore.shared.update(state)
            }
        case "ready":
            Diagnostics.log("page bridge ready on \(host)")
        default:
            break
        }
    }
}

// MARK: - Navigation policy

extension WebPlayerController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = action.request.url else {
            decisionHandler(.allow)
            return
        }

        // Only ever divert a deliberate link click in the main frame. Redirects, form
        // submissions and script-driven navigation stay in the app no matter where they
        // point - Google's sign-in and channel-picker flows bounce through a lot of
        // hosts, and yanking any one of them out to the default browser breaks the flow.
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        let isUserClick = action.navigationType == .linkActivated
        let scheme = url.scheme?.lowercased() ?? ""
        let isWebScheme = scheme == "http" || scheme == "https"

        guard isMainFrame, isUserClick, isWebScheme, !FirstPartyHosts.matches(url.host) else {
            decisionHandler(.allow)
            return
        }

        // A user clicked through to something outside Google: hand it to the real browser
        // rather than stranding the player on a page it cannot play from.
        Diagnostics.log("opening third-party link externally: \(url.host ?? url.absoluteString)")
        decisionHandler(.cancel)
        NSWorkspace.shared.open(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            refreshState()
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        Diagnostics.log("navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        // -999 is "cancelled", which is normal whenever we divert a link.
        guard nsError.code != NSURLErrorCancelled else { return }
        Diagnostics.log("provisional navigation failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Diagnostics.log("web content process died, reloading")
        reload()
    }
}

// MARK: - UI delegate

extension WebPlayerController: WKUIDelegate {

    /// `window.open()` gets a real child window.
    ///
    /// Google's account and channel pickers open this way, often starting at about:blank
    /// and navigating themselves afterwards. Loading the request into the main web view
    /// instead would replace the player with a blank page.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {

        // Reuse the configuration WebKit handed us: it shares this app's data store, so
        // cookies the popup sets are visible to the player when it closes.
        let width = windowFeatures.width?.doubleValue ?? 520
        let height = windowFeatures.height?.doubleValue ?? 640
        let frame = NSRect(x: 0, y: 0,
                           width: max(420, min(width, 900)),
                           height: max(480, min(height, 900)))

        let child = WKWebView(frame: frame, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        child.allowsBackForwardNavigationGestures = true

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "YouTube Music"
        window.contentView = child
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        popupWindows[ObjectIdentifier(child)] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Diagnostics.log("opened popup window for \(action.request.url?.absoluteString ?? "about:blank")")
        return child
    }

    /// The page called `window.close()` - typically the last step of a Google picker.
    func webViewDidClose(_ webView: WKWebView) {
        guard let window = popupWindows.removeValue(forKey: ObjectIdentifier(webView)) else { return }
        Diagnostics.log("popup window closed by the page")
        window.orderOut(nil)
        window.contentView = nil

        // The picker usually redirects the opener itself, but not always - make sure the
        // player is showing something playable again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !self.isOnFirstPartyPage { self.goHome() }
            self.refreshState()
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "YouTube Music"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "YouTube Music"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
