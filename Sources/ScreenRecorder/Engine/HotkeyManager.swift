import Foundation
import AppKit
import Combine

/// Engine responsible for listening to global and local keyboard shortcuts and triggering recording actions.
@MainActor
public final class HotkeyManager: ObservableObject {
    public static let shared = HotkeyManager()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    @Published public private(set) var isMonitoring: Bool = false
    
    private init() {
        observeSettingsChanges()
    }
    
    /// Start monitoring global and local keyboard events
    public func startMonitoring() {
        stopMonitoring()
        
        guard AppSettings.shared.globalHotkeysEnabled else { return }
        
        // 1. Global event monitor (triggers when RecLite is inactive in the background)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
        }
        
        // 2. Local event monitor (triggers when RecLite windows/panels are active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                if self?.handleKeyEvent(event) == true {
                    // Event handled
                }
            }
            return event
        }
        
        isMonitoring = true
    }
    
    /// Stop monitoring keyboard events
    public func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isMonitoring = false
    }
    
    /// Handle an incoming key event and check against configured shortcuts
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let settings = AppSettings.shared
        guard settings.globalHotkeysEnabled else { return false }
        
        let appState = AppState.shared
        
        // Check Start / Stop Recording shortcut
        if settings.shortcutStartStop.matches(event: event) {
            triggerStartStopAction(appState: appState)
            return true
        }
        
        // Check Pause / Resume Recording shortcut
        if settings.shortcutPauseResume.matches(event: event) {
            triggerPauseResumeAction(appState: appState)
            return true
        }
        
        // Check Toggle Control Bar shortcut
        if settings.shortcutToggleBar.matches(event: event) {
            triggerToggleBarAction()
            return true
        }
        
        return false
    }
    
    private func triggerStartStopAction(appState: AppState) {
        if appState.recordingState.isRecordingOrPaused {
            appState.stopRecording()
        } else {
            appState.startRecordingFlow()
        }
    }
    
    private func triggerPauseResumeAction(appState: AppState) {
        // Toggle recording/paused if currently recording or paused
        if case .recording = appState.recordingState {
            // Note: Pause action if available in future, or stop
            appState.stopRecording()
        } else if appState.recordingState == .idle {
            appState.startRecordingFlow()
        }
    }
    
    private func triggerToggleBarAction() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.toggleFloatingBar()
        }
    }
    
    private func observeSettingsChanges() {
        AppSettings.shared.$globalHotkeysEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }
}
