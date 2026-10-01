import SwiftUI
import ScreenCaptureKit
import AppKit

/// Zoom-style popup window view for selecting a window or display to record
public struct WindowPickerView: View {
    @ObservedObject var appState: AppState
    
    public enum PickerTab: String, CaseIterable, Identifiable {
        case windows = "Windows"
        case screens = "Screens"
        public var id: String { rawValue }
    }
    
    @State private var selectedTab: PickerTab = .windows
    @State private var searchText: String = ""
    @State private var selectedWindow: SCWindow? = nil
    @State private var selectedDisplayID: CGDirectDisplayID? = nil
    @State private var windowThumbnails: [CGWindowID: NSImage] = [:]
    @State private var displayThumbnails: [CGDirectDisplayID: NSImage] = [:]
    @State private var hoveredWindowID: CGWindowID? = nil
    @State private var hoveredDisplayID: CGDirectDisplayID? = nil
    @State private var isRefreshing: Bool = false
    
    @State private var lastClickTime: Date = .distantPast
    @State private var lastClickedWindowID: CGWindowID? = nil
    @State private var lastClickedDisplayID: CGDirectDisplayID? = nil
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    // MARK: - Filtered Sources
    
    private var filteredWindows: [SCWindow] {
        let windows = appState.availableWindows
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return windows
        }
        return windows.filter { win in
            let app = win.owningApplication?.applicationName.lowercased() ?? ""
            let title = win.title?.lowercased() ?? ""
            return app.contains(trimmed) || title.contains(trimmed)
        }
    }
    
    private var filteredDisplays: [SCDisplay] {
        return appState.availableDisplays
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            
            Divider()
            
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                if selectedTab == .windows {
                    windowsGridView
                } else {
                    screensGridView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            footerBar
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear {
            initializeSelection()
            loadThumbnails()
        }
        .onChange(of: appState.availableWindows.count) { _, _ in
            loadThumbnails()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text("Select Window to Record")
                    .font(.system(size: 15, weight: .bold))
                Text("Choose an open window or screen to capture")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Tab Switcher (Windows vs Screens)
            Picker("Mode", selection: $selectedTab) {
                Label("Windows (\(appState.availableWindows.count))", systemImage: "macwindow")
                    .tag(PickerTab.windows)
                Label("Screens (\(appState.availableDisplays.count))", systemImage: "display")
                    .tag(PickerTab.screens)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            
            // Search Field
            if selectedTab == .windows {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField("Search windows...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .frame(width: 170)
            }
            
            // Refresh Button
            Button(action: refreshSources) {
                Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .buttonStyle(.bordered)
            .help("Refresh open windows")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Windows Grid View
    
    private var windowsGridView: some View {
        Group {
            if filteredWindows.isEmpty {
                emptyWindowsView
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(filteredWindows, id: \.windowID) { window in
                            windowCard(window)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    // MARK: - Screens Grid View
    
    private var screensGridView: some View {
        Group {
            if filteredDisplays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Displays Detected")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(filteredDisplays, id: \.displayID) { display in
                            displayCard(display)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    // MARK: - Window Card
    
    private func windowCard(_ window: SCWindow) -> some View {
        let isSelected = (selectedWindow?.windowID == window.windowID)
        let isHovered = (hoveredWindowID == window.windowID)
        let appName = window.owningApplication?.applicationName ?? "Application"
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayTitle = title.isEmpty ? appName : title
        let appIcon = getAppIcon(for: window)
        let thumbnail = windowThumbnails[CGWindowID(window.windowID)]
        
        return VStack(spacing: 8) {
            // Preview Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
                
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Fallback when thumbnail is generating
                    VStack(spacing: 8) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.2), radius: 3)
                        
                        Text(appName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Resolution Pill (Bottom-Right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(window.frame.width)) × \(Int(window.frame.height))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
                
                // Selection Checkmark Badge (Top-Right, Zoom style)
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: Color.blue.opacity(0.5), radius: 4)
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 135)
            
            // App Icon & Info Row
            HStack(spacing: 8) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(displayTitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color(nsColor: .controlBackgroundColor).opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.blue : (isHovered ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12)),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovered in
            hoveredWindowID = hovered ? window.windowID : nil
            if hovered {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture {
            handleWindowClick(window)
        }
        .help("Click to select, double-click to record immediately")
    }
    
    // MARK: - Display Card
    
    private func displayCard(_ display: SCDisplay) -> some View {
        let isSelected = (selectedDisplayID == display.displayID)
        let isHovered = (hoveredDisplayID == display.displayID)
        let thumbnail = displayThumbnails[display.displayID]
        let isMain = (display.displayID == CGMainDisplayID())
        let title = isMain ? "Main Display" : "Display \(display.displayID)"
        
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
                
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 38))
                            .foregroundColor(.secondary)
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(display.width) × \(display.height)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .cornerRadius(4)
                            .padding(6)
                    }
                }
                
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: Color.blue.opacity(0.5), radius: 4)
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 150)
            
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(display.width) × \(display.height) Points")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color(nsColor: .controlBackgroundColor).opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? Color.blue : (isHovered ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12)),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .contentShape(Rectangle())
        .onHover { hovered in
            hoveredDisplayID = hovered ? display.displayID : nil
            if hovered {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture {
            handleDisplayClick(display)
        }
        .help("Click to select, double-click to record immediately")
    }
    
    // MARK: - Empty State
    
    private var emptyWindowsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if !searchText.isEmpty {
                Text("No windows match \"\(searchText)\"")
                    .font(.system(size: 15, weight: .semibold))
                
                Button("Clear Search") {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            } else {
                Text("No Open Windows Detected")
                    .font(.system(size: 15, weight: .semibold))
                
                Text("Make sure application windows are open on your desktop and Screen Recording permission is granted.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                
                HStack(spacing: 12) {
                    Button("Refresh Windows") {
                        refreshSources()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if !appState.permissions.hasScreenRecordingPermission {
                        Button("Open System Settings") {
                            appState.permissions.openScreenRecordingSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack(spacing: 14) {
            // Selected item info summary
            HStack(spacing: 8) {
                if selectedTab == .windows, let win = selectedWindow {
                    let appIcon = getAppIcon(for: win)
                    let appName = win.owningApplication?.applicationName ?? "Application"
                    let title = win.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("Selected:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(appName)
                                .font(.system(size: 11, weight: .bold))
                        }
                        if !title.isEmpty && title != appName {
                            Text(title)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if selectedTab == .screens, let dispID = selectedDisplayID {
                    Image(systemName: "display")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    
                    Text("Selected: \(dispID == CGMainDisplayID() ? "Main Display" : "Display \(dispID)")")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Select a window or screen above to begin")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            
            Spacer()
            
            // Cancel Button
            Button("Cancel") {
                appState.cancelWindowSelection()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            
            // Select Only Button (Closes picker and sets window in Floating Bar)
            Button("Select") {
                confirmSelectionOnly()
            }
            .buttonStyle(.bordered)
            .disabled(!canConfirm)
            
            // Primary Action Button (Record Now)
            Button(action: confirmAndStartRecording) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(selectedTab == .windows ? "Record Window" : "Record Screen")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!canConfirm)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Actions & Helpers
    
    private var canConfirm: Bool {
        if selectedTab == .windows {
            return selectedWindow != nil
        } else {
            return selectedDisplayID != nil
        }
    }
    
    private func initializeSelection() {
        if let current = appState.selectedWindow {
            selectedWindow = current
        } else {
            selectedWindow = appState.availableWindows.first
        }
        selectedDisplayID = appState.selectedDisplayID
    }
    
    private func handleWindowClick(_ window: SCWindow) {
        let now = Date()
        if lastClickedWindowID == window.windowID && now.timeIntervalSince(lastClickTime) < 0.35 {
            // Double click -> Start recording immediately
            selectedWindow = window
            confirmAndStartRecording()
        } else {
            selectedWindow = window
            lastClickedWindowID = window.windowID
            lastClickTime = now
        }
    }
    
    private func handleDisplayClick(_ display: SCDisplay) {
        let now = Date()
        if lastClickedDisplayID == display.displayID && now.timeIntervalSince(lastClickTime) < 0.35 {
            selectedDisplayID = display.displayID
            confirmAndStartRecording()
        } else {
            selectedDisplayID = display.displayID
            lastClickedDisplayID = display.displayID
            lastClickTime = now
        }
    }
    
    private func confirmSelectionOnly() {
        if selectedTab == .windows, let win = selectedWindow {
            appState.selectWindowOnly(win)
        } else if selectedTab == .screens, let dispID = selectedDisplayID {
            appState.selectDisplayOnly(dispID)
        }
    }
    
    private func confirmAndStartRecording() {
        if selectedTab == .windows, let win = selectedWindow {
            appState.selectWindowAndStartRecording(win)
        } else if selectedTab == .screens, let dispID = selectedDisplayID {
            appState.selectDisplayAndStartRecording(dispID)
        }
    }
    
    private func refreshSources() {
        isRefreshing = true
        appState.refreshAvailableSources()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                loadThumbnails()
                isRefreshing = false
            }
        }
    }
    
    private func loadThumbnails() {
        let windowsToCapture = appState.availableWindows
        let displaysToCapture = appState.availableDisplays
        
        Task.detached(priority: .userInitiated) {
            // 1. Capture window thumbnails
            for win in windowsToCapture {
                let winID = CGWindowID(win.windowID)
                if let cgImg = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    winID,
                    [.boundsIgnoreFraming, .bestResolution]
                ) {
                    let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                    await MainActor.run {
                        self.windowThumbnails[winID] = nsImg
                    }
                }
            }
            
            // 2. Capture display thumbnails
            for disp in displaysToCapture {
                let dispID = disp.displayID
                if let cgImg = CGDisplayCreateImage(dispID) {
                    let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                    await MainActor.run {
                        self.displayThumbnails[dispID] = nsImg
                    }
                }
            }
        }
    }
    
    private func getAppIcon(for window: SCWindow) -> NSImage {
        if let pid = window.owningApplication?.processID,
           let app = NSRunningApplication(processIdentifier: pid),
           let icon = app.icon {
            return icon
        }
        if let bundleID = window.owningApplication?.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage()
    }
}
