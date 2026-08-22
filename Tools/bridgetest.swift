// Exercises Resources/inject.js against Tests/fixture.html in a real WKWebView,
// checking the state it reports over the native bridge and the control functions
// it exposes. No network access.
//
//   swiftc ... -o build/bridgetest Tools/bridgetest.swift && ./build/bridgetest
import AppKit
import WebKit

var failures = 0

func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)\(detail.isEmpty ? "" : " -> \(detail)")")
    }
}

final class BridgeTest: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var messages: [[String: Any]] = []

    init(script: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: script,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        config.userContentController = controller
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                            configuration: config)
        super.init()
        controller.add(self, name: "eymBridge")
        webView.navigationDelegate = self
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { messages.append(body) }
    }

    var latestState: [String: Any]? {
        messages.last(where: { $0["type"] as? String == "state" })
    }

    func js(_ source: String, _ done: @escaping (Any?) -> Void) {
        webView.evaluateJavaScript(source) { value, error in
            if let error { print("  (js error: \(error.localizedDescription))") }
            done(value)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Let the injected poller run at least one cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.runAssertions() }
    }

    func runAssertions() {
        print("\nbridge handshake")
        check("posts a ready message", messages.contains { $0["type"] as? String == "ready" })
        check("posts at least one state message", latestState != nil)

        print("\nmetadata (mediaSession preferred over DOM scraping)")
        let s = latestState ?? [:]
        check("title from mediaSession", s["title"] as? String == "Session Title",
              "got \(s["title"] ?? "nil")")
        check("artist from mediaSession", s["artist"] as? String == "Session Artist",
              "got \(s["artist"] ?? "nil")")
        check("album from mediaSession", s["album"] as? String == "Session Album",
              "got \(s["album"] ?? "nil")")
        check("picks the largest artwork",
              (s["artwork"] as? String)?.contains("large.jpg") == true,
              "got \(s["artwork"] ?? "nil")")

        print("\nplayback state")
        check("duration read from <video>", (s["duration"] as? Double) == 210,
              "got \(s["duration"] ?? "nil")")
        check("elapsed read from <video>", (s["elapsed"] as? Double) == 12,
              "got \(s["elapsed"] ?? "nil")")
        check("starts paused", (s["isPlaying"] as? Bool) == false)
        check("detects the player element", (s["hasPlayer"] as? Bool) == true)

        print("\ncontrols")
        js("window.__eym.playPause(); 1") { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                check("playPause() starts playback",
                      (self.latestState?["isPlaying"] as? Bool) == true)

                self.js("window.__eym.seek(99); document.querySelector('video').currentTime") { v in
                    check("seek() moves the playhead", (v as? Double) == 99, "got \(v ?? "nil")")

                    self.js("window.__eym.next(); window.__eym.previous(); JSON.stringify(window.__clicks)") { clicks in
                        let list = clicks as? String ?? ""
                        check("next() uses the player API", list.contains("api:next"), list)
                        check("previous() uses the player API", list.contains("api:prev"), list)

                        self.js("""
                            window.__eym.toggleShuffle();
                            window.__eym.toggleRepeat();
                            JSON.stringify(window.__clicks)
                        """) { clicks2 in
                            let list2 = clicks2 as? String ?? ""
                            check("toggleShuffle() clicks the shuffle button",
                                  list2.contains("expand-shuffle"), list2)
                            check("toggleRepeat() clicks the repeat button",
                                  list2.contains("expand-repeat"), list2)

                            self.js("window.__eymInjected && (function(){ return typeof window.__eym; })()") { t in
                                check("guards against double injection", (t as? String) == "object")
                                self.checkDOMFallback()
                            }
                        }
                    }
                }
            }
        }
    }

    /// When mediaSession is unavailable (or Google stops populating it), inject.js
    /// must fall back to scraping the player bar.
    func checkDOMFallback() {
        print("\nDOM fallback (mediaSession removed)")
        js("navigator.mediaSession.metadata = null; window.__eym.refresh(); 1") { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let s = self.latestState ?? [:]
                check("falls back to the player-bar title",
                      s["title"] as? String == "DOM Fallback Title", "got \(s["title"] ?? "nil")")
                check("splits artist out of the subtitle",
                      s["artist"] as? String == "DOM Artist", "got \(s["artist"] ?? "nil")")
                check("splits album out of the subtitle",
                      s["album"] as? String == "DOM Album", "got \(s["album"] ?? "nil")")
                self.finish()
            }
        }
    }

    func finish() {
        print("\n\(failures == 0 ? "PASS" : "FAIL") - \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let scriptURL = root.appendingPathComponent("Resources/inject.js")
let pageURL = root.appendingPathComponent("Tests/fixture.html")

guard let script = try? String(contentsOf: scriptURL, encoding: .utf8) else {
    print("cannot read \(scriptURL.path)"); exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let test = BridgeTest(script: script)
test.webView.loadFileURL(pageURL, allowingReadAccessTo: root)

DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
    print("TIMEOUT"); exit(2)
}
app.run()
