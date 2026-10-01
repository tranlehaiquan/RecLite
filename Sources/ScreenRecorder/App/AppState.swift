import Foundation
import SwiftUI
import AppKit
import ScreenCaptureKit
import AVFoundation

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // MARK: - Published State
    
    @Published public var captureMode: CaptureMode = .entireScreen
    @Published public var recordingState: RecordingState = .idle
    @Published public var selectedCropRect: CGRect? = nil
    @Published public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var selectedWindow: SCWindow? = nil
    
    @Published public var availableDisplays: [SCDisplay] = []
    @Published public var availableWindows: [SCWindow] = []
    
    @Published public var liveAudioLevel: Float = 0.0
    @Published public var liveBytesWritten: Int64 = 0
    @Published public var liveElapsedTime: TimeInterval = 0
    
    @Published public var lastResult: RecordingResult? = nil
    @Published public var isShowingSettings: Bool = false
    @Published public var isShowingResultSheet: Bool = false
    @Published public var isShowingAreaSelection: Bool = false
    
    // MARK: - Internal Engines
    
    private let screenEngine = ScreenCaptureEngine()
    private let audioEngine = AudioCaptureEngine()
    private var videoWriter: VideoWriterEngine?
    
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 0
    private var recordingStartTime: Date?
    
    public let settings = AppSettings.shared
    public let permissions = PermissionsManager.shared
    
    // MARK: - Initializer
    
    private init() {
        setupEngineCallbacks()
        refreshAvailableSources()
    }
    
    public func refreshAvailableSources() {
        Task {
            if let displays = try? await ScreenCaptureEngine.getAvailableDisplays() {
                self.availableDisplays = displays
                if let main = displays.first {
                    self.selectedDisplayID = main.displayID
                }
            }
            if let windows = try? await ScreenCaptureEngine.getAvailableWindows() {
                self.availableWindows = windows
            }
        }
    }
    
    private func setupEngineCallbacks() {
        audioEngine.onAudioLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.liveAudioLevel = level
            }
        }
        
        screenEngine.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleRecordingError(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Actions
    
    public func setCaptureMode(_ mode: CaptureMode) {
        self.captureMode = mode
        if mode == .selectedArea {
            self.isShowingAreaSelection = true
        } else {
            self.isShowingAreaSelection = false
        }
    }
    
    public func toggleRecording() {
        if recordingState.isRecordingOrPaused {
            stopRecording()
        } else {
            startRecordingFlow()
        }
    }
    
    public func startRecordingFlow() {
        guard !recordingState.isRecordingOrPaused else { return }
        
        // Verify permissions
        permissions.checkPermissions()
        guard permissions.hasScreenRecordingPermission else {
            permissions.requestScreenCapturePermission()
            return
        }
        
        // Handle countdown
        let countdown = settings.countdownSeconds
        if countdown > 0 {
            startCountdown(seconds: countdown)
        } else {
            startActualRecording()
        }
    }
    
    private func startCountdown(seconds: Int) {
        self.countdownRemaining = seconds
        self.recordingState = .countingDown(remainingSeconds: seconds)
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.countdownRemaining -= 1
                if self.countdownRemaining <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.startActualRecording()
                } else {
                    self.recordingState = .countingDown(remainingSeconds: self.countdownRemaining)
                }
            }
        }
    }
    
    public func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingState = .idle
    }
    
    private func startActualRecording() {
        Task {
            do {
                let target: RecordingTarget
                switch captureMode {
                case .entireScreen:
                    target = .entireScreen(displayID: selectedDisplayID)
                case .selectedWindow:
                    if let win = selectedWindow {
                        target = .window(windowID: win.windowID, windowTitle: win.title ?? "")
                    } else if let firstWin = availableWindows.first {
                        target = .window(windowID: firstWin.windowID, windowTitle: firstWin.title ?? "")
                    } else {
                        target = .entireScreen(displayID: selectedDisplayID)
                    }
                case .selectedArea:
                    let rect = selectedCropRect ?? CGRect(x: 100, y: 100, width: 800, height: 600)
                    target = .area(rect: rect, displayID: selectedDisplayID)
                }
                
                let captureAudio = (settings.audioMode != .none)
                let captureSystem = (settings.audioMode == .system || settings.audioMode == .both)
                let captureMic = (settings.audioMode == .microphone || settings.audioMode == .both)
                let fpsValue = settings.fps.rawValue
                let scale = settings.resolutionScale
                let cursor = settings.showCursor
                let containerVal = settings.container
                let codecVal = settings.codec
                let presetVal = settings.preset
                let customBitrate = settings.customBitrateMbps
                let outputURL = settings.generateOutputFileURL()
                
                // 1. Start Screen Stream to determine dimensions
                let dimensions = try await screenEngine.startCapture(
                    target: target,
                    fps: fpsValue,
                    resolutionScale: scale,
                    showCursor: cursor,
                    captureSystemAudio: captureSystem
                )
                
                // 2. Compute bitrate based on settings & resolution
                let bitrate: Int
                if presetVal == .custom {
                    bitrate = Int(customBitrate * 1_000_000.0)
                } else {
                    bitrate = presetVal.targetBitrate(
                        for: dimensions,
                        fps: fpsValue,
                        codec: codecVal
                    )
                }
                
                // 3. Initialize Video Writer
                let writer = VideoWriterEngine(
                    outputURL: outputURL,
                    container: containerVal,
                    codec: codecVal,
                    dimensions: dimensions,
                    fps: fpsValue,
                    bitrate: bitrate,
                    hasAudio: captureAudio
                )
                
                try writer.start()
                self.videoWriter = writer
                
                // Directly pipe frames and audio to writer (Sendable closures with captured Sendable writer)
                self.screenEngine.onVideoSampleBuffer = { [weak writer] sampleBuffer in
                    writer?.appendVideoSampleBuffer(sampleBuffer)
                }
                self.screenEngine.onSystemAudioSampleBuffer = { [weak writer] sampleBuffer in
                    writer?.appendAudioSampleBuffer(sampleBuffer)
                }
                self.audioEngine.onAudioSampleBuffer = { [weak writer] sampleBuffer in
                    writer?.appendAudioSampleBuffer(sampleBuffer)
                }
                
                // 4. Start Microphone if enabled
                if captureMic {
                    if !permissions.hasMicrophonePermission {
                        _ = await permissions.requestMicrophonePermission()
                    }
                    try audioEngine.start()
                }
                
                // 5. Update State & Start Timers
                self.recordingStartTime = Date()
                self.liveElapsedTime = 0
                self.liveBytesWritten = 0
                self.recordingState = .recording(elapsed: 0, bytesWritten: 0)
                self.isShowingAreaSelection = false
                
                self.startElapsedTimer()
                
            } catch {
                handleRecordingError(error.localizedDescription)
            }
        }
    }
    
    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                let bytes = self.videoWriter?.bytesWritten ?? 0
                self.liveElapsedTime = elapsed
                self.liveBytesWritten = bytes
                self.recordingState = .recording(elapsed: elapsed, bytesWritten: bytes)
            }
        }
    }
    
    public func stopRecording() {
        guard recordingState.isRecordingOrPaused else { return }
        
        recordingState = .finalizing
        timer?.invalidate()
        timer = nil
        
        audioEngine.stop()
        screenEngine.onVideoSampleBuffer = nil
        screenEngine.onSystemAudioSampleBuffer = nil
        audioEngine.onAudioSampleBuffer = nil
        
        Task {
            do {
                try await screenEngine.stopCapture()
                
                if let writer = videoWriter {
                    let result = try await writer.finish()
                    self.videoWriter = nil
                    
                    self.lastResult = result
                    self.recordingState = .idle
                    self.isShowingResultSheet = true
                    
                    // Post-recording actions
                    if self.settings.openInPlayerAfterRecord {
                        NSWorkspace.shared.open(result.fileURL)
                    }
                    if self.settings.copyToClipboardAfterRecord {
                        self.copyFileToPasteboard(result.fileURL)
                    }
                } else {
                    self.recordingState = .idle
                }
            } catch {
                handleRecordingError(error.localizedDescription)
            }
        }
    }
    
    private func handleRecordingError(_ message: String) {
        timer?.invalidate()
        timer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        audioEngine.stop()
        recordingState = .failed(message)
    }
    
    public func dismissResultSheet() {
        self.isShowingResultSheet = false
    }
    
    public func copyFileToPasteboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}
