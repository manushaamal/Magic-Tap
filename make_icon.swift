#!/usr/bin/env swift
// make_icon.swift — Generates AppIcon.icns for MagicTap
// Run: swift make_icon.swift

import Cocoa

_ = NSApplication.shared   // needed for SF Symbol rendering

// ── Output paths ────────────────────────────────────────────────────────────

let iconsetPath = "/tmp/MagicTap.iconset"
let icnsOutPath = "./AppIcon.icns"

try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath,
                                         withIntermediateDirectories: true)

// ── Rendering ───────────────────────────────────────────────────────────────

func makeIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)

    guard let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    // Rounded-rect clip (macOS icon shape)
    let corner = s * 0.225
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                 xRadius: corner, yRadius: corner).addClip()

    // Gradient background: deep indigo → vivid purple
    NSGradient(colors: [
        NSColor(red: 0.14, green: 0.06, blue: 0.62, alpha: 1),
        NSColor(red: 0.50, green: 0.05, blue: 0.56, alpha: 1),
    ], atLocations: [0, 1], colorSpace: .sRGB)?
        .draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -55)

    // hand.tap.fill symbol, white, centred
    let pointSize = s * 0.55
    if let sym = NSImage(systemSymbolName: "hand.tap.fill",
                         accessibilityDescription: nil) {
        let cfg: NSImage.SymbolConfiguration = .init(pointSize: pointSize, weight: .medium)
        let configured: NSImage = sym.withSymbolConfiguration(cfg) ?? sym

        // Tint white: fill with white then mask to symbol shape via destinationIn
        let tinted = NSImage(size: configured.size)
        tinted.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: configured.size).fill()
        configured.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()

        let sw = tinted.size.width, sh = tinted.size.height
        tinted.draw(in: NSRect(x: (s - sw) / 2, y: (s - sh) / 2,
                               width: sw, height: sh))
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImg = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cgImg).representation(using: .png, properties: [:])
}

// ── Required iconset filenames & pixel sizes ─────────────────────────────────

let icons: [(pixels: Int, filename: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixels, filename) in icons {
    if let data = makeIcon(pixelSize: pixels) {
        try? data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
        print("  ✓ \(filename)  (\(pixels)px)")
    } else {
        fputs("  ✗ Failed: \(filename)\n", stderr)
    }
}

// ── Compile iconset → .icns ──────────────────────────────────────────────────

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments  = ["-c", "icns", iconsetPath, "-o", icnsOutPath]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("\n✅  AppIcon.icns written to \(icnsOutPath)")
} else {
    fputs("❌  iconutil failed (exit \(task.terminationStatus))\n", stderr)
    exit(1)
}
