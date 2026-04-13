import Cocoa
import Darwin

// MARK: - MultitouchSupport C types (matching the private framework's layout)

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var pos: MTPoint
    var vel: MTPoint
}

// Matches the C struct layout. 'int frame' (4 bytes) is followed by 4 bytes of
// natural padding before 'double timestamp' (8-byte aligned) on ARM64.
struct MTFinger {
    var frame: Int32
    var _pad: Int32         // padding: aligns timestamp to 8-byte boundary
    var timestamp: Double
    var identifier: Int32
    var state: UInt32
    var fingerId: Int32
    var handId: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var zero2a: Int32
    var zero2b: Int32
    var zDensity: Float
}

private let MTTouchStateMakeTouch: UInt32  = 3
private let MTTouchStateBreakTouch: UInt32 = 5

// MARK: - Global state (needed because the C callback cannot capture context)

var gTapEnabled = true

private struct TouchStart {
    var time: Double
    var x: Float
    var y: Float
}
private var gActiveTouches = [Int32: TouchStart]()

private let kTapMaxDuration: Double = 0.18   // seconds
private let kTapMaxMovement: Float  = 0.15   // normalised surface units

// MARK: - C callback (must be a global function, not a closure)

func mtTouchCallback(
    device: OpaquePointer,
    rawFingers: UnsafeRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard gTapEnabled, let rawFingers = rawFingers else { return 0 }
    let fingers = rawFingers.assumingMemoryBound(to: MTFinger.self)

    for i in 0..<Int(count) {
        let f = fingers[i]

        switch f.state {
        case MTTouchStateMakeTouch:
            gActiveTouches[f.fingerId] = TouchStart(
                time: f.timestamp,
                x: f.normalized.pos.x,
                y: f.normalized.pos.y
            )

        case MTTouchStateBreakTouch:
            guard let start = gActiveTouches.removeValue(forKey: f.fingerId) else { continue }

            let duration = f.timestamp - start.time
            let dx = f.normalized.pos.x - start.x
            let dy = f.normalized.pos.y - start.y
            let dist = sqrtf(dx * dx + dy * dy)

            guard duration < kTapMaxDuration && dist < kTapMaxMovement else { continue }

            let isRight = start.x >= 0.5
            postSyntheticClick(isRight: isRight)

        default:
            break
        }
    }
    return 0
}

// MARK: - Synthetic click injection

private func postSyntheticClick(isRight: Bool) {
    let mousePos = NSEvent.mouseLocation
    let screenH  = NSScreen.main?.frame.height ?? 0
    let pt = CGPoint(x: mousePos.x, y: screenH - mousePos.y)

    let downType: CGEventType  = isRight ? .rightMouseDown  : .leftMouseDown
    let upType:   CGEventType  = isRight ? .rightMouseUp    : .leftMouseUp
    let button:   CGMouseButton = isRight ? .right           : .left

    guard
        let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: pt, mouseButton: button),
        let up   = CGEvent(mouseEventSource: nil, mouseType: upType,   mouseCursorPosition: pt, mouseButton: button)
    else { return }

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

// MARK: - TouchHandler

class TouchHandler {
    static let shared = TouchHandler()

    private typealias CreateListFn      = @convention(c) () -> CFMutableArray?
    private typealias GetFamilyIDFn     = @convention(c) (OpaquePointer, UnsafeMutablePointer<Int32>) -> Void
    private typealias RegisterCBFn      = @convention(c) (OpaquePointer, @convention(c) (OpaquePointer, UnsafeRawPointer?, Int32, Double, Int32) -> Int32) -> Void
    private typealias StartFn           = @convention(c) (OpaquePointer, Int32) -> Void

    func start() {
        guard isAccessibilityGranted() else {
            DispatchQueue.main.async { self.promptAccessibility() }
            return
        }
        loadAndRegister()
    }

    func setEnabled(_ enabled: Bool) {
        gTapEnabled = enabled
    }

    // MARK: Private

    private func isAccessibilityGranted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    private func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MagicTap needs Accessibility access to inject tap events.\n\nGo to System Settings → Privacy & Security → Accessibility and enable MagicTap, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApp.terminate(nil)
    }

    private func loadAndRegister() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let lib = dlopen(path, RTLD_NOW) else { return }

        guard
            let s1 = dlsym(lib, "MTDeviceCreateList"),
            let s2 = dlsym(lib, "MTDeviceGetFamilyID"),
            let s3 = dlsym(lib, "MTRegisterContactFrameCallback"),
            let s4 = dlsym(lib, "MTDeviceStart")
        else { return }

        let createList  = unsafeBitCast(s1, to: CreateListFn.self)
        let getFamilyID = unsafeBitCast(s2, to: GetFamilyIDFn.self)
        let registerCB  = unsafeBitCast(s3, to: RegisterCBFn.self)
        let startDevice = unsafeBitCast(s4, to: StartFn.self)

        guard let devices = createList() else { return }

        for i in 0..<CFArrayGetCount(devices) {
            let dev = unsafeBitCast(CFArrayGetValueAtIndex(devices, i), to: OpaquePointer.self)
            var familyID: Int32 = 0
            getFamilyID(dev, &familyID)
            if familyID == 112 { // Magic Mouse & Magic Mouse 2
                let cb: @convention(c) (OpaquePointer, UnsafeRawPointer?, Int32, Double, Int32) -> Int32 = mtTouchCallback
                registerCB(dev, cb)
                startDevice(dev, 0)
            }
        }
    }
}
