import AppKit

// Menu-bar only: no Dock icon, no main menu window. Matches LSUIElement in Info.plist.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
