import SwiftUI
import AppKit
import AVFoundation

/// Full Settings / Preferences Window
@MainActor
public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionsManager
    
    @State private var selectedTab: Int = 0
    
    public init(settings: AppSettings, permissions: PermissionsManager) {
        self.settings = settings
        self.permissions = permissions
    }
    
    public init() {
        self.init(settings: .shared, permissions: .shared)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Header
            Picker("", selection: $selectedTab) {
                Text("Video & Format").tag(0)
                Text("Size Comparison").tag(1)
                Text("Audio").tag(2)
                Text("General").tag(3)
                Text("Shortcuts").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(16)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case 0:
                        videoSettingsSection
                    case 1:
                        sizeComparisonSection
                    case 2:
                        audioSettingsSection
                    case 3:
                        generalSettingsSection
                    case 4:
                        shortcutsSettingsSection
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 540, height: 490)
    }
    
    // MARK: - Tab 0: Video & Format Settings
    
    private var videoSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Container Format
            VStack(alignment: .leading, spacing: 6) {
                Text("Video Container")
                    .font(.headline)
                
                Picker("", selection: $settings.container) {
                    ForEach(VideoContainer.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(settings.container == .mp4
                     ? "✓ MP4 is universally supported on web, Windows, Android, Slack, and Discord."
                     : "ℹ QuickTime MOV is Apple's native container, supports ProRes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Video Codec
            VStack(alignment: .leading, spacing: 6) {
                Text("Video Codec (Compression)")
                    .font(.headline)
                
                Picker("", selection: $settings.codec) {
                    ForEach(VideoCodec.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.radioGroup)
                
                if settings.codec == .hevc {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.orange)
                        Text("HEVC uses Apple Silicon hardware encoder. Up to 50% smaller files than H.264 with crisp text clarity.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Quality Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Quality Preset")
                    .font(.headline)
                
                Picker("", selection: $settings.preset) {
                    ForEach(QualityPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                
                Text(settings.preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.preset == .custom {
                    HStack {
                        Text("Bitrate: \(Int(settings.customBitrateMbps)) Mbps")
                            .font(.system(size: 12, design: .monospaced))
                        Slider(value: $settings.customBitrateMbps, in: 1.0...50.0, step: 1.0)
                    }
                    .padding(.top, 4)
                }
            }
            
            Divider()
            
            // Frame Rate & Resolution
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame Rate")
                        .font(.headline)
                    Picker("", selection: $settings.fps) {
                        ForEach(RecordingFPS.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resolution Scale")
                        .font(.headline)
                    Picker("", selection: $settings.resolutionScale) {
                        ForEach(ResolutionScale.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }
        }
    }
    
    // MARK: - Tab 1: Size Comparison
    
    private var sizeComparisonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File Size Comparison (5 Min Recording)")
                .font(.headline)
            
            Text("See how different video formats and codecs dramatically impact file weight:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Comparison Cards
            VStack(spacing: 8) {
                comparisonRow(
                    title: "Default macOS QuickTime MOV",
                    subtitle: "Uncompressed / High Bitrate MOV",
                    size: "~350 MB",
                    savings: "Baseline (Heavy)",
                    color: .red
                )
                
                comparisonRow(
                    title: "ScreenRecorder • H.264 MP4",
                    subtitle: "Universal Compatibility MP4",
                    size: "~45 MB",
                    savings: "87% Smaller",
                    color: .blue
                )
                
                comparisonRow(
                    title: "ScreenRecorder • HEVC MP4 (Recommended)",
                    subtitle: "Hardware HEVC with Optimized Bitrate",
                    size: "~18 MB",
                    savings: "95% Smaller!",
                    color: .green,
                    isRecommended: true
                )
                
                comparisonRow(
                    title: "ScreenRecorder • Ultra Compact",
                    subtitle: "Tuned for Slack, Discord & Web Uploads",
                    size: "~8 MB",
                    savings: "98% Smaller!",
                    color: .purple
                )
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Estimates based on 1080p 60fps standard desktop content. Real files may vary depending on on-screen motion.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func comparisonRow(
        title: String,
        subtitle: String,
        size: String,
        savings: String,
        color: Color,
        isRecommended: Bool = false
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if isRecommended {
                        Text("BEST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(size)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text(savings)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecommended ? color.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Tab 2: Audio Settings
    
    private var audioSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Audio Capture Mode")
                .font(.headline)
            
            Picker("", selection: $settings.audioMode) {
                ForEach(AudioCaptureMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            
            Divider()
            
            // Microphone Permission Status
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Microphone Permission")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(permissions.hasMicrophonePermission ? "Permission granted" : "Access required for audio")
                        .font(.caption)
                        .foregroundColor(permissions.hasMicrophonePermission ? .green : .red)
                }
                
                Spacer()
                
                if !permissions.hasMicrophonePermission {
                    Button("Grant Access") {
                        permissions.openMicrophoneSystemSettings()
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            // System Audio Note
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Audio (ScreenCaptureKit)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Captures audio from running applications, games, and web videos with zero latency.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Tab 3: General Settings
    
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Save Directory
            VStack(alignment: .leading, spacing: 6) {
                Text("Save Destination")
                    .font(.headline)
                
                HStack {
                    Text(settings.saveDirectoryURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                    
                    Button("Choose Folder...") {
                        chooseFolder()
                    }
                    
                    Button("Open") {
                        NSWorkspace.shared.open(settings.saveDirectoryURL)
                    }
                }
            }
            
            Divider()
            
            // Filename Prefix
            VStack(alignment: .leading, spacing: 6) {
                Text("Filename Prefix")
                    .font(.headline)
                
                TextField("Prefix", text: $settings.filenamePrefix)
                    .textFieldStyle(.roundedBorder)
                
                Text("Files will be saved as: \(settings.filenamePrefix) YYYY-MM-DD at HH.mm.ss.\(settings.container.fileExtension)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Screen Capture Permission
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Screen Recording Permission")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(permissions.hasScreenRecordingPermission ? "Permission granted" : "Access required to record screen")
                        .font(.caption)
                        .foregroundColor(permissions.hasScreenRecordingPermission ? .green : .red)
                }
                
                Spacer()
                
                if !permissions.hasScreenRecordingPermission {
                    Button("Grant in System Settings") {
                        permissions.openScreenRecordingSystemSettings()
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            Divider()
            
            // Post-recording actions
            VStack(alignment: .leading, spacing: 8) {
                Text("After Recording")
                    .font(.headline)
                
                Toggle("Open video in default player", isOn: $settings.openInPlayerAfterRecord)
                Toggle("Copy video file to clipboard", isOn: $settings.copyToClipboardAfterRecord)
                
                HStack {
                    Text("Auto-close notification:")
                    Picker("", selection: $settings.autoCloseNotificationSeconds) {
                        Text("Never").tag(0)
                        Text("3 seconds").tag(3)
                        Text("5 seconds (Default)").tag(5)
                        Text("8 seconds").tag(8)
                        Text("10 seconds").tag(10)
                    }
                    .frame(width: 170)
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Tab 4: Shortcuts Settings (Key Mapping)
    
    private var shortcutsSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Enable Global Keyboard Shortcuts", isOn: $settings.globalHotkeysEnabled)
                .font(.headline)
            
            Text("Global hotkeys allow you to start, stop, and control recording from anywhere in macOS even when RecLite is running in the background.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Key mapping items
            VStack(alignment: .leading, spacing: 16) {
                shortcutRow(
                    title: "Start / Stop Recording",
                    description: "Toggle screen recording start and stop",
                    shortcut: $settings.shortcutStartStop,
                    presets: [
                        KeyShortcut.defaultStartStop,
                        KeyShortcut(keyCode: 15, modifiers: [.command, .option]), // ⌘⌥R
                        KeyShortcut(keyCode: 15, modifiers: [.control, .option]), // ⌃⌥R
                        KeyShortcut(keyCode: 1, modifiers: [.command, .shift])    // ⌘⇧S
                    ]
                )
                
                Divider()
                
                shortcutRow(
                    title: "Pause / Stop Recording",
                    description: "Pause active recording or stop if currently running",
                    shortcut: $settings.shortcutPauseResume,
                    presets: [
                        KeyShortcut.defaultPauseResume,
                        KeyShortcut(keyCode: 35, modifiers: [.command, .option]), // ⌘⌥P
                        KeyShortcut(keyCode: 35, modifiers: [.control, .option]), // ⌃⌥P
                        KeyShortcut(keyCode: 49, modifiers: [.command, .shift])   // ⌘⇧Space
                    ]
                )
                
                Divider()
                
                shortcutRow(
                    title: "Toggle Control Bar",
                    description: "Show or hide the floating recorder control bar",
                    shortcut: $settings.shortcutToggleBar,
                    presets: [
                        KeyShortcut.defaultToggleBar,
                        KeyShortcut(keyCode: 23, modifiers: [.command, .option]), // ⌘⌥5
                        KeyShortcut(keyCode: 18, modifiers: [.command, .shift]),  // ⌘⇧1
                        KeyShortcut(keyCode: 48, modifiers: [.command, .shift])   // ⌘⇧Tab
                    ]
                )
            }
            .disabled(!settings.globalHotkeysEnabled)
            .opacity(settings.globalHotkeysEnabled ? 1.0 : 0.5)
            
            Divider()
            
            HStack {
                Button("Reset Shortcuts to Defaults") {
                    settings.resetShortcutsToDefaults()
                }
                .disabled(!settings.globalHotkeysEnabled)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.blue)
                    Text("Global macOS Key Mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func shortcutRow(
        title: String,
        description: String,
        shortcut: Binding<KeyShortcut>,
        presets: [KeyShortcut]
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Key Badge
                Text(shortcut.wrappedValue.displayString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                
                // Key Mapping Preset Picker Menu
                Menu {
                    Text("Select Preset Key Mapping:")
                    Divider()
                    ForEach(presets, id: \.self) { p in
                        Button(action: {
                            shortcut.wrappedValue = p
                        }) {
                            if p == shortcut.wrappedValue {
                                Text("✓ \(p.displayString)")
                            } else {
                                Text(p.displayString)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.medium)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
    
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.customSavePath = url.path
        }
    }
}
