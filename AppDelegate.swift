import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var tapEnabled: Bool = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        buildMenu()
        TouchHandler.shared.start()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Tap to Click", action: #selector(toggleTap), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MagicTap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleTap() {
        tapEnabled.toggle()
        TouchHandler.shared.setEnabled(tapEnabled)
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: tapEnabled ? "hand.tap.fill" : "hand.tap",
                               accessibilityDescription: "MagicTap")
        button.toolTip = tapEnabled ? "Tap to Click: ON" : "Tap to Click: OFF"
    }
}
