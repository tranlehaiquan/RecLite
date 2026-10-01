import Foundation
import AVFoundation
import CoreMedia
import AppKit

/// High-performance video and audio writer powered by AVAssetWriter
public final class VideoWriterEngine: @unchecked Sendable {
    
    // MARK: - Configuration
    
    public let outputURL: URL
    public let container: VideoContainer
    public let codec: VideoCodec
    public let targetDimensions: CGSize
    public let fps: Int
    public let bitrate: Int
    public let hasAudio: Bool
    
    // MARK: - State
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    
    private let writerQueue = DispatchQueue(label: "com.screenrecorder.writerQueue", qos: .userInitiated)
    
    private var isWriting: Bool = false
    private var isSessionStarted: Bool = false
    private var sessionStartTime: CMTime = .invalid
    private var lastVideoTime: CMTime = .invalid
    private var lastAudioTime: CMTime = .invalid
    
    public private(set) var bytesWritten: Int64 = 0
    
    // MARK: - Initializer
    
    public init(
        outputURL: URL,
        container: VideoContainer,
        codec: VideoCodec,
        dimensions: CGSize,
        fps: Int,
        bitrate: Int,
        hasAudio: Bool = false
    ) {
        self.outputURL = outputURL
        self.container = container
        self.codec = codec
        self.targetDimensions = dimensions
        self.fps = fps
        self.bitrate = bitrate
        self.hasAudio = hasAudio
    }
    
    // MARK: - Lifecycle
    
    public func start() throws {
        // Remove existing file at path if any
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: container.avFileType)
        
        // 1. Configure Video Input
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2 // Keyframe every 2 seconds
        ]
        
        if codec == .h264 {
            compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        } else if codec == .hevc {
            compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
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
            var channelLayout = AudioChannelLayout()
            memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
            channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            let channelLayoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000,
                AVChannelLayoutKey: channelLayoutData
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
        self.sessionStartTime = .invalid
        self.lastVideoTime = .invalid
        self.lastAudioTime = .invalid
    }
    
    // MARK: - Frame Append
    
    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        
        appendVideoPixelBuffer(pixelBuffer, presentationTime: pts)
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
            
            // AVAssetWriter requires strictly increasing timestamps
            if self.lastVideoTime.isValid && presentationTime <= self.lastVideoTime {
                return
            }
            
            guard adaptor.assetWriterInput.isReadyForMoreMediaData else { return }
            
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                self.lastVideoTime = presentationTime
                self.updateBytesWritten()
            } else if writer.status == .failed {
                print("[VideoWriterEngine] Video append failed: \(String(describing: writer.error))")
            }
        }
    }
    
    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isWriting, let aInput = self.audioInput, let writer = self.assetWriter else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            // If session hasn't started yet, audio can start the session
            if !self.isSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.sessionStartTime = pts
                self.isSessionStarted = true
            }
            
            // Ensure audio is standardized to Stereo Float32
            guard let stereoBuffer = self.ensureStereoSampleBuffer(sampleBuffer) else { return }
            let bufferDuration = CMSampleBufferGetDuration(sampleBuffer)
            
            // Check for initial gap between session start and first audio buffer
            if !self.lastAudioTime.isValid {
                if pts > self.sessionStartTime {
                    let gap = CMTimeSubtract(pts, self.sessionStartTime)
                    if CMTimeGetSeconds(gap) > 0.02 {
                        self.appendSilence(from: self.sessionStartTime, to: pts, input: aInput)
                    }
                }
            } else {
                // If there's an intermediate gap of more than 150ms (e.g. system audio paused), fill with silence
                let expectedTime = self.lastAudioTime
                if pts > expectedTime {
                    let gap = CMTimeSubtract(pts, expectedTime)
                    if CMTimeGetSeconds(gap) > 0.15 {
                        self.appendSilence(from: expectedTime, to: pts, input: aInput)
                    }
                }
            }
            
            // Calculate adjusted PTS if needed to ensure strictly increasing timestamps
            var finalPTS = pts
            if self.lastAudioTime.isValid && pts <= self.lastAudioTime {
                finalPTS = CMTimeAdd(self.lastAudioTime, CMTime(value: 1, timescale: 48000))
            }
            
            // If timestamp had to be adjusted, recreate with new timing
            let bufferToAppend: CMSampleBuffer
            if CMTimeCompare(finalPTS, pts) != 0 {
                bufferToAppend = self.retimedSampleBuffer(stereoBuffer, newPTS: finalPTS, duration: bufferDuration) ?? stereoBuffer
            } else {
                bufferToAppend = stereoBuffer
            }
            
            if aInput.isReadyForMoreMediaData {
                if aInput.append(bufferToAppend) {
                    let dur = bufferDuration.isValid && CMTimeGetSeconds(bufferDuration) > 0 ? bufferDuration : CMTime(value: Int64(CMSampleBufferGetNumSamples(bufferToAppend)), timescale: 48000)
                    self.lastAudioTime = CMTimeAdd(finalPTS, dur)
                } else if writer.status == .failed {
                    print("[VideoWriterEngine] Audio append failed: \(String(describing: writer.error))")
                }
            }
        }
    }
    
    private func updateBytesWritten() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attrs[.size] as? NSNumber {
            self.bytesWritten = size.int64Value
        }
    }
    
    // MARK: - Audio Format Normalization & Silence Generation
    
    private func ensureStereoSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else {
            return sampleBuffer
        }
        
        // Already 2 channels stereo
        if asbd.mChannelsPerFrame == 2 {
            return sampleBuffer
        }
        
        // Handle 1 channel mono -> 2 channel stereo
        guard asbd.mChannelsPerFrame == 1,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return sampleBuffer }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == noErr, let ptr = dataPointer, length > 0 else { return sampleBuffer }
        
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return sampleBuffer }
        
        var stereoSamples = [Float](repeating: 0, count: sampleCount * 2)
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let floats = ptr.withMemoryRebound(to: Float.self, capacity: sampleCount) { UnsafeBufferPointer(start: $0, count: sampleCount) }
            for i in 0..<sampleCount {
                let val = floats[i]
                stereoSamples[i * 2] = val
                stereoSamples[i * 2 + 1] = val
            }
        } else {
            let ints = ptr.withMemoryRebound(to: Int16.self, capacity: sampleCount) { UnsafeBufferPointer(start: $0, count: sampleCount) }
            for i in 0..<sampleCount {
                let val = Float(ints[i]) / 32768.0
                stereoSamples[i * 2] = val
                stereoSamples[i * 2 + 1] = val
            }
        }
        
        var stereoASBD = AudioStreamBasicDescription(
            mSampleRate: asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        var channelLayout = AudioChannelLayout()
        memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        var stereoFormatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &stereoASBD,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &channelLayout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &stereoFormatDesc
        )
        guard let sDesc = stereoFormatDesc else { return sampleBuffer }
        
        let byteCount = stereoSamples.count * MemoryLayout<Float>.size
        var newBlockBuffer: CMBlockBuffer?
        stereoSamples.withUnsafeBytes { raw in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &newBlockBuffer
            )
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: newBlockBuffer!, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard let nb = newBlockBuffer else { return sampleBuffer }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        
        var outBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: nb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: sDesc,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outBuffer
        )
        return outBuffer ?? sampleBuffer
    }
    
    private func retimedSampleBuffer(_ sbuf: CMSampleBuffer, newPTS: CMTime, duration: CMTime) -> CMSampleBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sbuf),
              let block = CMSampleBufferGetDataBuffer(sbuf) else { return nil }
        let sampleCount = CMSampleBufferGetNumSamples(sbuf)
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: newPTS, decodeTimeStamp: .invalid)
        
        var out: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &out
        )
        return out
    }
    
    private func appendSilence(from startPTS: CMTime, to endPTS: CMTime, input: AVAssetWriterInput) {
        let diff = CMTimeSubtract(endPTS, startPTS)
        let totalSeconds = CMTimeGetSeconds(diff)
        guard totalSeconds > 0.005 else { return }
        
        var currentPTS = startPTS
        let maxChunkSeconds: Double = 1.0
        while CMTimeCompare(currentPTS, endPTS) < 0 {
            let nextPTS = CMTimeMinimum(CMTimeAdd(currentPTS, CMTime(seconds: maxChunkSeconds, preferredTimescale: 48000)), endPTS)
            if let silenceBuffer = makeSilenceBuffer(startPTS: currentPTS, endPTS: nextPTS) {
                if input.isReadyForMoreMediaData {
                    input.append(silenceBuffer)
                }
            }
            currentPTS = nextPTS
        }
        self.lastAudioTime = endPTS
    }
    
    private func makeSilenceBuffer(startPTS: CMTime, endPTS: CMTime) -> CMSampleBuffer? {
        let diff = CMTimeSubtract(endPTS, startPTS)
        let seconds = CMTimeGetSeconds(diff)
        guard seconds > 0.001 else { return nil }
        
        let sampleRate: Double = 48000
        let sampleCount = max(1, Int(round(seconds * sampleRate)))
        
        var stereoASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        var channelLayout = AudioChannelLayout()
        memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &stereoASBD,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &channelLayout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard let desc = formatDesc else { return nil }
        
        let byteCount = sampleCount * 2 * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard let block = blockBuffer else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        
        var timing = CMSampleTimingInfo(
            duration: diff,
            presentationTimeStamp: startPTS,
            decodeTimeStamp: .invalid
        )
        
        var outBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outBuffer
        )
        return outBuffer
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
                
                guard self.isSessionStarted else {
                    writer.cancelWriting()
                    continuation.resume(throwing: NSError(
                        domain: "VideoWriterEngine",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Recording was too short or no video frames were captured. Please check Screen Recording permissions in System Settings."]
                    ))
                    return
                }
                
                // If audio was enabled, ensure audio track finishes cleanly up to the last video time
                if let aInput = self.audioInput, self.hasAudio, self.lastVideoTime.isValid {
                    if !self.lastAudioTime.isValid {
                        // No audio samples were ever received; fill full duration with silence
                        self.appendSilence(from: self.sessionStartTime, to: self.lastVideoTime, input: aInput)
                    } else if self.lastAudioTime < self.lastVideoTime {
                        // Audio ended earlier than video; pad silence to match video length
                        self.appendSilence(from: self.lastAudioTime, to: self.lastVideoTime, input: aInput)
                    }
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
