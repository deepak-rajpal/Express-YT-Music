import AppKit
import Carbon.HIToolbox

/// Window for viewing and re-recording the four global shortcuts.
///
/// Recording uses a *local* NSEvent monitor, which only sees events delivered to this
/// app while the window is focused. No Accessibility permission, no global tap.
final class ShortcutSettingsController: NSObject, NSWindowDelegate {

    private var window: NSWindow!
    private var rows: [HotKeyAction: Row] = [:]
    private var recordingAction: HotKeyAction?
    private var monitor: Any?

    private final class Row {
        let toggle = NSButton()
        let button = NSButton()
        init() {}
    }

    override init() {
        super.init()
        build()
    }

    private func build() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating

        let header = NSTextField(wrappingLabelWithString:
            "Click a shortcut to record a new one. Escape cancels; Delete clears it.")
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor

        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        for action in HotKeyAction.allCases {
            let row = Row()

            row.toggle.setButtonType(.switch)
            row.toggle.title = action.title
            row.toggle.target = self
            row.toggle.action = #selector(toggleEnabled(_:))
            row.toggle.tag = index(of: action)

            row.button.bezelStyle = .rounded
            row.button.target = self
            row.button.action = #selector(startRecording(_:))
            row.button.tag = index(of: action)
            row.button.setContentHuggingPriority(.defaultLow, for: .horizontal)

            rows[action] = row
            grid.addRow(with: [row.toggle, row.button])
        }

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAll))
        reset.bezelStyle = .rounded

        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"

        let buttons = NSStackView(views: [reset, NSView(), done])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        let stack = NSStackView(views: [header, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = content
        refresh()
    }

    private func index(of action: HotKeyAction) -> Int {
        HotKeyAction.allCases.firstIndex(of: action) ?? 0
    }

    private func action(at tag: Int) -> HotKeyAction {
        HotKeyAction.allCases[tag]
    }

    func show() {
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        for action in HotKeyAction.allCases {
            guard let row = rows[action] else { continue }
            let spec = HotKeyManager.shared.spec(for: action)
            row.toggle.state = spec.enabled ? .on : .off
            row.button.title = recordingAction == action
                ? "Press keys…"
                : HotKeyManager.describe(spec)
            row.button.isEnabled = spec.enabled
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSButton) {
        let action = self.action(at: sender.tag)
        var spec = HotKeyManager.shared.spec(for: action)
        spec.enabled = sender.state == .on
        if spec.enabled && spec.keyCode == 0 {
            spec = action.defaultSpec
        }
        HotKeyManager.shared.setSpec(spec, for: action)
        refresh()
    }

    @objc private func startRecording(_ sender: NSButton) {
        stopRecording()
        recordingAction = action(at: sender.tag)
        refresh()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording()
                self.refresh()
                return nil
            }

            if event.keyCode == UInt16(kVK_Delete) {
                HotKeyManager.shared.setSpec(.none, for: action)
                self.stopRecording()
                self.refresh()
                return nil
            }

            let mods = HotKeyManager.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else {
                NSSound.beep()   // a bare key would swallow normal typing system-wide
                return nil
            }

            HotKeyManager.shared.setSpec(
                HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: mods, enabled: true),
                for: action
            )
            self.stopRecording()
            self.refresh()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recordingAction = nil
    }

    @objc private func resetAll() {
        stopRecording()
        HotKeyManager.shared.resetAll()
        refresh()
    }

    @objc private func closeWindow() {
        window.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        refresh()
    }
}
