import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import AppKit

/// High performance ScreenCaptureKit engine
public final class ScreenCaptureEngine: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.screenrecorder.captureQueue", qos: .userInteractive)
    
    public var onVideoSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    public var onSystemAudioSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    
    public private(set) var isCapturing: Bool = false
    
    // MARK: - Available Content Discovery
    
    public static func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }
    
    public static func getAvailableWindows() async throws -> [SCWindow] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.filter { window in
            guard window.owningApplication?.processID != myPID else { return false }
            guard window.windowLayer == 0 else { return false }
            guard window.isOnScreen else { return false }
            let title = window.title ?? ""
            let appName = window.owningApplication?.applicationName ?? ""
            guard !title.isEmpty || !appName.isEmpty else { return false }
            return window.frame.width > 120 && window.frame.height > 120
        }
    }
    
    // MARK: - Start Capture
    
    public func startCapture(
        target: RecordingTarget,
        fps: Int,
        resolutionScale: ResolutionScale,
        showCursor: Bool,
        captureSystemAudio: Bool
    ) async throws -> CGSize {
        guard !isCapturing else { return .zero }
        
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let filter: SCContentFilter
        let originalSize: CGSize
        var cropRect: CGRect? = nil
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myWindows = shareableContent.windows.filter { $0.owningApplication?.processID == myPID }
        
        var scaleFactor: CGFloat = 1.0
        
        switch target {
        case .entireScreen(let displayID):
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) ?? shareableContent.displays.first else {
                throw NSError(domain: "ScreenCaptureEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Target display not found"])
            }
            filter = SCContentFilter(display: display, excludingWindows: myWindows)
            scaleFactor = NSScreen.screens.first(where: {
                let screenNum = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                return screenNum == displayID
            })?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            originalSize = CGSize(width: CGFloat(display.width) * scaleFactor, height: CGFloat(display.height) * scaleFactor)
            
        case .window(let windowID, _):
            guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
                throw NSError(domain: "ScreenCaptureEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Target window not found"])
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
            originalSize = CGSize(width: window.frame.size.width * scaleFactor, height: window.frame.size.height * scaleFactor)
            
        case .area(let rect, let displayID):
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) ?? shareableContent.displays.first else {
                throw NSError(domain: "ScreenCaptureEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Target display not found"])
            }
            filter = SCContentFilter(display: display, excludingWindows: myWindows)
            scaleFactor = NSScreen.screens.first(where: {
                let screenNum = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                return screenNum == displayID
            })?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            originalSize = CGSize(width: rect.size.width * scaleFactor, height: rect.size.height * scaleFactor)
            cropRect = rect
        }
        
        let targetDimensions = resolutionScale.targetDimensions(from: originalSize)
        
        // Configure stream
        let config = SCStreamConfiguration()
        let width = Int(targetDimensions.width) + (Int(targetDimensions.width) % 2)
        let height = Int(targetDimensions.height) + (Int(targetDimensions.height) % 2)
        config.width = max(2, width)
        config.height = max(2, height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showCursor
        config.capturesAudio = captureSystemAudio
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        
        if let crop = cropRect {
            config.sourceRect = crop
        }
        
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add video stream output
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        
        // Add audio stream output if system audio requested
        if captureSystemAudio {
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
        }
        
        try await newStream.startCapture()
        
        self.stream = newStream
        self.isCapturing = true
        
        return CGSize(width: config.width, height: config.height)
    }
    
    // MARK: - Stop Capture
    
    public func stopCapture() async throws {
        guard isCapturing, let activeStream = stream else { return }
        try await activeStream.stopCapture()
        self.stream = nil
        self.isCapturing = false
    }
}

// MARK: - SCStreamOutput & SCStreamDelegate

extension ScreenCaptureEngine: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let attachments = attachmentsArray.first,
               let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRawValue) {
                guard status == .complete else { return }
            }
            onVideoSampleBuffer?(sampleBuffer)
        case .audio, .microphone:
            onSystemAudioSampleBuffer?(sampleBuffer)
        @unknown default:
            break
        }
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.isCapturing = false
        onError?(error)
    }
}
