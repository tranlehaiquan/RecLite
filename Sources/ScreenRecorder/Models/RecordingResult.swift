import Foundation
import AppKit
import AVFoundation

public struct RecordingResult: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let fileURL: URL
    public let duration: TimeInterval
    public let fileSize: Int64
    public let dimensions: CGSize
    public let codec: VideoCodec
    public let container: VideoContainer
    public let thumbnail: NSImage?
    public let recordedAt: Date
    
    public init(
        fileURL: URL,
        duration: TimeInterval,
        fileSize: Int64,
        dimensions: CGSize,
        codec: VideoCodec,
        container: VideoContainer,
        thumbnail: NSImage? = nil,
        recordedAt: Date = Date()
    ) {
        self.fileURL = fileURL
        self.duration = duration
        self.fileSize = fileSize
        self.dimensions = dimensions
        self.codec = codec
        self.container = container
        self.thumbnail = thumbnail
        self.recordedAt = recordedAt
    }
    
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public var formattedFileSize: String {
        return FileSizeEstimator.formatBytes(fileSize)
    }
    
    /// Estimated size this video would have occupied with macOS default MOV encoder
    public var estimatedMacOsMovFileSize: Int64 {
        let minutes = max(0.1, duration / 60.0)
        let mbPerMin = FileSizeEstimator.defaultMacOsMovMegabytesPerMinute(resolution: dimensions, fps: 60)
        let estimatedBytes = Int64(mbPerMin * minutes * 1024.0 * 1024.0)
        return max(fileSize, estimatedBytes)
    }
    
    /// Percentage saved compared to default MOV
    public var storageSavedPercentage: Int {
        let defaultBytes = estimatedMacOsMovFileSize
        guard defaultBytes > fileSize else { return 0 }
        let diff = defaultBytes - fileSize
        return min(99, Int((Double(diff) / Double(defaultBytes)) * 100))
    }
}
