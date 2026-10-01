import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AppKit

/// Primary application state orchestrator
@MainActor
public final class AppState: ObservableObject {
    
    public static let shared = AppState()
    
    // MARK: - Published Properties
    
    @Published public var captureMode: CaptureMode = .entireScreen
    @Published public var recordingState: RecordingState = .idle
    @Published public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var selectedWindow: SCWindow?
    @Published public var selectedCropRect: CGRect?
    @Published public var isMuted: Bool = false
    @Published public var liveAudioLevel: Float = 0.0
    @Published public var lastResult: RecordingResult?
    @Published public var isShowingResultSheet: Bool = false
    @Published public var isShowingSettings: Bool = false
    @Published public var availableDisplays: [SCDisplay] = []
    @Published public var availableWindows: [SCWindow] = []
    
    // UI states
    @Published public var liveElapsedTime: TimeInterval = 0
    @Published public var liveBytesWritten: Int64 = 0
    @Published public var isShowingAreaSelection: Bool = false
    @Published public var isShowingWindowSelection: Bool = false
    @Published public var isHUDCollapsed: Bool = false
    
    // MARK: - Internal Engines
    
    private let screenEngine = ScreenCaptureEngine()
    private let audioEngine = AudioCaptureEngine()
    private let audioMixer = AudioMixer()
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
            self.isShowingWindowSelection = false
        } else if mode == .selectedWindow {
            self.isShowingAreaSelection = false
            self.isShowingWindowSelection = true
            refreshAvailableSources()
        } else {
            self.isShowingAreaSelection = false
            self.isShowingWindowSelection = false
        }
    }
    
    public func cancelWindowSelection() {
        self.isShowingWindowSelection = false
        self.captureMode = .entireScreen
    }
    
    public func selectWindow(_ window: SCWindow) {
        self.selectedWindow = window
        self.isShowingWindowSelection = false
    }
    
    public func selectWindowOnly(_ window: SCWindow) {
        self.selectedWindow = window
        self.captureMode = .selectedWindow
        self.isShowingWindowSelection = false
    }
    
    public func selectDisplayOnly(_ displayID: CGDirectDisplayID) {
        self.selectedDisplayID = displayID
        self.captureMode = .entireScreen
        self.isShowingWindowSelection = false
    }
    
    public func selectWindowAndStartRecording(_ window: SCWindow) {
        selectWindowOnly(window)
        startRecording()
    }
    
    public func selectDisplayAndStartRecording(_ displayID: CGDirectDisplayID) {
        selectDisplayOnly(displayID)
        startRecording()
    }
    
    public func dismissResultSheet() {
        self.isShowingResultSheet = false
    }
    
    public func toggleHUDCollapsed() {
        isHUDCollapsed.toggle()
    }
    
    public func startRecording() {
        guard recordingState == .idle else { return }
        
        // Check screen recording permission first
        guard permissions.hasScreenRecordingPermission else {
            recordingState = .failed("Screen Recording permission is required. Please enable it in System Settings > Privacy & Security.")
            return
        }
        
        // Hide selection overlays before starting
        isShowingAreaSelection = false
        isShowingWindowSelection = false
        isHUDCollapsed = false
        
        let countdown = settings.countdownSeconds
        if countdown > 0 {
            startCountdown(seconds: countdown)
        } else {
            startActualRecording()
        }
    }
    
    public func startRecordingFlow() {
        startRecording()
    }
    
    public func toggleRecording() {
        if recordingState.isRecordingOrPaused {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startCountdown(seconds: Int) {
        countdownRemaining = seconds
        recordingState = .countingDown(remainingSeconds: seconds)
        
        // Pre-warm microphone during countdown if enabled
        let captureMic = (settings.audioMode == .microphone || settings.audioMode == .both)
        if captureMic && permissions.hasMicrophonePermission {
            try? audioEngine.start()
        }
        
        countdownTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.countdownRemaining -= 1
                if self.countdownRemaining > 0 {
                    self.recordingState = .countingDown(remainingSeconds: self.countdownRemaining)
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.startActualRecording()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }
    
    public func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        audioEngine.stop()
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
                
                // 1. Pre-warm and start Audio Engine FIRST if microphone is requested
                // Starting AVCaptureSession early prevents audio startup lag/silence
                if captureMic {
                    if !permissions.hasMicrophonePermission {
                        _ = await permissions.requestMicrophonePermission()
                    }
                    self.isMuted = false
                    self.audioEngine.isMuted = false
                    try audioEngine.start()
                } else {
                    self.isMuted = true
                    self.audioEngine.isMuted = true
                }
                
                // 2. Start Screen Stream to determine dimensions
                let dimensions = try await screenEngine.startCapture(
                    target: target,
                    fps: fpsValue,
                    resolutionScale: scale,
                    showCursor: cursor,
                    captureSystemAudio: captureSystem
                )
                
                // 3. Compute bitrate based on settings & resolution
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
                
                // 4. Initialize Video Writer
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
                
                // 5. Pipe Video Frames
                self.screenEngine.onVideoSampleBuffer = { [weak writer] sampleBuffer in
                    writer?.appendVideoSampleBuffer(sampleBuffer)
                }
                
                // 6. Pipe Audio Stream(s)
                if captureSystem && captureMic {
                    // Both System Audio & Microphone: pipe through AudioMixer
                    self.audioMixer.reset()
                    self.audioMixer.onMixedBuffer = { [weak writer] mixedBuffer in
                        writer?.appendAudioSampleBuffer(mixedBuffer)
                    }
                    self.screenEngine.onSystemAudioSampleBuffer = { [weak self] sampleBuffer in
                        self?.audioMixer.appendBuffer(sampleBuffer)
                    }
                    self.audioEngine.onAudioSampleBuffer = { [weak self] sampleBuffer in
                        self?.audioMixer.appendBuffer(sampleBuffer)
                    }
                } else if captureMic {
                    // Microphone only
                    self.audioEngine.onAudioSampleBuffer = { [weak writer] sampleBuffer in
                        writer?.appendAudioSampleBuffer(sampleBuffer)
                    }
                    self.screenEngine.onSystemAudioSampleBuffer = nil
                } else if captureSystem {
                    // System Audio only
                    self.screenEngine.onSystemAudioSampleBuffer = { [weak writer] sampleBuffer in
                        writer?.appendAudioSampleBuffer(sampleBuffer)
                    }
                    self.audioEngine.onAudioSampleBuffer = nil
                } else {
                    self.screenEngine.onSystemAudioSampleBuffer = nil
                    self.audioEngine.onAudioSampleBuffer = nil
                }
                
                // 7. Update State & Start Timers
                self.recordingStartTime = Date()
                self.liveElapsedTime = 0
                self.liveBytesWritten = 0
                self.recordingState = .recording(elapsed: 0, bytesWritten: 0)
                self.isShowingAreaSelection = false
                self.isShowingWindowSelection = false
                
                self.startElapsedTimer()
                
            } catch {
                handleRecordingError(error.localizedDescription)
            }
        }
    }
    
    private func startElapsedTimer() {
        timer?.invalidate()
        // Use .common mode so the timer keeps firing even while user interacts with the UI
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                let bytes = self.videoWriter?.bytesWritten ?? 0
                self.liveElapsedTime = elapsed
                self.liveBytesWritten = bytes
                self.recordingState = .recording(elapsed: elapsed, bytesWritten: bytes)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    /// Toggle microphone mute during recording without stopping capture session
    public func toggleMute() {
        isMuted.toggle()
        audioEngine.isMuted = isMuted
    }
    
    public func stopRecording() {
        guard recordingState.isRecordingOrPaused else { return }
        
        recordingState = .finalizing
        timer?.invalidate()
        timer = nil
        isHUDCollapsed = false
        
        if settings.audioMode == .both {
            audioMixer.flush()
        }
        audioEngine.stop()
        audioMixer.onMixedBuffer = nil
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
        isHUDCollapsed = false
        recordingState = .failed(message)
    }
    
    private func copyFileToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
