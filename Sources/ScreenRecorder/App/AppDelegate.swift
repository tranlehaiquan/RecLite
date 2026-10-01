import Cocoa
import SwiftUI
import ScreenCaptureKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    public var appState: AppState = .shared
    private var cancellables = Set<AnyCancellable>()
    
    // Windows / Panels
    private var floatingBarPanel: NSPanel?
    private var areaSelectionPanel: NSPanel?
    private var recordingHUDPanel: NSPanel?
    private var completionPanel: NSPanel?
    private var settingsWindow: NSWindow?
    
    // Menu Bar Status Item
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // App is accessory / floating agent
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusBar()
        setupFloatingBarPanel()
        setupRecordingHUDPanel()
        setupAreaSelectionPanel()
        setupCompletionPanel()
        
        observeStateChanges()
        
        // Initial presentation
        showFloatingBar()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenRecorder")
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    @objc private func statusBarButtonClicked() {
        if appState.recordingState.isRecordingOrPaused {
            appState.stopRecording()
        } else {
            showFloatingBar()
        }
    }
    
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        
        switch appState.recordingState {
        case .recording(let elapsed, _):
            let total = Int(elapsed)
            let m = total / 60
            let s = total % 60
            button.title = String(format: " %02d:%02d [■]", m, s)
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        case .finalizing:
            button.title = " Saving..."
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Saving")
        default:
            button.title = ""
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenRecorder")
        }
    }
    
    // MARK: - Floating Control Bar Panel (macOS Cmd+Shift+5 style)
    
    private func setupFloatingBarPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        
        let hostingView = NSHostingView(rootView: FloatingControlBarView(appState: appState))
        panel.contentView = hostingView
        
        self.floatingBarPanel = panel
    }
    
    public func showFloatingBar() {
        guard let panel = floatingBarPanel, let screen = NSScreen.main else { return }
        
        // Position at bottom center, just above the Dock
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (panel.frame.width / 2)
        let y = screenRect.minY + 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        
        panel.orderFront(nil)
    }
    
    public func hideFloatingBar() {
        floatingBarPanel?.orderOut(nil)
    }
    
    // MARK: - Area Selection Overlay Panel
    
    private func setupAreaSelectionPanel() {
        guard let screen = NSScreen.main else { return }
        
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        
        let hostingView = NSHostingView(rootView: AreaSelectionOverlayView(appState: appState))
        panel.contentView = hostingView
        
        self.areaSelectionPanel = panel
    }
    
    private func showAreaSelection() {
        if let screen = NSScreen.main, let panel = areaSelectionPanel {
            panel.setFrame(screen.frame, display: true)
            panel.orderFront(nil)
        }
    }
    
    private func hideAreaSelection() {
        areaSelectionPanel?.orderOut(nil)
    }
    
    // MARK: - Recording HUD Panel (Live indicator during recording)
    
    private func setupRecordingHUDPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 48),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        
        let hostingView = NSHostingView(rootView: RecordingHUDView(appState: appState))
        panel.contentView = hostingView
        
        self.recordingHUDPanel = panel
    }
    
    private func showRecordingHUD() {
        guard let panel = recordingHUDPanel, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - panel.frame.width - 24
        let y = screenRect.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }
    
    private func hideRecordingHUD() {
        recordingHUDPanel?.orderOut(nil)
    }
    
    // MARK: - Completion Panel (Result card)
    
    private func setupCompletionPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        
        self.completionPanel = panel
    }
    
    private func showCompletionCard(result: RecordingResult) {
        guard let panel = completionPanel, let screen = NSScreen.main else { return }
        
        let view = CompletionCardView(result: result) { [weak self] in
            self?.appState.dismissResultSheet()
        }
        panel.contentView = NSHostingView(rootView: view)
        
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - 360 - 24
        let y = screenRect.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }
    
    private func hideCompletionCard() {
        completionPanel?.orderOut(nil)
    }
    
    // MARK: - Settings Window
    
    public func openSettingsWindow() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ScreenRecorder Preferences"
        win.center()
        win.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: SettingsView())
        win.contentView = hostingView
        
        self.settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - State Observation
    
    private func observeStateChanges() {
        appState.$recordingState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.updateStatusItem()
                
                switch state {
                case .idle:
                    self.hideRecordingHUD()
                    self.showFloatingBar()
                case .countingDown:
                    self.hideFloatingBar()
                    self.showRecordingHUD()
                case .recording:
                    self.hideFloatingBar()
                    self.showRecordingHUD()
                case .paused:
                    break
                case .finalizing:
                    self.updateStatusItem()
                case .failed(let msg):
                    self.hideRecordingHUD()
                    self.showFloatingBar()
                    self.showErrorAlert(msg)
                }
            }
            .store(in: &cancellables)
        
        appState.$isShowingAreaSelection
            .receive(on: RunLoop.main)
            .sink { [weak self] isShowing in
                if isShowing {
                    self?.showAreaSelection()
                } else {
                    self?.hideAreaSelection()
                }
            }
            .store(in: &cancellables)
        
        appState.$isShowingResultSheet
            .receive(on: RunLoop.main)
            .sink { [weak self] isShowing in
                guard let self = self else { return }
                if isShowing, let res = self.appState.lastResult {
                    self.showCompletionCard(result: res)
                } else {
                    self.hideCompletionCard()
                }
            }
            .store(in: &cancellables)
        
        appState.$isShowingSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] isShowing in
                if isShowing {
                    self?.openSettingsWindow()
                    self?.appState.isShowingSettings = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        
        let isPermissionRelated = message.contains("-3801")
            || message.lowercased().contains("declined")
            || message.lowercased().contains("tcc")
            || message.lowercased().contains("permission")
            || !PermissionsManager.shared.hasScreenRecordingPermission
        
        if isPermissionRelated {
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "ScreenRecorder needs permission to record your screen and audio.\n\nPlease enable ScreenRecorder in:\nSystem Settings > Privacy & Security > Screen & System Audio Recording."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                PermissionsManager.shared.openScreenRecordingSystemSettings()
            }
        } else {
            alert.messageText = "Recording Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
