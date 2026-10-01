import Foundation
import AVFoundation
import AppKit
import CoreMedia
import VideoToolbox

/// Manages AVAssetWriter pipeline with hardware-accelerated encoding
public final class VideoWriterEngine: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let outputURL: URL
    private let container: VideoContainer
    private let codec: VideoCodec
    private let targetDimensions: CGSize
    private let fps: Int
    private let bitrate: Int
    private let hasAudio: Bool
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private let writerQueue = DispatchQueue(label: "com.screenrecorder.writerQueue", qos: .userInitiated)
    private var isSessionStarted = false
    private var sessionStartTime: CMTime = .invalid
    private var lastVideoTime: CMTime = .invalid
    
    public private(set) var bytesWritten: Int64 = 0
    public private(set) var isWriting: Bool = false
    
    // MARK: - Initializer
    
    public init(
        outputURL: URL,
        container: VideoContainer,
        codec: VideoCodec,
        dimensions: CGSize,
        fps: Int,
        bitrate: Int,
        hasAudio: Bool
    ) {
        self.outputURL = outputURL
        self.container = container
        self.codec = codec
        // Dimensions must be even integers for video encoders
        let width = Int(dimensions.width) + (Int(dimensions.width) % 2)
        let height = Int(dimensions.height) + (Int(dimensions.height) % 2)
        self.targetDimensions = CGSize(width: max(2, width), height: max(2, height))
        self.fps = fps
        self.bitrate = bitrate
        self.hasAudio = hasAudio
    }
    
    // MARK: - Setup & Start
    
    public func start() throws {
        // Ensure parent directory exists
        let parentDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: container.avFileType)
        
        // 1. Configure Video Input
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoExpectedSourceFrameRateKey: fps
        ]
        
        if codec == .h264 {
            compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec.avCodecType,
            AVVideoWidthKey: Int(targetDimensions.width),
            AVVideoHeightKey: Int(targetDimensions.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]
        
        if codec != .proRes422 {
            videoSettings[AVVideoCompressionPropertiesKey] = compressionProps
        }
        
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        
        guard writer.canAdd(vInput) else {
            throw NSError(domain: "VideoWriterEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to asset writer"])
        }
        writer.add(vInput)
        
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(targetDimensions.width),
            kCVPixelBufferHeightKey as String: Int(targetDimensions.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        // 2. Configure Audio Input (if enabled)
        var aInput: AVAssetWriterInput?
        if hasAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000
            ]
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioIn.expectsMediaDataInRealTime = true
            
            if writer.canAdd(audioIn) {
                writer.add(audioIn)
                aInput = audioIn
            }
        }
        
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "VideoWriterEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
        }
        
        self.assetWriter = writer
        self.videoInput = vInput
        self.pixelBufferAdaptor = adaptor
        self.audioInput = aInput
        self.isWriting = true
        self.isSessionStarted = false
    }
    
    // MARK: - Frame Append
    
    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isWriting, let writer = self.assetWriter, let vInput = self.videoInput else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.sessionStartTime = pts
                self.isSessionStarted = true
            }
            
            guard vInput.isReadyForMoreMediaData else { return }
            
            vInput.append(sampleBuffer)
            self.lastVideoTime = pts
            self.updateBytesWritten()
        }
    }
    
    public func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isWriting, let writer = self.assetWriter, let adaptor = self.pixelBufferAdaptor else { return }
            
            guard presentationTime.isValid else { return }
            
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: presentationTime)
                self.sessionStartTime = presentationTime
                self.isSessionStarted = true
            }
            
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return }
            
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            self.lastVideoTime = presentationTime
            self.updateBytesWritten()
        }
    }
    
    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isWriting, let aInput = self.audioInput else { return }
            
            // Only append audio after video session has begun
            guard self.isSessionStarted else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid, pts >= self.sessionStartTime else { return }
            
            if aInput.isReadyForMoreMediaData {
                aInput.append(sampleBuffer)
            }
        }
    }
    
    private func updateBytesWritten() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attrs[.size] as? NSNumber {
            self.bytesWritten = size.int64Value
        }
    }
    
    // MARK: - Finish Writing
    
    public func finish() async throws -> RecordingResult {
        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "VideoWriterEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Deallocated"]))
                    return
                }
                
                self.isWriting = false
                guard let writer = self.assetWriter else {
                    continuation.resume(throwing: NSError(domain: "VideoWriterEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "No active writer"]))
                    return
                }
                
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                
                writer.finishWriting {
                    if let error = writer.error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    // Calculate final duration
                    var duration: TimeInterval = 0
                    if self.sessionStartTime.isValid && self.lastVideoTime.isValid {
                        let diff = CMTimeSubtract(self.lastVideoTime, self.sessionStartTime)
                        duration = max(0.1, CMTimeGetSeconds(diff))
                    }
                    
                    // Final file size
                    var finalFileSize: Int64 = 0
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: self.outputURL.path),
                       let size = attrs[.size] as? NSNumber {
                        finalFileSize = size.int64Value
                    }
                    
                    // Generate thumbnail
                    let thumbnail = self.generateThumbnail(for: self.outputURL)
                    
                    let result = RecordingResult(
                        fileURL: self.outputURL,
                        duration: duration,
                        fileSize: finalFileSize,
                        dimensions: self.targetDimensions,
                        codec: self.codec,
                        container: self.container,
                        thumbnail: thumbnail
                    )
                    
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    private func generateThumbnail(for url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 480, height: 270)
        
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        return nil
    }
}
