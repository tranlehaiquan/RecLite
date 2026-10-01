# RecLite (for macOS)

A native, ultra-high-performance macOS screen recording application built with **Swift**, **ScreenCaptureKit**, and **AVFoundation**.

Designed to replicate the seamless user experience of macOS's built-in screen recording (`Command + Shift + 5`) while solving its biggest limitation: **giant, heavyweight uncompressed `.mov` files**.

---

## 🚀 Why RecLite?

| Feature | macOS Built-in Screen Recording | **RecLite** |
| :--- | :--- | :--- |
| **Output Container** | Fixed `.mov` only | **MP4 (`.mp4`) & QuickTime (`.mov`)** |
| **Video Codec** | Uncompressed / High-bitrate Apple ProRes/H.264 | **HEVC (H.265), H.264 (AVC), ProRes 422** |
| **File Weight (5 min 1080p)** | **~350 MB – 1.2 GB** 🛑 | **~15 MB – 45 MB** ⚡ *(Up to 95% smaller!)* |
| **Web Compatibility** | Needs re-encoding for web/Discord/Slack | **Instant sharing (Universal MP4)** |
| **Performance** | Native | **Native zero-copy ScreenCaptureKit + Apple Silicon Hardware Encoders** |
| **Controls** | Floating pill bar | **Floating glassmorphic pill bar + Menu Bar status item** |
| **Capture Modes** | Entire Screen, Window, Cropped Area | **Entire Screen, Window, Draggable Cropped Area** |
| **Audio** | Mic or None | **Microphone + System Audio (SCK zero-latency) with live VU meters** |

---

## 🌟 Key Features

1. **Custom Video Container & Codec Selection**:
   - **MP4 (`.mp4`)**: Universally playable in any browser, Android, Windows, Slack, Discord, and messaging apps without re-encoding.
   - **HEVC / H.265**: Uses Apple Silicon hardware encoders for up to **50% smaller file size** compared to H.264 at identical visual clarity.
   - **H.264 / AVC**: Universal legacy compatibility across all players.
   - **Apple ProRes 422**: For professional lossless video editing workflows.

2. **Quality & Compression Presets**:
   - **Ultra Compact**: Tuned for Discord, Slack, and email uploads (~3 Mbps for 1080p60, files under 15 MB).
   - **Balanced (Default)**: Sweet spot between razor-sharp Retina text and small file footprint (~7 Mbps for 1080p60).
   - **High Quality**: Near-source quality for crisp gradients and design demos (~16 Mbps for 1080p60).
   - **Custom Bitrate**: Configure exact Mbps from 1 to 50 Mbps.

3. **Floating Control Bar (`Cmd+Shift+5` experience)**:
   - Full screen, specific window, and interactive cropped area selection.
   - Quick format badge (e.g. `MP4 • HEVC ~18 MB/min`).
   - Options menu for fast switching of codecs, framerates (60/30/24 fps), countdown timer, and audio sources.

4. **Interactive Area Selection Overlay**:
   - Dimmed backdrop with crystal-clear crop cutout.
   - Draggable & resizable with live dimension indicator (`1920 × 1080 (16:9)`).
   - Aspect ratio preset buttons (1080p, 720p, 1:1 square).

5. **Live Recording HUD**:
   - Compact status pill with flashing red recording indicator.
   - Live elapsed timer and **real-time file size counter** (`2.4 MB`).
   - Dynamic animated audio level meter.
   - One-click `Stop` button.

6. **Post-Recording Completion Sheet**:
   - Instant video thumbnail preview.
   - Exact file size and **Storage Saved %** badge compared to default macOS MOV.
   - Quick actions: "Open Video", "Show in Finder", "Copy Video File".

---

## 🛠 Project Structure

```
ScreenRecorder/
├── Package.swift                             # SPM manifest (macOS 14+)
├── build_app.sh                              # Release build and .app packager script
├── ScreenRecorder.app/                       # Ready-to-run macOS Application Bundle
├── Sources/
│   └── ScreenRecorder/
│       ├── main.swift                        # Application entry point
│       ├── App/
│       │   ├── AppDelegate.swift             # App lifecycle, NSStatusItem & panels
│       │   └── AppState.swift                # Central observable state & engine coordinator
│       ├── Models/
│       │   ├── VideoFormat.swift             # Container, Codecs, Presets & File size estimator
│       │   ├── AppSettings.swift             # UserDefaults preferences persistence
│       │   ├── RecordingTarget.swift         # Display, Window, and Area targets
│       │   └── RecordingResult.swift         # Result metadata & savings calculation
│       ├── Engine/
│       │   ├── ScreenCaptureEngine.swift     # ScreenCaptureKit zero-copy pipeline
│       │   ├── AudioCaptureEngine.swift      # Microphone capture & live audio metering
│       │   ├── VideoWriterEngine.swift       # AVAssetWriter hardware encoder
│       │   └── PermissionsManager.swift      # Screen & Mic permissions handling
│       └── UI/
│           ├── FloatingControlBarView.swift  # Floating pill bar (Cmd+Shift+5 style)
│           ├── AreaSelectionOverlay.swift    # Interactive crop area selection window
│           ├── RecordingHUDView.swift        # Live recording status HUD & audio meter
│           ├── SettingsView.swift            # Preferences & File size comparison matrix
│           └── CompletionCardView.swift      # Post-recording summary card
└── Tests/
    └── ScreenRecorderTests/
        └── ScreenRecorderTests.swift         # Unit tests for codecs, bitrates & estimators
```

---

## 💻 Building and Running

### Requirements
- macOS 14.0 or newer
- Xcode 15+ / Swift 6+

### 1. Build and Run App Bundle
```bash
cd /Users/quantranlehai/.gemini/antigravity-ide/scratch/ScreenRecorder
./build_app.sh
open ScreenRecorder.app
```

### 2. Run Tests
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### 3. Run directly from Terminal
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

---

## 🔒 Permissions
On first launch, macOS requires granting Screen Recording access in:
`System Settings` > `Privacy & Security` > `Screen & System Audio Recording`.
If you enable microphone recording, microphone access will be requested once.
