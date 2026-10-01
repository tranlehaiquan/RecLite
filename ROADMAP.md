# RecLite — Roadmap & Known Issues

This document tracks bugs, missing features, and planned improvements for RecLite.

---

## 🔴 Bugs / Critical Fixes

- [ ] **`filenamePrefix` defaults to `"Screen Recording"`** — should default to `"RecLite Recording"` so saved files are branded correctly (`AppSettings.swift` L157)
- [ ] **Size Comparison tab still references `"ScreenRecorder"`** — comparison row titles say `"ScreenRecorder • H.264 MP4"` etc. (`SettingsView.swift` L189–210)
- [ ] **`highlightClicks` setting is saved but never used** — the option exists in `AppSettings` and presumably shown in UI, but is never passed to `ScreenCaptureEngine` during recording

---

## 🟡 Missing Features

- [ ] **Pause / Resume recording** — `shortcutPauseResume` is defined in settings and the keyboard shortcut is configurable, but `AppState` has no `pauseRecording()` / `resumeRecording()` implementation — the shortcut currently does nothing
- [ ] **Launch at Login** — a "Start RecLite at Login" toggle in General settings. Native macOS screen recorders are expected to offer this via `SMAppService`
- [ ] **Recording history / Recent files** — a list of past recordings accessible from the menu bar icon, allowing users to re-open, reveal in Finder, or delete previous recordings without digging through the Movies folder
- [ ] **GitHub Release with downloadable DMG** — no tagged `v1.0.0` release with a `RecLite-Installer.dmg` asset has been published yet; required for Homebrew cask submission and broad user adoption

---

## 🟢 Polish & Nice-to-Have

- [ ] **Banner image in README** — a visual preview / screenshot has been generated but not yet embedded at the top of `README.md`
- [ ] **Fix hardcoded build path in README** — line 105 of `README.md` contains the author's personal machine path (`/Users/quantranlehai/...`) instead of a generic `cd /path/to/RecLite`
- [ ] **Submit to `awesome-mac` list** — open a PR to [jaywcjlove/awesome-mac](https://github.com/jaywcjlove/awesome-mac) under *Screen Recording / Utilities* for passive organic discovery
- [ ] **Submit to `AlternativeTo`** — list RecLite as a free, open-source alternative to CleanShot X, Loom, and QuickTime Player

---

## ✅ Completed

- [x] Native MP4 / HEVC direct capture (no re-encoding)
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
