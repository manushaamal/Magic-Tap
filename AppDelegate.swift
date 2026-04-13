import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var tapEnabled: Bool = true
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        buildMenu()
        TouchHandler.shared.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc func systemDidWake() {
        guard tapEnabled else { return }
        TouchHandler.shared.restart()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Tap to Click", action: #selector(toggleTap), keyEquivalent: "t"))

        launchAtLoginItem = NSMenuItem(title: "Launch at Login",
                                       action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MagicTap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleLaunchAtLogin() {
        let enable = !LaunchAtLoginManager.shared.isEnabled
        LaunchAtLoginManager.shared.setEnabled(enable)
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
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
