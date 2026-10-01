import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// Mixes multiple audio streams (e.g. system audio and microphone) into a single continuous, time-aligned stereo PCM stream.
public final class AudioMixer: @unchecked Sendable {
    
    private let sampleRate: Double = 48000
    private var baseTime: CMTime?
    private var bufferStartSample: Int64 = 0
    private var accumulatedSamples: [Float] = [] // Interleaved stereo: L, R, L, R...
    private let lock = NSLock()
    
    public var onMixedBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    
    public init() {}
    
    /// Reset the mixer state for a new recording
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        baseTime = nil
        bufferStartSample = 0
        accumulatedSamples.removeAll(keepingCapacity: true)
    }
    
    /// Append an audio sample buffer from any source (Microphone or System Audio)
    public func appendBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        
        if baseTime == nil {
            baseTime = pts
            bufferStartSample = 0
        }
        guard let base = baseTime else { return }
        
        let diffSec = pts.seconds - base.seconds
        // Discard buffers that arrive more than 0.5s before current buffer head
        guard diffSec >= -0.5 else { return }
        
        let targetSampleIndex = max(0, Int64(round(diffSec * sampleRate)))
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }
        
        let stereo = extractStereoSamples(from: sampleBuffer)
        guard !stereo.isEmpty else { return }
        
        let requiredEndOffset = Int(targetSampleIndex - bufferStartSample) + numSamples
        let requiredSize = max(0, requiredEndOffset * 2)
        if accumulatedSamples.count < requiredSize {
            accumulatedSamples.append(contentsOf: [Float](repeating: 0, count: requiredSize - accumulatedSamples.count))
        }
        
        let startOffset = max(0, Int(targetSampleIndex - bufferStartSample))
        for i in 0..<numSamples {
            let outIdx = (startOffset + i) * 2
            let inIdx = i * 2
            if outIdx + 1 < accumulatedSamples.count && inIdx + 1 < stereo.count {
                accumulatedSamples[outIdx] += stereo[inIdx]
                accumulatedSamples[outIdx + 1] += stereo[inIdx + 1]
            }
        }
        
        // Emit chunks of 1024 frames if enough audio is buffered ahead
        let chunkSize = 1024
        while accumulatedSamples.count >= (chunkSize * 2 * 2) {
            emitChunk(count: chunkSize)
        }
    }
    
    /// Flushes all remaining buffered audio samples to the output callback
    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        let chunkSize = 1024
        while accumulatedSamples.count >= (chunkSize * 2) {
            emitChunk(count: chunkSize)
        }
        if accumulatedSamples.count > 0 {
            emitChunk(count: accumulatedSamples.count / 2)
        }
        accumulatedSamples.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func emitChunk(count: Int) {
        guard count > 0, let base = baseTime else { return }
        let subCount = count * 2
        var chunk = Array(accumulatedSamples.prefix(subCount))
        accumulatedSamples.removeFirst(subCount)
        
        // Soft-clamp samples to [-1.0, 1.0] to prevent clipping distortion
        for i in 0..<chunk.count {
            if chunk[i] > 1.0 { chunk[i] = 1.0 }
            else if chunk[i] < -1.0 { chunk[i] = -1.0 }
        }
        
        let chunkPTS = CMTimeAdd(base, CMTime(value: bufferStartSample, timescale: 48000))
        bufferStartSample += Int64(count)
        
        if let sbuf = makeSampleBuffer(from: chunk, count: count, pts: chunkPTS) {
            onMixedBuffer?(sbuf)
        }
    }
    
    private func extractStereoSamples(from sbuf: CMSampleBuffer) -> [Float] {
        guard let desc = CMSampleBufferGetFormatDescription(sbuf),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee,
              let block = CMSampleBufferGetDataBuffer(sbuf) else { return [] }
        
        var len = 0
        var ptr: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
        guard status == noErr, let p = ptr, len > 0 else { return [] }
        
        let numSamples = CMSampleBufferGetNumSamples(sbuf)
        guard numSamples > 0 else { return [] }
        var stereo = [Float](repeating: 0, count: numSamples * 2)
        
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if asbd.mChannelsPerFrame == 1 {
            // Mono -> Stereo upmix
            if isFloat {
                let f = p.withMemoryRebound(to: Float.self, capacity: numSamples) { UnsafeBufferPointer(start: $0, count: numSamples) }
                for i in 0..<numSamples {
                    let v = f[i]
                    stereo[i * 2] = v
                    stereo[i * 2 + 1] = v
                }
            } else {
                let ints = p.withMemoryRebound(to: Int16.self, capacity: numSamples) { UnsafeBufferPointer(start: $0, count: numSamples) }
                for i in 0..<numSamples {
                    let v = Float(ints[i]) / 32768.0
                    stereo[i * 2] = v
                    stereo[i * 2 + 1] = v
                }
            }
        } else if asbd.mChannelsPerFrame >= 2 {
            // Stereo
            if isFloat {
                let f = p.withMemoryRebound(to: Float.self, capacity: numSamples * 2) { UnsafeBufferPointer(start: $0, count: numSamples * 2) }
                for i in 0..<(numSamples * 2) {
                    stereo[i] = f[i]
                }
            } else {
                let ints = p.withMemoryRebound(to: Int16.self, capacity: numSamples * 2) { UnsafeBufferPointer(start: $0, count: numSamples * 2) }
                for i in 0..<(numSamples * 2) {
                    stereo[i] = Float(ints[i]) / 32768.0
                }
            }
        }
        return stereo
    }
    
    private func makeSampleBuffer(from samples: [Float], count: Int, pts: CMTime) -> CMSampleBuffer? {
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
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &stereoASBD,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &channelLayout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard formatStatus == noErr, let desc = formatDesc else { return nil }
        
        let byteCount = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        let blockStatus = samples.withUnsafeBytes { raw in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: nil,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &block
            )
        }
        guard blockStatus == noErr, let b = block else { return nil }
        
        _ = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: b, offsetIntoDestination: 0, dataLength: byteCount)
        }
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(count), timescale: 48000),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        
        var outBuf: CMSampleBuffer?
        let sbufStatus = CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: b,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleCount: count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outBuf
        )
        guard sbufStatus == noErr else { return nil }
        return outBuf
    }
}
