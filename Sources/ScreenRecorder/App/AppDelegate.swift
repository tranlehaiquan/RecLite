import Cocoa
import SwiftUI
import ScreenCaptureKit
import Combine

/// NSPanel subclass that allows borderless panels to become key window and receive keyboard events
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// NSHostingView subclass that accepts mouse clicks immediately even when the panel is inactive or not the key window
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// Hosting view for the floating control bar with native right-click context menu
final class FloatingBarHostingView: FirstMouseHostingView<FloatingControlBarView> {
    weak var appDelegate: AppDelegate?
    override func menu(for event: NSEvent) -> NSMenu? {
        return appDelegate?.buildFloatingBarContextMenu()
    }
}

/// Hosting view for the recording HUD with native right-click context menu
final class RecordingHUDHostingView: FirstMouseHostingView<RecordingHUDView> {
    weak var appDelegate: AppDelegate?
    override func menu(for event: NSEvent) -> NSMenu? {
        return appDelegate?.buildHUDContextMenu()
    }
}

/// Transparent overlay on NSStatusBarButton that captures left-click and secondary/right-click with 100% reliability
final class StatusItemOverlayView: NSView {
    weak var appDelegate: AppDelegate?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            appDelegate?.showStatusContextMenu()
        } else {
            (superview as? NSStatusBarButton)?.isHighlighted = true
            super.mouseDown(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        (superview as? NSStatusBarButton)?.isHighlighted = false
        let pointInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(pointInView) {
            if event.modifierFlags.contains(.control) {
                appDelegate?.showStatusContextMenu()
            } else {
                appDelegate?.handleStatusBarLeftClick()
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        (superview as? NSStatusBarButton)?.isHighlighted = true
    }
    
    override func rightMouseUp(with event: NSEvent) {
        (superview as? NSStatusBarButton)?.isHighlighted = false
        let pointInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(pointInView) {
            appDelegate?.showStatusContextMenu()
        }
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return appDelegate?.buildStatusMenu()
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    
    public var appState: AppState = .shared
    private var cancellables = Set<AnyCancellable>()
    
    // Windows / Panels
    private var floatingBarPanel: NSPanel?
    private var areaSelectionPanel: NSPanel?
    private var windowSelectionPanel: NSWindow?
    private var countdownPanel: NSPanel?
    private var recordingHUDPanel: NSPanel?
    private var areaRecordingFramePanel: NSPanel?
    private var completionPanel: NSPanel?
    private var screenshotPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var installWindow: NSWindow?
    
    // Menu Bar Status Item
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // App is accessory / floating agent
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false
        
        setupStatusBar()
        setupFloatingBarPanel()
        setupCountdownPanel()
        setupRecordingHUDPanel()
        setupAreaSelectionPanel()
        setupWindowSelectionPanel()
        setupAreaRecordingFramePanel()
        setupCompletionPanel()
        setupScreenshotPanel()
        
        observeStateChanges()
        
        // Start Global Keyboard Shortcuts Monitoring
        HotkeyManager.shared.startMonitoring()
        
        // Initial presentation
        showFloatingBar()
        
        // Prompt user to drag & drop / move app to /Applications if running outside /Applications
        if AppInstaller.shared.shouldPromptForInstallation() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showInstallPromptWindow()
            }
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "RecLite")
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        
        // Add transparent overlay to guarantee 100% reliable left/right/control click handling
        let overlay = StatusItemOverlayView(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.appDelegate = self
        button.addSubview(overlay)
    }
    
    @objc public func handleStatusBarLeftClick() {
        if appState.recordingState.isRecordingOrPaused {
            appState.stopRecording()
        } else {
            toggleFloatingBar()
        }
    }
    
    @objc private func statusBarButtonClicked() {
        handleStatusBarLeftClick()
    }
    
    @objc public func toggleFloatingBar() {
        guard let panel = floatingBarPanel else { return }
        if panel.isVisible {
            hideFloatingBar()
        } else {
            showFloatingBar()
        }
    }
    
    @objc public func showStatusContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = buildStatusMenu()
        button.isHighlighted = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        button.isHighlighted = false
    }
    
    public func buildStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "RecLite")
        let settings = AppSettings.shared
        
        if appState.recordingState.isRecordingOrPaused {
            let stopShortcut = settings.shortcutStartStop
            let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecordingAction), keyEquivalent: stopShortcut.keyEquivalent)
            stopItem.keyEquivalentModifierMask = stopShortcut.modifierFlags
            stopItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            stopItem.target = self
            menu.addItem(stopItem)

            let pauseShortcut = settings.shortcutPauseResume
            let isPaused = appState.recordingState.isPaused
            let pauseItem = NSMenuItem(title: isPaused ? "Resume Recording" : "Pause Recording", action: #selector(togglePauseAction), keyEquivalent: pauseShortcut.keyEquivalent)
            pauseItem.keyEquivalentModifierMask = pauseShortcut.modifierFlags
            pauseItem.image = NSImage(systemSymbolName: isPaused ? "play.circle" : "pause.circle", accessibilityDescription: nil)
            pauseItem.target = self
            menu.addItem(pauseItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        let barVisible = floatingBarPanel?.isVisible == true
        let toggleBarTitle = barVisible ? "Hide Control Bar" : "Show Control Bar"
        let toggleShortcut = settings.shortcutToggleBar
        let toggleBarItem = NSMenuItem(title: toggleBarTitle, action: #selector(toggleFloatingBar), keyEquivalent: toggleShortcut.keyEquivalent)
        toggleBarItem.keyEquivalentModifierMask = toggleShortcut.modifierFlags
        toggleBarItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        toggleBarItem.target = self
        menu.addItem(toggleBarItem)
        
        let folderItem = NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "o")
        folderItem.keyEquivalentModifierMask = [.command, .shift]
        folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderItem.target = self
        menu.addItem(folderItem)
        
        if !AppInstaller.shared.isInstalledInApplicationsFolder {
            menu.addItem(NSMenuItem.separator())
            let installItem = NSMenuItem(title: "Move to Applications Folder…", action: #selector(showInstallPromptWindow), keyEquivalent: "")
            installItem.image = NSImage(systemSymbolName: "arrow.down.app", accessibilityDescription: nil)
            installItem.target = self
            menu.addItem(installItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        let aboutItem = NSMenuItem(title: "About RecLite", action: #selector(openAboutPanel), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit RecLite", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    public func buildFloatingBarContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Floating Bar Context")
        
        let hideBarItem = NSMenuItem(title: "Hide Control Bar", action: #selector(hideFloatingBar), keyEquivalent: "")
        hideBarItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        hideBarItem.target = self
        menu.addItem(hideBarItem)
        
        let folderItem = NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "")
        folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderItem.target = self
        menu.addItem(folderItem)
        
        if !AppInstaller.shared.isInstalledInApplicationsFolder {
            menu.addItem(NSMenuItem.separator())
            let installItem = NSMenuItem(title: "Move to Applications Folder…", action: #selector(showInstallPromptWindow), keyEquivalent: "")
            installItem.image = NSImage(systemSymbolName: "arrow.down.app", accessibilityDescription: nil)
            installItem.target = self
            menu.addItem(installItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: "")
        prefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        let aboutItem = NSMenuItem(title: "About RecLite", action: #selector(openAboutPanel), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit RecLite", action: #selector(quitApp), keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    public func buildHUDContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Recording HUD")
        
        let isCollapsed = appState.isHUDCollapsed
        let toggleCollapseItem = NSMenuItem(
            title: isCollapsed ? "Expand HUD" : "Collapse HUD",
            action: #selector(toggleHUDCollapsedAction),
            keyEquivalent: ""
        )
        toggleCollapseItem.image = NSImage(systemSymbolName: isCollapsed ? "chevron.left" : "chevron.right", accessibilityDescription: nil)
        toggleCollapseItem.target = self
        menu.addItem(toggleCollapseItem)
        
        let hideHUDItem = NSMenuItem(title: "Hide Floating HUD", action: #selector(hideHUDAction), keyEquivalent: "")
        hideHUDItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        hideHUDItem.target = self
        menu.addItem(hideHUDItem)
        
        menu.addItem(NSMenuItem.separator())

        let isPaused = appState.recordingState.isPaused
        let pauseItem = NSMenuItem(title: isPaused ? "Resume Recording" : "Pause Recording", action: #selector(togglePauseAction), keyEquivalent: "")
        pauseItem.image = NSImage(systemSymbolName: isPaused ? "play.circle" : "pause.circle", accessibilityDescription: nil)
        pauseItem.target = self
        menu.addItem(pauseItem)

        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecordingAction), keyEquivalent: "")
        stopItem.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
        stopItem.target = self
        menu.addItem(stopItem)
        
        let folderItem = NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "")
        folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        folderItem.target = self
        menu.addItem(folderItem)
        
        return menu
    }
    
    @objc private func stopRecordingAction() {
        appState.stopRecording()
    }

    @objc private func togglePauseAction() {
        appState.togglePause()
    }
    
    @objc private func toggleHUDCollapsedAction() {
        appState.toggleHUDCollapsed()
    }
    
    @objc private func hideHUDAction() {
        hideRecordingHUD()
    }
    
    @objc private func openRecordingsFolder() {
        let saveURL = appState.settings.saveDirectoryURL
        NSWorkspace.shared.open(saveURL)
    }
    
    @objc private func openPreferences() {
        openSettingsWindow()
    }
    
    @objc private func openAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "RecLite",
            .version: "1.0.0",
            .applicationVersion: "1.0.0",
            .credits: NSAttributedString(string: "Native high-performance screen recording for macOS with compact MP4 & HEVC encoding.")
        ]
        NSApp.orderFrontStandardAboutPanel(options)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Install Prompt Window
    
    @objc public func showInstallPromptWindow() {
        if let win = installWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Install RecLite"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.center()
        win.level = .floating
        win.isReleasedWhenClosed = false
        
        let view = InstallPromptView { [weak win] in
            win?.close()
        }
        let hostingView = NSHostingView(rootView: view)
        win.contentView = hostingView
        
        self.installWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
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
        case .paused(let elapsed):
            let total = Int(elapsed)
            button.title = String(format: " %02d:%02d [❚❚]", total / 60, total % 60)
            button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
        case .finalizing:
            button.title = " Saving..."
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Saving")
        default:
            button.title = ""
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenRecorder")
        }
    }
    
    // MARK: - Screen Discovery Helper
    
    private var targetScreen: NSScreen? {
        if let barScreen = floatingBarPanel?.screen {
            return barScreen
        }
        let mouseLoc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    // MARK: - Floating Control Bar Panel (macOS Cmd+Shift+5 style)
    
    private func setupFloatingBarPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu // Always above selection overlay
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Native shadow follows the rounded content shape and isn't clipped by the panel bounds
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Use FloatingBarHostingView so clicks register immediately and right-clicks pop up context menu
        let hostingView = FloatingBarHostingView(rootView: FloatingControlBarView(appState: appState))
        hostingView.appDelegate = self
        panel.contentView = hostingView
        
        self.floatingBarPanel = panel
    }
    
    private var hasPositionedFloatingBar = false
    
    @objc public func showFloatingBar() {
        guard let panel = floatingBarPanel else { return }
        
        // If already visible, do not reposition it (preserves user drag position)
        if panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        
        // Only set default bottom-center origin once; retain dragged position across hide/show
        if !hasPositionedFloatingBar {
            guard let screen = targetScreen ?? NSScreen.main else { return }
            panel.setContentSize(NSSize(width: 750, height: 60))
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (panel.frame.width / 2)
            let y = screenRect.minY + 40
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            hasPositionedFloatingBar = true
        }
        
        panel.orderFrontRegardless()
    }
    
    @objc public func hideFloatingBar() {
        floatingBarPanel?.orderOut(nil)
    }
    
    // MARK: - Area Selection Overlay Panel
    
    private func setupAreaSelectionPanel() {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        
        let panel = KeyablePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // High level directly below floating control bar (.popUpMenu), well above all applications
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        
        // Directly use pure AppKit AreaSelectionNSView (no NSHostingView layout recursion)
        let areaView = AreaSelectionNSView(appState: appState)
        panel.contentView = areaView
        
        self.areaSelectionPanel = panel
    }
    
    private func showAreaSelection() {
        guard let screen = targetScreen ?? NSScreen.main, let panel = areaSelectionPanel else { return }
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            appState.selectedDisplayID = screenNumber
        }
        panel.setFrame(screen.frame, display: true)
        if let areaView = panel.contentView as? AreaSelectionNSView {
            areaView.prepareForDisplay()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        // Ensure floating bar stays visible and interactable above the dimmed overlay
        floatingBarPanel?.orderFrontRegardless()
    }
    
    private func hideAreaSelection() {
        areaSelectionPanel?.orderOut(nil)
    }
    
    // MARK: - Window Selection Window (Zoom-style modal picker)
    
    private func setupWindowSelectionPanel() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Select Window to Record"
        win.minSize = NSSize(width: 660, height: 480)
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        
        let hostingView = NSHostingView(rootView: WindowPickerView(appState: appState))
        win.contentView = hostingView
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.appState.isShowingWindowSelection == true {
                    self?.appState.isShowingWindowSelection = false
                }
            }
        }
        
        self.windowSelectionPanel = win
    }
    
    private func showWindowSelection() {
        if windowSelectionPanel == nil {
            setupWindowSelectionPanel()
        }
        guard let win = windowSelectionPanel else { return }
        
        if let screen = targetScreen ?? NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (win.frame.width / 2)
            let y = screenRect.midY - (win.frame.height / 2)
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }
    
    private func hideWindowSelection() {
        windowSelectionPanel?.orderOut(nil)
    }
    
    // MARK: - Active Area Recording Frame Panel (Shows boundary during recording)
    
    private func setupAreaRecordingFramePanel() {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) - 1)
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // 100% click-through
        
        let hostingView = NSHostingView(rootView: AreaRecordingFrameView(appState: appState))
        panel.contentView = hostingView
        
        self.areaRecordingFramePanel = panel
    }
    
    private func showAreaRecordingFrame() {
        guard let screen = targetScreen ?? NSScreen.main, let panel = areaRecordingFramePanel else { return }
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }
    
    private func hideAreaRecordingFrame() {
        areaRecordingFramePanel?.orderOut(nil)
    }
    
    // MARK: - Countdown Panel (Centered 3-2-1 indicator)
    
    private func setupCountdownPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 140),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        
        let hostingView = NSHostingView(rootView: CountdownHUDView(appState: appState))
        panel.contentView = hostingView
        
        self.countdownPanel = panel
    }
    
    private func showCountdown() {
        guard let panel = countdownPanel, let screen = targetScreen ?? NSScreen.main else { return }
        panel.setContentSize(NSSize(width: 140, height: 140))
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - 70
        let y = screenRect.midY - 70
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }
    
    private func hideCountdown() {
        countdownPanel?.orderOut(nil)
    }
    
    // MARK: - Recording HUD Panel (Live indicator during recording)
    
    private func setupRecordingHUDPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 285, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        
        let hostingView = RecordingHUDHostingView(rootView: RecordingHUDView(appState: appState))
        hostingView.appDelegate = self
        panel.contentView = hostingView
        
        self.recordingHUDPanel = panel
    }
    
    private func showRecordingHUD() {
        guard let panel = recordingHUDPanel else { return }
        
        // If already visible, DO NOT reset origin (prevents snapping back while user drags!)
        if panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let initialWidth: CGFloat = 285
        let initialHeight: CGFloat = 44
        panel.setContentSize(NSSize(width: initialWidth, height: initialHeight))
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - initialWidth - 24
        let y = screenRect.maxY - initialHeight - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }
    
    public func hideRecordingHUD() {
        recordingHUDPanel?.orderOut(nil)
    }
    
    public func updateHUDSize(isCollapsed: Bool) {
        guard let panel = recordingHUDPanel, panel.isVisible else { return }
        guard let screen = panel.screen ?? targetScreen ?? NSScreen.main else { return }
        
        let targetSize = isCollapsed ? NSSize(width: 112, height: 36) : NSSize(width: 285, height: 44)
        let currentFrame = panel.frame
        
        let widthDiff = currentFrame.width - targetSize.width
        let heightDiff = currentFrame.height - targetSize.height
        
        // Pin top edge: origin.y is bottom in Cocoa, so new origin.y = currentFrame.origin.y + heightDiff
        let newY = currentFrame.origin.y + heightDiff
        
        // Pin to whichever side user placed it closer to
        let isNearRight = currentFrame.midX > screen.frame.midX
        let newX = isNearRight ? (currentFrame.origin.x + widthDiff) : currentFrame.origin.x
        
        let newFrame = NSRect(origin: NSPoint(x: newX, y: newY), size: targetSize)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }
    
    // MARK: - Completion Panel (Result card)
    
    private func setupCompletionPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        
        self.completionPanel = panel
    }
    
    private func showCompletionCard(result: RecordingResult) {
        guard let panel = completionPanel, let screen = targetScreen ?? NSScreen.main else { return }
        
        let autoCloseSeconds = Double(appState.settings.autoCloseNotificationSeconds)
        let view = CompletionCardView(result: result, autoCloseSeconds: autoCloseSeconds) { [weak self] in
            self?.appState.dismissResultSheet()
        }
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = 360
        let height: CGFloat = fittingSize.height > 50 ? fittingSize.height : 185
        panel.setContentSize(NSSize(width: width, height: height))
        
        let screenRect = screen.visibleFrame
        let x = screenRect.maxX - width - 24
        let y = screenRect.minY + 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }
    
    private func hideCompletionCard() {
        guard let panel = completionPanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
        }
    }
    
    // MARK: - Screenshot Thumbnail Panel

    private func setupScreenshotPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        self.screenshotPanel = panel
    }

    private func showScreenshotThumbnail(_ result: ScreenshotResult) {
        guard let panel = screenshotPanel, let screen = targetScreen ?? NSScreen.main else { return }

        let autoCloseSeconds = Double(appState.settings.autoCloseNotificationSeconds)
        let view = ScreenshotThumbnailView(result: result, autoCloseSeconds: autoCloseSeconds) { [weak self] in
            self?.hideScreenshotThumbnail()
        }
        // FirstMouseHostingView so click/drag work without activating RecLite first
        let hostingView = FirstMouseHostingView(rootView: view)
        panel.contentView = hostingView
        let size = hostingView.fittingSize
        panel.setContentSize(size)

        let screenRect = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: screenRect.maxX - size.width - 14, y: screenRect.minY + 14))

        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    private func hideScreenshotThumbnail() {
        guard let panel = screenshotPanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.0
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
        }
    }

    // MARK: - Settings Window
    
    public func openSettingsWindow() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 490),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "RecLite Preferences"
        win.center()
        win.isReleasedWhenClosed = false
        
        let hostingView = NSHostingView(rootView: SettingsView())
        win.contentView = hostingView
        
        self.settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private var lastRecordedCaseName: String?
    
    // MARK: - State Observation
    
    private func observeStateChanges() {
        appState.$recordingState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.updateStatusItem()
                
                let currentCase: String
                switch state {
                case .idle: currentCase = "idle"
                case .countingDown: currentCase = "countingDown"
                case .recording: currentCase = "recording"
                case .paused: currentCase = "paused"
                case .finalizing: currentCase = "finalizing"
                case .failed: currentCase = "failed"
                }
                
                // Prevent duplicate case transitions (e.g. 0.5s recording timer ticks)
                // from resetting window panels or snapping dragged positions back!
                guard currentCase != self.lastRecordedCaseName else { return }
                self.lastRecordedCaseName = currentCase
                
                switch state {
                case .idle:
                    self.hideCountdown()
                    self.hideRecordingHUD()
                    self.hideAreaRecordingFrame()
                    self.showFloatingBar()
                case .countingDown:
                    self.hideFloatingBar()
                    self.hideRecordingHUD()
                    self.showCountdown()
                    if self.appState.captureMode == .selectedArea || self.appState.captureMode == .selectedWindow {
                        self.showAreaRecordingFrame()
                    }
                case .recording:
                    self.hideFloatingBar()
                    self.hideCountdown()
                    self.showRecordingHUD()
                    if self.appState.captureMode == .selectedArea || self.appState.captureMode == .selectedWindow {
                        self.showAreaRecordingFrame()
                    }
                case .paused:
                    break
                case .finalizing:
                    self.hideAreaRecordingFrame()
                    self.updateStatusItem()
                case .failed(let msg):
                    self.hideCountdown()
                    self.hideRecordingHUD()
                    self.hideAreaRecordingFrame()
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
            
        appState.$isShowingWindowSelection
            .receive(on: RunLoop.main)
            .sink { [weak self] isShowing in
                if isShowing {
                    self?.showWindowSelection()
                } else {
                    self?.hideWindowSelection()
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
        
        appState.$lastScreenshot
            .receive(on: RunLoop.main)
            .sink { [weak self] screenshot in
                guard let screenshot = screenshot else { return }
                self?.showScreenshotThumbnail(screenshot)
            }
            .store(in: &cancellables)

        appState.$isShowingSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] isShowing in
                if isShowing {
                    self?.openSettingsWindow()
                    DispatchQueue.main.async {
                        self?.appState.isShowingSettings = false
                    }
                }
            }
            .store(in: &cancellables)
            
        appState.$isHUDCollapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] isCollapsed in
                self?.updateHUDSize(isCollapsed: isCollapsed)
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
            alert.informativeText = "ScreenRecorder needs permission to record your screen.\n\nIf you just enabled it in System Settings, macOS requires restarting the app to take effect."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit & Reopen App")
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                relaunchApp()
            } else if res == .alertSecondButtonReturn {
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
    
    private func relaunchApp() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
