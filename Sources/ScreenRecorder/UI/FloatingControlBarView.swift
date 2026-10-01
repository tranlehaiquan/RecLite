import SwiftUI
import ScreenCaptureKit

/// Floating control bar modeled after macOS native Cmd+Shift+5 screen recording bar
public struct FloatingControlBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    
    @State private var isShowingOptionsMenu: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
        self.settings = appState.settings
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Close Button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Quit Application")
            
            Divider()
                .frame(height: 24)
                .opacity(0.3)
            
            // Section 1: Capture Mode Segmented Buttons
            HStack(spacing: 4) {
                CaptureModeButton(
                    mode: .entireScreen,
                    currentMode: appState.captureMode,
                    title: "Entire Screen",
                    iconName: "display"
                ) {
                    appState.setCaptureMode(.entireScreen)
                }
                
                CaptureModeButton(
                    mode: .selectedWindow,
                    currentMode: appState.captureMode,
                    title: "Selected Window",
                    iconName: "macwindow"
                ) {
                    if appState.captureMode == .selectedWindow && !appState.isShowingWindowSelection {
                        appState.isShowingWindowSelection = true
                        appState.refreshAvailableSources()
                    } else {
                        appState.setCaptureMode(.selectedWindow)
                    }
                }
                .contextMenu {
                    Button("Choose Window to Record (Zoom style)...") {
                        appState.setCaptureMode(.selectedWindow)
                        appState.isShowingWindowSelection = true
                        appState.refreshAvailableSources()
                    }
                    Divider()
                    if appState.availableWindows.isEmpty {
                        Text("No open windows detected")
                    } else {
                        ForEach(appState.availableWindows, id: \.windowID) { win in
                            let appName = win.owningApplication?.applicationName ?? "App"
                            let title = win.title ?? ""
                            let label = title.isEmpty ? appName : "\(appName): \(title)"
                            Button(action: {
                                appState.selectedWindow = win
                                appState.setCaptureMode(.selectedWindow)
                            }) {
                                HStack {
                                    Text(label)
                                    if appState.selectedWindow?.windowID == win.windowID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                
                CaptureModeButton(
                    mode: .selectedArea,
                    currentMode: appState.captureMode,
                    title: "Selected Area",
                    iconName: "rectangle.dashed"
                ) {
                    appState.setCaptureMode(.selectedArea)
                }
            }
            
            Divider()
                .frame(height: 24)
                .opacity(0.3)
            
            // Section 2: Audio Toggle Button
            Menu {
                ForEach(AudioCaptureMode.allCases) { mode in
                    Button(action: {
                        settings.audioMode = mode
                    }) {
                        HStack {
                            Text(mode.displayName)
                            if settings.audioMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: audioIconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(settings.audioMode == .none ? .secondary : .green)
                    
                    Text(settings.audioMode == .none ? "Muted" : "Audio")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Section 3: Format & Compression Quick Options
            Menu {
                // Video Container
                Section("Video Container") {
                    ForEach(VideoContainer.allCases) { container in
                        Button(action: {
                            settings.container = container
                        }) {
                            HStack {
                                Text(container.displayName)
                                if settings.container == container {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                // Codec Selection
                Section("Codec (Compression)") {
                    ForEach(VideoCodec.allCases) { codec in
                        Button(action: {
                            settings.codec = codec
                        }) {
                            HStack {
                                Text(codec.displayName)
                                if settings.codec == codec {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                // Quality Presets
                Section("Quality & Size Preset") {
                    ForEach(QualityPreset.allCases) { preset in
                        Button(action: {
                            settings.preset = preset
                        }) {
                            HStack {
                                Text(preset.displayName)
                                if settings.preset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                // Frame Rate
                Section("Frame Rate") {
                    ForEach(RecordingFPS.allCases) { fps in
                        Button(action: {
                            settings.fps = fps
                        }) {
                            HStack {
                                Text(fps.displayName)
                                if settings.fps == fps {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                // Countdown Timer
                Section("Timer") {
                    Button(action: { settings.countdownSeconds = 0 }) {
                        HStack {
                            Text("None")
                            if settings.countdownSeconds == 0 { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { settings.countdownSeconds = 3 }) {
                        HStack {
                            Text("3 Seconds")
                            if settings.countdownSeconds == 3 { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { settings.countdownSeconds = 5 }) {
                        HStack {
                            Text("5 Seconds")
                            if settings.countdownSeconds == 5 { Image(systemName: "checkmark") }
                        }
                    }
                }
                
                Divider()
                
                Button(action: {
                    settings.showCursor.toggle()
                }) {
                    HStack {
                        Text("Show Mouse Pointer")
                        if settings.showCursor { Image(systemName: "checkmark") }
                    }
                }
                
                Divider()
                
                Button("All Preferences...") {
                    appState.isShowingSettings = true
                }
            } label: {
                Text("Options")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Format / Target Badge (e.g. "MP4 • HEVC" or "WIN: Safari")
            VStack(alignment: .leading, spacing: 2) {
                if appState.captureMode == .selectedWindow, let win = appState.selectedWindow {
                    let app = win.owningApplication?.applicationName ?? "Window"
                    Text("WIN: \(app.uppercased())")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .lineLimit(1)
                } else {
                    Text("\(settings.container.rawValue.uppercased()) • \(settings.codec.shortName)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                }
                Text(estimatedSizeHint)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 6)
            
            // Section 4: Primary Record Button
            Button(action: {
                appState.toggleRecording()
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red.opacity(0.8), radius: 3)
                    
                    Text("Record")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.red.opacity(0.92), Color.red],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color.red.opacity(0.4), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .layoutPriority(2)
            .help("Start Recording (Return)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
    }
    
    private var audioIconName: String {
        switch settings.audioMode {
        case .none: return "mic.slash"
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .both: return "waveform"
        }
    }
    
    private var estimatedSizeHint: String {
        let mbMin = FileSizeEstimator.megabytesPerMinute(
            resolution: CGSize(width: 1920, height: 1080),
            fps: settings.fps.rawValue,
            codec: settings.codec,
            preset: settings.preset
        )
        return String(format: "~%.0f MB/min", mbMin)
    }
}

// MARK: - CaptureModeButton

struct CaptureModeButton: View {
    let mode: CaptureMode
    let currentMode: CaptureMode
    let title: String
    let iconName: String
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    var isSelected: Bool { mode == currentMode }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (isHovering ? .primary : .secondary))
                
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : (isHovering ? .primary : .secondary))
                    .lineLimit(1)
            }
            .frame(width: 84, height: 42)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.18) : (isHovering ? Color.white.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - VisualEffectBlur Helper

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
