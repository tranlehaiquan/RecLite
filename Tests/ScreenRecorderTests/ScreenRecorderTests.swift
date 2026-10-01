import Testing
import Foundation
import CoreGraphics
import AVFoundation
import CoreMedia
@testable import ScreenRecorder

@Suite("ScreenRecorder Video Formats & Compression Tests")
struct VideoFormatTests {
    
    @Test("VideoContainer file extensions and types")
    func testContainerExtensions() {
        #expect(VideoContainer.mp4.fileExtension == "mp4")
        #expect(VideoContainer.mov.fileExtension == "mov")
        #expect(VideoContainer.mp4.avFileType == .mp4)
        #expect(VideoContainer.mov.avFileType == .mov)
    }
    
    @Test("VideoCodec MP4 compatibility")
    func testCodecCompatibility() {
        #expect(VideoCodec.hevc.isMp4Compatible == true)
        #expect(VideoCodec.h264.isMp4Compatible == true)
        #expect(VideoCodec.proRes422.isMp4Compatible == false)
        
        #expect(VideoCodec.hevc.avCodecType == .hevc)
        #expect(VideoCodec.h264.avCodecType == .h264)
        #expect(VideoCodec.proRes422.avCodecType == .proRes422)
    }
    
    @Test("QualityPreset bitrate calculation scales with resolution and codec efficiency")
    func testQualityPresetBitrates() {
        let res1080p = CGSize(width: 1920, height: 1080)
        let res4k = CGSize(width: 3840, height: 2160)
        
        let h264Bitrate = QualityPreset.balanced.targetBitrate(for: res1080p, fps: 60, codec: .h264)
        let hevcBitrate = QualityPreset.balanced.targetBitrate(for: res1080p, fps: 60, codec: .hevc)
        
        // HEVC should use lower bitrate for equivalent high quality
        #expect(hevcBitrate < h264Bitrate)
        #expect(h264Bitrate >= 6_000_000)
        #expect(hevcBitrate >= 4_000_000)
        
        // 4K should scale higher than 1080p
        let h264Bitrate4k = QualityPreset.balanced.targetBitrate(for: res4k, fps: 60, codec: .h264)
        #expect(h264Bitrate4k > h264Bitrate)
        
        // Ultra Compact should be lower than High Quality
        let ultraCompact = QualityPreset.ultraCompact.targetBitrate(for: res1080p, fps: 60, codec: .hevc)
        let highQuality = QualityPreset.highQuality.targetBitrate(for: res1080p, fps: 60, codec: .hevc)
        #expect(ultraCompact < highQuality)
    }
    
    @Test("FileSizeEstimator calculates realistic weights and massive storage savings")
    func testFileSizeEstimator() {
        let res = CGSize(width: 1920, height: 1080)
        
        // 5 min recording estimation
        let hevcMbMin = FileSizeEstimator.megabytesPerMinute(
            resolution: res,
            fps: 60,
            codec: .hevc,
            preset: .ultraCompact
        )
        let defaultMacOsMovMbMin = FileSizeEstimator.defaultMacOsMovMegabytesPerMinute(
            resolution: res,
            fps: 60
        )
        
        #expect(hevcMbMin > 0)
        #expect(defaultMacOsMovMbMin > hevcMbMin)
        
        let savings = FileSizeEstimator.savingsPercentage(
            ourMbPerMin: hevcMbMin,
            macOsDefaultMbPerMin: defaultMacOsMovMbMin
        )
        // Savings should be between 80% and 98%
        #expect(savings >= 80)
        #expect(savings <= 99)
    }
    
    @Test("ResolutionScale downscaling preserves aspect ratio")
    func testResolutionScaling() {
        let original4k = CGSize(width: 3840, height: 2160)
        
        let native = ResolutionScale.native.targetDimensions(from: original4k)
        #expect(native.width == 3840 && native.height == 2160)
        
        let half = ResolutionScale.half.targetDimensions(from: original4k)
        #expect(half.width == 1920 && half.height == 1080)
        
        let p1080 = ResolutionScale.p1080.targetDimensions(from: original4k)
        #expect(p1080.width == 1920 && p1080.height == 1080)
        
        let p720 = ResolutionScale.p720.targetDimensions(from: original4k)
        #expect(p720.width == 1280 && p720.height == 720)
    }
    
    @Test("RecordingResult duration formatting and savings calculation")
    func testRecordingResult() {
        let tempURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let result = RecordingResult(
            fileURL: tempURL,
            duration: 125, // 2 min 5 sec
            fileSize: 15 * 1024 * 1024, // 15 MB
            dimensions: CGSize(width: 1920, height: 1080),
            codec: .hevc,
            container: .mp4
        )
        
        #expect(result.formattedDuration == "02:05")
        #expect(result.formattedFileSize.contains("MB"))
        #expect(result.storageSavedPercentage > 50)
    }
    
    @Test("Byte formatter")
    func testByteFormatting() {
        #expect(FileSizeEstimator.formatBytes(1024).contains("KB") || FileSizeEstimator.formatBytes(1024).contains("kB"))
        #expect(FileSizeEstimator.formatBytes(10 * 1024 * 1024).contains("MB"))
        #expect(FileSizeEstimator.formatBytes(2 * 1024 * 1024 * 1024).contains("GB"))
    }
    
    @Test("AppState capture mode switching and window selection state")
    @MainActor
    func testAppStateWindowSelection() {
        let appState = AppState.shared
        
        // Test switching to selectedWindow mode triggers window selection flag
        appState.setCaptureMode(.selectedWindow)
        #expect(appState.captureMode == .selectedWindow)
        #expect(appState.isShowingWindowSelection == true)
        
        // Test cancel
        appState.cancelWindowSelection()
        #expect(appState.isShowingWindowSelection == false)
        
        // Test selectDisplayOnly
        appState.selectDisplayOnly(1)
        #expect(appState.selectedDisplayID == 1)
        #expect(appState.captureMode == .entireScreen)
        #expect(appState.isShowingWindowSelection == false)
    }
    
    @Test("AppState HUD collapse state toggling")
    @MainActor
    func testAppStateHUDCollapse() {
        let appState = AppState.shared
        appState.isHUDCollapsed = false
        #expect(appState.isHUDCollapsed == false)
        
        appState.toggleHUDCollapsed()
        #expect(appState.isHUDCollapsed == true)
        
        appState.toggleHUDCollapsed()
        #expect(appState.isHUDCollapsed == false)
    }
    
    @Test("AudioMixer buffering and flushing")
    func testAudioMixerBufferingAndFlushing() {
        let mixer = AudioMixer()
        var receivedCount = 0
        mixer.onMixedBuffer = { buffer in
            receivedCount += 1
            let numSamples = CMSampleBufferGetNumSamples(buffer)
            #expect(numSamples > 0)
        }
        
        // Create a 1-channel mono PCM sample buffer (simulating mic)
        let sampleCount = 4800
        var monoASBD = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var monoFormatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &monoASBD, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &monoFormatDesc)
        
        var blockBuffer: CMBlockBuffer?
        let byteCount = sampleCount * MemoryLayout<Float>.size
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer!, offsetIntoDestination: 0, dataLength: byteCount)
        
        var timing = CMSampleTimingInfo(duration: CMTime(value: CMTimeValue(sampleCount), timescale: 48000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(allocator: nil, dataBuffer: blockBuffer!, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: monoFormatDesc, sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        
        #expect(sampleBuffer != nil)
        if let sbuf = sampleBuffer {
            mixer.appendBuffer(sbuf)
            mixer.flush()
            #expect(receivedCount > 0)
        }
        
        mixer.reset()
    }
}
