import Foundation
import SwiftUI

/// App Settings managed with UserDefaults persistence
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    // MARK: - Keys
    private enum Keys {
        static let container = "app_video_container"
        static let codec = "app_video_codec"
        static let preset = "app_quality_preset"
        static let fps = "app_recording_fps"
        static let resolutionScale = "app_resolution_scale"
        static let customBitrateMbps = "app_custom_bitrate_mbps"
        static let audioMode = "app_audio_mode"
        static let showCursor = "app_show_cursor"
        static let highlightClicks = "app_highlight_clicks"
        static let countdownSeconds = "app_countdown_seconds"
        static let outputDirectoryBookmark = "app_output_directory_bookmark"
        static let customSavePath = "app_custom_save_path"
        static let filenamePrefix = "app_filename_prefix"
        static let copyToClipboardAfterRecord = "app_copy_to_clipboard"
        static let openInPlayerAfterRecord = "app_open_in_player"
        static let autoCloseNotificationSeconds = "app_auto_close_notification_seconds"
    }
    
    // MARK: - Published Properties
    
    @Published public var container: VideoContainer {
        didSet {
            UserDefaults.standard.set(container.rawValue, forKey: Keys.container)
            // Ensure codec is compatible with MP4 container
            if container == .mp4 && !codec.isMp4Compatible {
                codec = .hevc
            }
        }
    }
    
    @Published public var codec: VideoCodec {
        didSet {
            UserDefaults.standard.set(codec.rawValue, forKey: Keys.codec)
            if !codec.isMp4Compatible && container == .mp4 {
                container = .mov
            }
        }
    }
    
    @Published public var preset: QualityPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: Keys.preset) }
    }
    
    @Published public var fps: RecordingFPS {
        didSet { UserDefaults.standard.set(fps.rawValue, forKey: Keys.fps) }
    }
    
    @Published public var resolutionScale: ResolutionScale {
        didSet { UserDefaults.standard.set(resolutionScale.rawValue, forKey: Keys.resolutionScale) }
    }
    
    @Published public var customBitrateMbps: Double {
        didSet { UserDefaults.standard.set(customBitrateMbps, forKey: Keys.customBitrateMbps) }
    }
    
    @Published public var audioMode: AudioCaptureMode {
        didSet { UserDefaults.standard.set(audioMode.rawValue, forKey: Keys.audioMode) }
    }
    
    @Published public var showCursor: Bool {
        didSet { UserDefaults.standard.set(showCursor, forKey: Keys.showCursor) }
    }
    
    @Published public var highlightClicks: Bool {
        didSet { UserDefaults.standard.set(highlightClicks, forKey: Keys.highlightClicks) }
    }
    
    @Published public var countdownSeconds: Int {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: Keys.countdownSeconds) }
    }
    
    @Published public var customSavePath: String? {
        didSet { UserDefaults.standard.set(customSavePath, forKey: Keys.customSavePath) }
    }
    
    @Published public var filenamePrefix: String {
        didSet { UserDefaults.standard.set(filenamePrefix, forKey: Keys.filenamePrefix) }
    }
    
    @Published public var copyToClipboardAfterRecord: Bool {
        didSet { UserDefaults.standard.set(copyToClipboardAfterRecord, forKey: Keys.copyToClipboardAfterRecord) }
    }
    
    @Published public var openInPlayerAfterRecord: Bool {
        didSet { UserDefaults.standard.set(openInPlayerAfterRecord, forKey: Keys.openInPlayerAfterRecord) }
    }
    
    @Published public var autoCloseNotificationSeconds: Int {
        didSet { UserDefaults.standard.set(autoCloseNotificationSeconds, forKey: Keys.autoCloseNotificationSeconds) }
    }
    
    // MARK: - Initializer
    
    private init() {
        let defaults = UserDefaults.standard
        
        let containerRaw = defaults.string(forKey: Keys.container) ?? VideoContainer.mp4.rawValue
        self.container = VideoContainer(rawValue: containerRaw) ?? .mp4
        
        let codecRaw = defaults.string(forKey: Keys.codec) ?? VideoCodec.hevc.rawValue
        self.codec = VideoCodec(rawValue: codecRaw) ?? .hevc
        
        let presetRaw = defaults.string(forKey: Keys.preset) ?? QualityPreset.balanced.rawValue
        self.preset = QualityPreset(rawValue: presetRaw) ?? .balanced
        
        let fpsRaw = defaults.integer(forKey: Keys.fps)
        self.fps = RecordingFPS(rawValue: fpsRaw == 0 ? 60 : fpsRaw) ?? .fps60
        
        let resRaw = defaults.string(forKey: Keys.resolutionScale) ?? ResolutionScale.native.rawValue
        self.resolutionScale = ResolutionScale(rawValue: resRaw) ?? .native
        
        let bitrateVal = defaults.double(forKey: Keys.customBitrateMbps)
        self.customBitrateMbps = bitrateVal > 0 ? bitrateVal : 8.0
        
        let audioRaw = defaults.string(forKey: Keys.audioMode) ?? AudioCaptureMode.microphone.rawValue
        self.audioMode = AudioCaptureMode(rawValue: audioRaw) ?? .microphone
        
        self.showCursor = defaults.object(forKey: Keys.showCursor) == nil ? true : defaults.bool(forKey: Keys.showCursor)
        self.highlightClicks = defaults.bool(forKey: Keys.highlightClicks)
        self.countdownSeconds = defaults.object(forKey: Keys.countdownSeconds) == nil ? 0 : defaults.integer(forKey: Keys.countdownSeconds)
        self.customSavePath = defaults.string(forKey: Keys.customSavePath)
        self.filenamePrefix = defaults.string(forKey: Keys.filenamePrefix) ?? "Screen Recording"
        self.copyToClipboardAfterRecord = defaults.bool(forKey: Keys.copyToClipboardAfterRecord)
        self.openInPlayerAfterRecord = defaults.object(forKey: Keys.openInPlayerAfterRecord) == nil ? true : defaults.bool(forKey: Keys.openInPlayerAfterRecord)
        self.autoCloseNotificationSeconds = defaults.object(forKey: Keys.autoCloseNotificationSeconds) == nil ? 5 : defaults.integer(forKey: Keys.autoCloseNotificationSeconds)
    }
    
    // MARK: - Computed Properties
    
    public var saveDirectoryURL: URL {
        if let customPath = customSavePath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        // Default to Movies directory or Desktop
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        let desktopDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        return moviesDir ?? desktopDir ?? FileManager.default.temporaryDirectory
    }
    
    /// Generate a new recording destination file URL with timestamp and proper extension
    public func generateOutputFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateString = formatter.string(from: Date())
        
        let filename = "\(filenamePrefix) \(dateString).\(container.fileExtension)"
        return saveDirectoryURL.appendingPathComponent(filename)
    }
}
