# MagicTap

A lightweight macOS menu bar app that brings **tap-to-click** to the Apple Magic Mouse — left tap acts as left click, right tap acts as right click, no physical press required.

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Why

The Magic Mouse has no built-in tap-to-click setting (unlike the trackpad). This app fills that gap by intercepting touch events from the mouse surface and injecting synthetic click events 

## How it works

- Uses the private `MultitouchSupport.framework` to receive raw touch events from the Magic Mouse
- Detects a tap as a touch that starts and ends within **180 ms** with **minimal movement**
- Determines left vs. right based on the horizontal position of the touch on the mouse surface
- Injects a synthetic `CGEvent` mouse click at the current cursor position
- Requires **Accessibility permission** to post synthetic events

## Requirements

- macOS 12 or later
- Apple Magic Mouse (1st or 2nd gen, family ID 112)
- Xcode Command Line Tools

## Build

```bash
xcode-select --install   # if not already installed
git clone https://github.com/your-username/applemousetaptoclick
cd applemousetaptoclick
chmod +x build.sh
./build.sh
```

The app is built to `build/MagicTap.app` and ad-hoc signed automatically.

## Run

```bash
open build/MagicTap.app
```

**On first launch**, macOS will ask for Accessibility permission. Grant it in:

> System Settings → Privacy & Security → Accessibility → enable MagicTap

Then relaunch the app. A hand icon will appear in the menu bar.

## Usage

| Gesture | Action |
|---|---|
| Light tap — left side of mouse | Left click |
| Light tap — right side of mouse | Right click |
| Physical press | Works as normal (unchanged) |

Click the menu bar icon to toggle tap-to-click on or off.

## Auto-start on login

> System Settings → General → Login Items → add `MagicTap.app`

## Tuning tap sensitivity

If taps feel too sensitive or not sensitive enough, edit the thresholds in `TouchHandler.swift`:

```swift
private let kTapMaxDuration: Double = 0.18   // max seconds for a tap (lower = less sensitive)
private let kTapMaxMovement: Float  = 0.15   // max surface movement (lower = less sensitive)
```

Then rebuild with `./build.sh`.

## Project structure

```
AppDelegate.swift    — menu bar icon, toggle, app lifecycle
TouchHandler.swift   — MultitouchSupport integration, tap detection, click injection
main.swift           — NSApplication entry point
build.sh             — compile, bundle, and ad-hoc sign
```

## Caveats

- Uses a **private Apple framework** (`MultitouchSupport.framework`). This is not App Store distributable and may break on future macOS versions.
- Physical clicks still work normally — this app only adds tap-to-click on top.
- If a physical press is also light enough to register as a touch, it may produce a double-click. Lowering `kTapMaxDuration` reduces this.

## License

MIT
