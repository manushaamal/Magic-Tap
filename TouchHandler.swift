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

    let downType: CGEventType   = isRight ? .rightMouseDown : .leftMouseDown
    let upType:   CGEventType   = isRight ? .rightMouseUp   : .leftMouseUp
    let button:   CGMouseButton = isRight ? .right          : .left

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

    // C function pointer types
    private typealias MTCb          = @convention(c) (OpaquePointer, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn  = @convention(c) () -> CFMutableArray?
    private typealias GetFamilyIDFn = @convention(c) (OpaquePointer, UnsafeMutablePointer<Int32>) -> Void
    private typealias CBFn          = @convention(c) (OpaquePointer, MTCb) -> Void   // register & unregister share this signature
    private typealias StartFn       = @convention(c) (OpaquePointer, Int32) -> Void
    private typealias StopFn        = @convention(c) (OpaquePointer) -> Void

    // Library and function pointers — loaded once at startup
    private var createList:   CreateListFn?
    private var getFamilyID:  GetFamilyIDFn?
    private var registerCB:   CBFn?
    private var unregisterCB: CBFn?
    private var startDevice:  StartFn?
    private var stopDevice:   StopFn?

    // Persistent device list — kept alive like Jitouch does (DO NOT let it go out of scope)
    private var deviceList: CFMutableArray?

    // MARK: - Public API

    func start() {
        loadLibrary()
        registerDevices()
    }

    // Called on NSWorkspace.didWakeNotification.
    // Mirrors Jitouch's -reload: unregister + stop all → 1 s pause → fresh list + re-register.
    func restart() {
        unregisterAndStop()
        gActiveTouches.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.registerDevices()
        }
    }

    func setEnabled(_ enabled: Bool) {
        gTapEnabled = enabled
    }

    // MARK: - Private

    // Load the private framework once; store all function pointers.
    private func loadLibrary() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let lib = dlopen(path, RTLD_NOW),
              let s1 = dlsym(lib, "MTDeviceCreateList"),
              let s2 = dlsym(lib, "MTDeviceGetFamilyID"),
              let s3 = dlsym(lib, "MTRegisterContactFrameCallback"),
              let s4 = dlsym(lib, "MTUnregisterContactFrameCallback"),
              let s5 = dlsym(lib, "MTDeviceStart"),
              let s6 = dlsym(lib, "MTDeviceStop")
        else { return }

        createList   = unsafeBitCast(s1, to: CreateListFn.self)
        getFamilyID  = unsafeBitCast(s2, to: GetFamilyIDFn.self)
        registerCB   = unsafeBitCast(s3, to: CBFn.self)
        unregisterCB = unsafeBitCast(s4, to: CBFn.self)
        startDevice  = unsafeBitCast(s5, to: StartFn.self)
        stopDevice   = unsafeBitCast(s6, to: StopFn.self)
    }

    // Unregister callback then stop every tracked device, then release the list.
    // Mirrors Jitouch reload phase 1: MTUnregisterContactFrameCallback → MTDeviceStop → CFRelease(deviceList).
    private func unregisterAndStop() {
        guard let list  = deviceList,
              let unreg = unregisterCB,
              let stop  = stopDevice else { return }

        let cb: MTCb = mtTouchCallback
        for i in 0..<CFArrayGetCount(list) {
            let dev = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: OpaquePointer.self)
            unreg(dev, cb)
            stop(dev)
        }
        deviceList = nil   // releases the CFMutableArray (Swift ARC handles CFRelease)
    }

    // Build a fresh device list and register callbacks.
    // Mirrors Jitouch reload phase 2: MTDeviceCreateList → MTRegisterContactFrameCallback → MTDeviceStart.
    private func registerDevices() {
        guard let create    = createList,
              let getFamily = getFamilyID,
              let reg       = registerCB,
              let start     = startDevice else { return }

        guard let freshList = create() else { return }
        deviceList = freshList   // retain via Swift ARC; kept alive until next unregisterAndStop()

        let cb: MTCb = mtTouchCallback
        for i in 0..<CFArrayGetCount(freshList) {
            let dev = unsafeBitCast(CFArrayGetValueAtIndex(freshList, i), to: OpaquePointer.self)
            var familyID: Int32 = 0
            getFamily(dev, &familyID)
            if familyID == 112 {   // Magic Mouse & Magic Mouse 2
                reg(dev, cb)
                start(dev, 0)
            }
        }
    }
}
