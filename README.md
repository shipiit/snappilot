<p align="center">
  <img src="docs/assets/banner.png" alt="Snappilot" width="100%">
</p>

<h1 align="center">Snappilot</h1>

<p align="center">
  <b>The free, open-source Snagit alternative for macOS.</b><br>
  Capture · Annotate · Record · OCR — native, on-device, and private.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Privacy" src="https://img.shields.io/badge/privacy-100%25%20on--device-brightgreen">
</p>

---

## ✨ Overview

Snappilot is a fast, modern screen-capture studio for macOS. Grab exactly the part of the
screen you want, annotate it like a pro, record it to a compact video, and pull text out of
anything — all on-device, with no telemetry and no accounts.

<p align="center">
  <img src="docs/assets/dashboard.png" alt="Snappilot dashboard" width="49%">
  <img src="docs/assets/editor.png" alt="Snappilot editor" width="49%">
</p>

## 🚀 Features

### Capture
- 🟦 **Region** · 🪟 **Window** · 🖥️ **Full Screen** — a crisp crosshair overlay with a
  **live magnifier loupe**, pixel dimensions, and keyboard hints.
- ⌨️ **Global shortcuts** — trigger any capture from anywhere. Fully **customizable**.
- 🫥 Snappilot **hides itself** during capture so it never lands in your shot.

### Annotate (Snagit-style editor)
- ➡️ Arrows, lines, rectangles, ellipses, callouts, freehand pen
- 🔢 **Step badges** — auto-numbered `1·2·3`, `A·B·C`, or `a·b·c`
- 🖍️ Highlighter · 🙈 **Blur / redact** · ✂️ **Crop** · ⭐ **Stamps** (emoji)
- 🎨 **Quick Styles** — 10+ one-click presets per tool (solid / dashed / dotted, dot & bar
  arrow heads, fills, colors)
- 🎚️ Tool properties: custom color, thickness, opacity, arrow **start/end/size**
- ↩️ Non-destructive layers, undo/redo, move & edit anything

### Record
- 🎥 Record a **region or the full screen** → compact **HEVC MP4**
- 🔊 System audio · 🎙️ Microphone · 📷 **Webcam overlay** · 🖱️ cursor — all optional
- ⏱️ **"Ready to Record"** panel + **3·2·1 countdown** (outside the frame)
- 🟨 A live **recording frame** shows exactly what's being captured
- ▶️ Recordings open in Snappilot's **own player** — never QuickTime

### OCR & Library
- 🔤 **Grab Text** — extract selectable text from any region via Apple Vision
- 🗂️ Every capture **auto-saves** to a local library, **searchable by the text inside it**
- ⭐ Favorites · 📋 copy · 🗑️ delete · 🔎 instant search

### Design
- 🌗 Full **light & dark** theme support (follows your system)
- 🧭 Clean sidebar dashboard · menu-bar quick access · full app menu

## ⌨️ Default shortcuts

| Shortcut | Action |          | Shortcut | Action |
|----------|--------|----------|----------|--------|
| `⌃⇧1`    | Region |          | `⌃⇧5`    | Record Region |
| `⌃⇧2`    | Window |          | `⌃⇧6`    | Record Screen |
| `⌃⇧3`    | Full Screen |     | `⌃⇧.`    | Stop Recording |
| `⌃⇧4`    | Grab Text (OCR) | |          | *(all customizable in Settings)* |

## 🛠️ Build & run

Requires **macOS 14+**, **Xcode 16+**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate        # creates Snappilot.xcodeproj
open Snappilot.xcodeproj  # then Run (⌘R)

swift run snapverify      # framework-free logic tests for SnapCore
```

On first capture/record, macOS asks for **Screen Recording** (and, if used, Microphone /
Camera) permission — enable Snappilot in **System Settings → Privacy & Security**.

## 🏗️ Architecture

- **`SnapCore`** — a UI-free, unit-tested Swift package: capture/crop geometry, the Vision
  OCR wrapper, image ops, sensitive-data detection, the annotation layer model, and the
  local-library index.
- **`App`** — SwiftUI + AppKit: capture overlay, ScreenCaptureKit controller, the
  annotation editor, recorder, video player, menu-bar UI, hotkeys, and settings.

Logic lives in `SnapCore` so it can be tested without a UI; everything visual consumes it
through clean value types.

## 🗺️ Roadmap

- Video **trim** + **annotation** · **GIF export**
- **Scrolling capture** (stitch long pages)
- Floating recording **control bar** + cursor click-highlight
- Templates / step-guides · quick share

## 🔒 Privacy

100% on-device. No telemetry, no third-party services, no account. OCR runs locally via
Apple Vision; recordings and captures never leave your Mac.

## 📄 License

MIT.
