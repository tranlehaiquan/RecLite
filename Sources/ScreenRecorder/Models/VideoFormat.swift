import Foundation
import AVFoundation
import CoreGraphics

/// Video container format
public enum VideoContainer: String, CaseIterable, Identifiable, Codable, Sendable {
    case mp4 = "mp4"
    case mov = "mov"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .mp4: return "MP4 (.mp4) - Universal"
        case .mov: return "QuickTime (.mov)"
        }
    }
    
    public var fileExtension: String {
        return rawValue
    }
    
    public var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }
}

/// Video compression codec
public enum VideoCodec: String, CaseIterable, Identifiable, Codable, Sendable {
    case hevc = "hevc"
    case h264 = "h264"
    case proRes422 = "prores422"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .hevc: return "HEVC / H.265 (Recommended - Smallest Size)"
        case .h264: return "H.264 / AVC (Most Compatible)"
        case .proRes422: return "Apple ProRes 422 (Editing/Lossless)"
        }
    }
    
    public var shortName: String {
        switch self {
        case .hevc: return "HEVC (H.265)"
        case .h264: return "H.264"
        case .proRes422: return "ProRes 422"
        }
    }
    
    public var avCodecType: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        case .proRes422: return .proRes422
        }
    }
    
    /// Whether this codec can be saved in an MP4 container
    public var isMp4Compatible: Bool {
        switch self {
        case .hevc, .h264: return true
        case .proRes422: return false // ProRes requires MOV
        }
    }
}

/// Quality presets tailored for crisp screen recordings and minimal file size
public enum QualityPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case ultraCompact = "ultraCompact"
    case balanced = "balanced"
    case highQuality = "highQuality"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .ultraCompact: return "Ultra Compact (Web / Slack / Discord)"
        case .balanced: return "Balanced (Recommended - High Clarity)"
        case .highQuality: return "High Quality (Pixel-Perfect Text)"
        case .custom: return "Custom Bitrate"
        }
    }
    
    public var description: String {
        switch self {
        case .ultraCompact:
            return "Extreme compression with clear text. Tiny files under 15 MB/5 min, great for sharing."
        case .balanced:
            return "Sweet spot between razor-sharp Retina visuals and small file footprint."
        case .highQuality:
            return "Higher bitrates for pristine gradients, video playback, and design demos."
        case .custom:
            return "Manually specify target bitrate in Mbps."
        }
    }
    
    /// Target bitrate in bits per second for a standard 1080p 60fps recording
    public func targetBitrate(for resolution: CGSize, fps: Int, codec: VideoCodec) -> Int {
        let pixelCount = max(1.0, Double(resolution.width * resolution.height))
        let standard1080p = 1920.0 * 1080.0
        let resolutionMultiplier = max(0.4, sqrt(pixelCount / standard1080p))
        let fpsMultiplier = Double(fps) / 60.0
        
        let baseBitrate: Double
        switch self {
        case .ultraCompact:
            baseBitrate = 3_000_000 // 3 Mbps for 1080p60
        case .balanced:
            baseBitrate = 7_000_000 // 7 Mbps for 1080p60
        case .highQuality:
            baseBitrate = 16_000_000 // 16 Mbps for 1080p60
        case .custom:
            baseBitrate = 8_000_000
        }
        
        // HEVC is roughly 40-50% more efficient than H.264 at equivalent visual fidelity
        let codecEfficiencyMultiplier: Double = (codec == .hevc) ? 0.65 : 1.0
        
        let calculated = baseBitrate * resolutionMultiplier * fpsMultiplier * codecEfficiencyMultiplier
        return max(800_000, Int(calculated))
    }
}

/// Screen recording frame rate options
public enum RecordingFPS: Int, CaseIterable, Identifiable, Codable, Sendable {
    case fps60 = 60
    case fps30 = 30
    case fps24 = 24
    
    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) FPS" }
}

/// Resolution scaling
public enum ResolutionScale: String, CaseIterable, Identifiable, Codable, Sendable {
    case native = "native"
    case p1080 = "1080p"
    case p720 = "720p"
    case half = "half"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .native: return "Native Resolution (100%)"
        case .p1080: return "1080p Max (Downscale if larger)"
        case .p720: return "720p Max (Super compact)"
        case .half: return "50% Scale"
        }
    }
    
    public func targetDimensions(from original: CGSize) -> CGSize {
        switch self {
        case .native:
            return original
        case .half:
            return CGSize(width: round(original.width * 0.5), height: round(original.height * 0.5))
        case .p1080:
            let maxDim: CGFloat = 1920
            if original.width <= maxDim && original.height <= 1080 {
                return original
            }
            let aspect = original.width / original.height
            if aspect >= (1920.0 / 1080.0) {
                return CGSize(width: 1920, height: round(1920 / aspect))
            } else {
                return CGSize(width: round(1080 * aspect), height: 1080)
            }
        case .p720:
            let maxDim: CGFloat = 1280
            if original.width <= maxDim && original.height <= 720 {
                return original
            }
            let aspect = original.width / original.height
            if aspect >= (1280.0 / 720.0) {
                return CGSize(width: 1280, height: round(1280 / aspect))
            } else {
                return CGSize(width: round(720 * aspect), height: 720)
            }
        }
    }
}

/// Audio recording options
public enum AudioCaptureMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "none"
    case microphone = "microphone"
    case system = "system"
    case both = "both"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .none: return "No Audio"
        case .microphone: return "Microphone Only"
        case .system: return "System Audio Only"
        case .both: return "Mic + System Audio"
        }
    }
}

/// Helper for estimating file size and savings
public struct FileSizeEstimator {
    /// Calculate estimated MB per minute of recording
    public static func megabytesPerMinute(
        resolution: CGSize,
        fps: Int,
        codec: VideoCodec,
        preset: QualityPreset,
        customBitrateMbps: Double = 8.0,
        includesAudio: Bool = true
    ) -> Double {
        if codec == .proRes422 {
            // ProRes 422 is approx 147 Mbps at 1080p29.97, ~300 Mbps at 1080p60
            let pixelRatio = (resolution.width * resolution.height) / (1920 * 1080)
            let proResBitrate = 150_000_000.0 * (Double(fps) / 30.0) * pixelRatio
            let audioBitrate = includesAudio ? 256_000.0 : 0.0
            let totalBitsPerSec = proResBitrate + audioBitrate
            return (totalBitsPerSec * 60.0) / (8.0 * 1024.0 * 1024.0)
        }
        
        let videoBitrate: Double
        if preset == .custom {
            videoBitrate = customBitrateMbps * 1_000_000.0
        } else {
            videoBitrate = Double(preset.targetBitrate(for: resolution, fps: fps, codec: codec))
        }
        
        let audioBitrate: Double = includesAudio ? 160_000.0 : 0.0 // AAC 160kbps
        let totalBitsPerSec = videoBitrate + audioBitrate
        return (totalBitsPerSec * 60.0) / (8.0 * 1024.0 * 1024.0)
    }
    
    /// Default macOS QuickTime MOV estimated MB per minute (typically 40 - 120+ Mbps)
    public static func defaultMacOsMovMegabytesPerMinute(resolution: CGSize, fps: Int) -> Double {
        let pixelRatio = max(0.5, (resolution.width * resolution.height) / (1920 * 1080))
        let typicalBitrate = 45_000_000.0 * (Double(fps) / 60.0) * pixelRatio
        return (typicalBitrate * 60.0) / (8.0 * 1024.0 * 1024.0)
    }
    
    /// Calculate storage saved percentage
    public static func savingsPercentage(
        ourMbPerMin: Double,
        macOsDefaultMbPerMin: Double
    ) -> Int {
        guard macOsDefaultMbPerMin > 0 else { return 0 }
        let diff = max(0, macOsDefaultMbPerMin - ourMbPerMin)
        return min(99, Int((diff / macOsDefaultMbPerMin) * 100))
    }
    
    /// Format bytes to human readable string (e.g. 14.2 MB)
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
