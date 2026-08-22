// Diagnostic: loads Google's YouTube sign-in page in a WKWebView configured exactly
// like the app's, and prints the effective user agent plus the page's visible text.
// Purpose: confirm Google serves a real sign-in form rather than the
// "This browser or app may not be secure" interstitial. No credentials involved.
import AppKit
import WebKit

final class Probe: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "Version/18.3 Safari/605.1.15"
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800),
                            configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func run(_ url: String) {
        webView.load(URLRequest(url: URL(string: url)!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("navigator.userAgent") { ua, _ in
            print("UA: \(ua as? String ?? "?")")
            webView.evaluateJavaScript(
                "document.title + '\\n----\\n' + document.body.innerText.slice(0, 700)"
            ) { text, _ in
                print("URL: \(webView.url?.absoluteString ?? "?")")
                print("---- PAGE ----")
                print(text as? String ?? "(no text)")
                exit(0)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("FAILED: \(error.localizedDescription)")
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let probe = Probe()
let target = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "https://accounts.google.com/ServiceLogin?service=youtube"
probe.run(target)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    print("TIMEOUT")
    exit(2)
}
app.run()
