import AppKit
import Carbon.HIToolbox

/// A global shortcut definition. Modifiers are Carbon flags (cmdKey, optionKey, ...).
struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var enabled: Bool

    static let none = HotKeySpec(keyCode: 0, modifiers: 0, enabled: false)
}

enum HotKeyAction: String, CaseIterable {
    case toggleWindow
    case togglePlayPause
    case nextTrack
    case previousTrack

    var title: String {
        switch self {
        case .toggleWindow:    return "Show / Hide Player"
        case .togglePlayPause: return "Play / Pause"
        case .nextTrack:       return "Next Track"
        case .previousTrack:   return "Previous Track"
        }
    }

    /// Control-Option-Command plus a letter or arrow: unlikely to collide with anything.
    var defaultSpec: HotKeySpec {
        let mods = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .toggleWindow:    return HotKeySpec(keyCode: UInt32(kVK_ANSI_M), modifiers: mods, enabled: true)
        case .togglePlayPause: return HotKeySpec(keyCode: UInt32(kVK_ANSI_P), modifiers: mods, enabled: true)
        case .nextTrack:       return HotKeySpec(keyCode: UInt32(kVK_RightArrow), modifiers: mods, enabled: true)
        case .previousTrack:   return HotKeySpec(keyCode: UInt32(kVK_LeftArrow), modifiers: mods, enabled: true)
        }
    }
}

/// Registers global shortcuts with Carbon's `RegisterEventHotKey`.
///
/// This is a deliberate choice over `NSEvent.addGlobalMonitorForEvents`: it needs no
/// Accessibility permission, and the process only ever receives the exact key
/// combinations it registered - it cannot observe any other keystroke.
final class HotKeyManager {

    static let shared = HotKeyManager()

    var onTrigger: ((HotKeyAction) -> Void)?

    private var handler: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, action: HotKeyAction)] = [:]
    private var nextID: UInt32 = 1

    private init() {}

    // MARK: - Persistence

    func spec(for action: HotKeyAction) -> HotKeySpec {
        let d = UserDefaults.standard
        let base = "hotkey.\(action.rawValue)"
        guard d.object(forKey: "\(base).keyCode") != nil else { return action.defaultSpec }
        return HotKeySpec(
            keyCode: UInt32(d.integer(forKey: "\(base).keyCode")),
            modifiers: UInt32(d.integer(forKey: "\(base).modifiers")),
            enabled: d.bool(forKey: "\(base).enabled")
        )
    }

    func setSpec(_ spec: HotKeySpec, for action: HotKeyAction) {
        let d = UserDefaults.standard
        let base = "hotkey.\(action.rawValue)"
        d.set(Int(spec.keyCode), forKey: "\(base).keyCode")
        d.set(Int(spec.modifiers), forKey: "\(base).modifiers")
        d.set(spec.enabled, forKey: "\(base).enabled")
        reload()
    }

    func resetAll() {
        let d = UserDefaults.standard
        for action in HotKeyAction.allCases {
            let base = "hotkey.\(action.rawValue)"
            d.removeObject(forKey: "\(base).keyCode")
            d.removeObject(forKey: "\(base).modifiers")
            d.removeObject(forKey: "\(base).enabled")
        }
        reload()
    }

    // MARK: - Registration

    func start() {
        installHandlerIfNeeded()
        reload()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),
                            eymHotKeyCallback,
                            1,
                            &type,
                            nil,
                            &handler)
    }

    func reload() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered.removeAll()

        for action in HotKeyAction.allCases {
            let spec = self.spec(for: action)
            guard spec.enabled, spec.keyCode != 0, spec.modifiers != 0 else { continue }

            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x45594D31), id: id) // 'EYM1'
            let status = RegisterEventHotKey(spec.keyCode,
                                             spec.modifiers,
                                             hotKeyID,
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                registered[id] = (ref, action)
            } else {
                Diagnostics.log("could not register hot key for \(action.rawValue) (status \(status))")
            }
        }
    }

    fileprivate func handle(id: UInt32) {
        guard let entry = registered[id] else { return }
        onTrigger?(entry.action)
    }

    // MARK: - Display

    /// Renders a spec the way macOS menus do, e.g. "⌃⌥⌘M".
    static func describe(_ spec: HotKeySpec) -> String {
        guard spec.keyCode != 0 || spec.modifiers != 0 else { return "None" }
        var out = ""
        if spec.modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if spec.modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if spec.modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if spec.modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += keyName(spec.keyCode)
        return out
    }

    static func keyName(_ code: UInt32) -> String {
        let named: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Grave: "`",
        ]
        return named[Int(code)] ?? "Key \(code)"
    }

    /// Translates AppKit modifier flags (from a recorded NSEvent) into Carbon flags.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }
}

/// C callback for Carbon's event handler.
private func eymHotKeyCallback(_ nextHandler: EventHandlerCallRef?,
                               _ event: EventRef?,
                               _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    DispatchQueue.main.async {
        HotKeyManager.shared.handle(id: hotKeyID.id)
    }
    return noErr
}
