import Foundation
import ServiceManagement

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    var isEnabled: Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return legacyIsEnabled
    }

    func setEnabled(_ on: Bool) {
        if #available(macOS 13, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else  { try SMAppService.mainApp.unregister() }
            } catch {
                // User may need to approve in System Settings — fail silently
            }
        } else {
            on ? legacyEnable() : legacyDisable()
        }
    }

    // MARK: - macOS 12 fallback via LaunchAgent plist

    private let label = "com.local.magictap"

    private var plistURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents/\(label).plist")
    }

    private var legacyIsEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private func legacyEnable() {
        guard let exec = Bundle.main.executablePath else { return }
        let plist: NSDictionary = [
            "Label": label,
            "ProgramArguments": [exec],
            "RunAtLoad": true,
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        plist.write(toFile: plistURL.path, atomically: true)

        let t = Process()
        t.launchPath = "/bin/launchctl"
        t.arguments  = ["load", plistURL.path]
        try? t.run(); t.waitUntilExit()
    }

    private func legacyDisable() {
        let t = Process()
        t.launchPath = "/bin/launchctl"
        t.arguments  = ["unload", plistURL.path]
        try? t.run(); t.waitUntilExit()
        try? FileManager.default.removeItem(at: plistURL)
    }
}
