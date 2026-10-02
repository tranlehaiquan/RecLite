# RecLite — Roadmap & Known Issues

This document tracks bugs, missing features, and planned improvements for RecLite.

---

## 🔴 Bugs / Critical Fixes

_No known open bugs._


---

## 🟡 Missing Features

- [ ] **Screenshot keyboard shortcut** — screenshots are available from the control bar camera button, but there is no configurable global hotkey yet
- [ ] **"Save to" destinations in Options menu** — native offers Desktop, Documents, Clipboard, Mail, Messages, QuickTime Player, and Other Location directly from the bar; RecLite only has a save folder in Preferences
- [ ] **Drag-out from video completion card** — native's floating thumbnail can be dragged straight into Mail, Slack, Finder, etc. (done for screenshots, not yet for videos)
- [ ] **Quick trim** — native lets you trim the clip from the floating thumbnail before saving
- [ ] **Launch at Login** — a "Start RecLite at Login" toggle in General settings. Native macOS screen recorders are expected to offer this via `SMAppService`
- [ ] **Recording history / Recent files** — a list of past recordings accessible from the menu bar icon, allowing users to re-open, reveal in Finder, or delete previous recordings without digging through the Movies folder
- [ ] **GitHub Release with downloadable DMG** — no tagged `v1.0.0` release with a `RecLite-Installer.dmg` asset has been published yet; required for Homebrew cask submission and broad user adoption

---

## 🟢 Polish & Nice-to-Have

- [ ] **Banner image in README** — a visual preview / screenshot has been generated but not yet embedded at the top of `README.md`
- [ ] **Submit to `awesome-mac` list** — open a PR to [jaywcjlove/awesome-mac](https://github.com/jaywcjlove/awesome-mac) under *Screen Recording / Utilities* for passive organic discovery
- [ ] **Submit to `AlternativeTo`** — list RecLite as a free, open-source alternative to CleanShot X, Loom, and QuickTime Player

---

## ✅ Completed

- [x] Native MP4 / HEVC direct capture (no re-encoding)
- [x] Rebranding leftovers fixed: default filename prefix is now `RecLite Recording`; Size Comparison rows, menu bar accessibility label, and permission alert say RecLite
- [x] README install guide (clone, build, install, permissions, troubleshooting); removed hardcoded personal build path
- [x] Pause / Resume recording (shortcut, HUD button, and menu bar items; paused time is removed from the output)
- [x] Show Mouse Clicks (`highlightClicks` wired to `SCStreamConfiguration.showMouseClicks`, macOS 15+)
- [x] Microphone device picker in the Audio menu
- [x] 10-second countdown timer option
- [x] Screenshots (entire screen / window / area) via `SCScreenshotManager`, saved as PNG with a native-style floating thumbnail (click to open, drag to share, right-click to copy / reveal / delete)
- [x] Remember last selected area across launches
- [x] Floating glassmorphic control bar (Cmd+Shift+5 style)
- [x] Interactive draggable crop area selection
- [x] Window picker with live thumbnail previews
- [x] Live recording HUD with elapsed timer and file size counter
- [x] Post-recording completion card with storage saved % badge
- [x] System audio + microphone capture with real-time audio mixer
- [x] Quality presets (Ultra Compact, Balanced, High Quality, Custom Bitrate)
- [x] Global keyboard shortcuts with configurable key mappings
- [x] Settings window with 5 tabs (Video, Size Comparison, Audio, General, Shortcuts)
- [x] DMG installer packaging (`create_dmg.sh`)
- [x] App renamed to **RecLite** (`CFBundleName`, binary, bundle)
- [x] GitHub repository description and topic tags updated
