import AppKit
import ServiceManagement

/// Thin, typed wrapper over UserDefaults. Nothing here leaves the machine.
enum Preferences {
    private static let d = UserDefaults.standard

    private enum Key {
        static let showTrackTitle   = "showTrackTitleInMenuBar"
        static let titleMaxLength   = "menuBarTitleMaxLength"
        static let hideOnFocusLoss  = "hidePlayerOnFocusLoss"
        static let popupWidth       = "popupWidth"
        static let popupHeight      = "popupHeight"
        static let miniPlayerOpen   = "miniPlayerOpen"
        static let webInspector     = "enableWebInspector"
        static let showNextButton   = "showNextButtonInMenuBar"
        static let miniOnTop        = "miniPlayerAlwaysOnTop"
    }

    static func registerDefaults() {
        d.register(defaults: [
            Key.showTrackTitle:  false,
            Key.titleMaxLength:  28,
            Key.hideOnFocusLoss: true,
            Key.popupWidth:      480.0,
            Key.popupHeight:     620.0,
            Key.miniPlayerOpen:  false,
            Key.webInspector:    false,
            Key.showNextButton:  true,
            Key.miniOnTop:       true,
        ])
    }

    static var showNextButton: Bool {
        get { d.bool(forKey: Key.showNextButton) }
        set { d.set(newValue, forKey: Key.showNextButton) }
    }

    static var showTrackTitle: Bool {
        get { d.bool(forKey: Key.showTrackTitle) }
        set { d.set(newValue, forKey: Key.showTrackTitle) }
    }

    static var titleMaxLength: Int {
        get { max(8, d.integer(forKey: Key.titleMaxLength)) }
        set { d.set(newValue, forKey: Key.titleMaxLength) }
    }

    static var hideOnFocusLoss: Bool {
        get { d.bool(forKey: Key.hideOnFocusLoss) }
        set { d.set(newValue, forKey: Key.hideOnFocusLoss) }
    }

    static var popupSize: NSSize {
        get { NSSize(width: d.double(forKey: Key.popupWidth),
                     height: d.double(forKey: Key.popupHeight)) }
        set {
            d.set(newValue.width, forKey: Key.popupWidth)
            d.set(newValue.height, forKey: Key.popupHeight)
        }
    }

    /// Whether the mini player floats above other apps' windows.
    static var miniPlayerAlwaysOnTop: Bool {
        get { d.bool(forKey: Key.miniOnTop) }
        set { d.set(newValue, forKey: Key.miniOnTop) }
    }

    static var miniPlayerOpen: Bool {
        get { d.bool(forKey: Key.miniPlayerOpen) }
        set { d.set(newValue, forKey: Key.miniPlayerOpen) }
    }

    static var webInspectorEnabled: Bool {
        get { d.bool(forKey: Key.webInspector) }
        set { d.set(newValue, forKey: Key.webInspector) }
    }

    // MARK: - Launch at login

    /// Uses SMAppService (macOS 13+). No login items are written by hand, no helper
    /// binary is installed, and the user can always override this in System Settings.
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                Diagnostics.log("launch-at-login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}
