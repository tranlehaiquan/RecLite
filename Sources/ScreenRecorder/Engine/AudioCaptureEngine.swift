import Foundation
import AVFoundation
import Accelerate

/// Manages microphone capture with live audio level metering
public final class AudioCaptureEngine: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let audioQueue = DispatchQueue(label: "com.screenrecorder.audioQueue", qos: .userInitiated)
    
    public var onAudioSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    public var onAudioLevelUpdate: (@Sendable (Float) -> Void)?
    
    public var isMuted: Bool = false
    public private(set) var isRunning: Bool = false
    
    // MARK: - Lifecycle
    
    public func start() throws {
        guard !isRunning else { return }
        
        let session = AVCaptureSession()
        
        guard let micDevice = AVCaptureDevice.default(for: .audio) else {
            throw NSError(domain: "AudioCaptureEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone device found"])
        }
        
        let micInput = try AVCaptureDeviceInput(device: micDevice)
        if session.canAddInput(micInput) {
            session.addInput(micInput)
        } else {
            throw NSError(domain: "AudioCaptureEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add microphone input to session"])
        }
        
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw NSError(domain: "AudioCaptureEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not add microphone output to session"])
        }
        
        session.startRunning()
        self.captureSession = session
        self.audioOutput = output
        self.isRunning = true
    }
    
    public func stop() {
        guard isRunning else { return }
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        isRunning = false
        onAudioLevelUpdate?(0.0)
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioCaptureEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isMuted else {
            onAudioLevelUpdate?(0.0)
            return
        }
        
        // Forward sample buffer to video writer
        onAudioSampleBuffer?(sampleBuffer)
        
        // Calculate audio RMS level for visual meter
        calculateAudioLevel(from: sampleBuffer)
    }
    
    private func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == noErr, let rawData = dataPointer, totalLength > 0 else { return }
        
        // Treat as 16-bit linear PCM or Float32
        var rms: Float = 0.0
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let floatCount = totalLength / MemoryLayout<Float>.size
            rawData.withMemoryRebound(to: Float.self, capacity: floatCount) { floatBuffer in
                vDSP_rmsqv(floatBuffer, 1, &rms, vDSP_Length(floatCount))
            }
        } else {
            let int16Count = totalLength / MemoryLayout<Int16>.size
            rawData.withMemoryRebound(to: Int16.self, capacity: int16Count) { intBuffer in
                var floatArray = [Float](repeating: 0, count: int16Count)
                vDSP_vflt16(intBuffer, 1, &floatArray, 1, vDSP_Length(int16Count))
                var divisor: Float = 32768.0
                vDSP_vsdiv(floatArray, 1, &divisor, &floatArray, 1, vDSP_Length(int16Count))
                vDSP_rmsqv(floatArray, 1, &rms, vDSP_Length(int16Count))
            }
        }
        
        // Clamp and normalize level between 0.0 and 1.0
        let normalizedLevel = min(1.0, max(0.0, rms * 4.0))
        onAudioLevelUpdate?(normalizedLevel)
    }
}
