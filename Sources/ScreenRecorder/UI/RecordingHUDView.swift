import SwiftUI
import AppKit

/// Floating status bar / HUD displayed while recording is in progress.
/// Supports smooth native dragging anywhere on the screen and collapse to an ultra-compact mini pill.
public struct RecordingHUDView: View {
    @ObservedObject var appState: AppState
    
    @State private var isBlinking: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            switch appState.recordingState {
            case .recording(let elapsed, _):
                if appState.isHUDCollapsed {
                    collapsedBarView(elapsed: elapsed)
                } else {
                    fullBarView(elapsed: elapsed)
                }
            case .finalizing:
                finalizingView
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Collapsed Mini-Pill (Ultra-compact, frees screen space)
    
    private func collapsedBarView(elapsed: TimeInterval) -> some View {
        HStack(spacing: 6) {
            // Generous drag zone (entire left area)
            HStack(spacing: 6) {
                dragGrip
                blinkingDot
                Text(formattedTime(elapsed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .fixedSize()
            }
            .contentShape(Rectangle())
            .overlay(
                WindowDragHandle(onDoubleClick: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        appState.isHUDCollapsed = false
                    }
                })
            )
            .help("Drag to move HUD (Double-click to expand)")
            
            // Expand Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    appState.isHUDCollapsed = false
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Expand Controls (Double-click HUD)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .fixedSize()
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                WindowDragHandle(onDoubleClick: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        appState.isHUDCollapsed = false
                    }
                })
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
        .contextMenu {
            hudContextMenu
        }
    }
    
    // MARK: - Full Recording Bar View
    
    private func fullBarView(elapsed: TimeInterval) -> some View {
        HStack(spacing: 10) {
            // Generous Drag Zone: Grip + Blinking Dot + Elapsed Time (~110px wide drag area)
            HStack(spacing: 8) {
                dragGrip
                blinkingDot
                Text(formattedTime(elapsed))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .fixedSize()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .overlay(
                WindowDragHandle(onDoubleClick: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        appState.isHUDCollapsed = true
                    }
                })
            )
            .help("Drag anywhere on handle or timer to move HUD (Double-click to collapse)")
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Mic mute toggle — single circular icon button
            Button(action: {
                appState.toggleMute()
            }) {
                Image(systemName: appState.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(appState.isMuted ? .white.opacity(0.4) : .green)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(appState.isMuted ? Color.white.opacity(0.08) : Color.green.opacity(0.18))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(appState.isMuted ? "Unmute microphone" : "Mute microphone")
            
            // Stop Button
            Button(action: {
                appState.stopRecording()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.25, blue: 0.25), Color(red: 0.85, green: 0.15, blue: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shadow(color: Color.red.opacity(0.4), radius: 4)
            .fixedSize()
            .layoutPriority(2)
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Collapse Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    appState.isHUDCollapsed = true
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Collapse HUD (Double-click handle/timer to toggle)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .fixedSize()
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                WindowDragHandle(onDoubleClick: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        appState.toggleHUDCollapsed()
                    }
                })
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .contextMenu {
            hudContextMenu
        }
    }
    
    // MARK: - Components
    
    private var dragGrip: some View {
        HStack(spacing: 2) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(width: 22, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.12))
        )
    }
    
    private var blinkingDot: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .opacity(isBlinking ? 0.25 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isBlinking)
            .onAppear { isBlinking = true }
    }
    
    @ViewBuilder
    private var hudContextMenu: some View {
        Button(appState.isHUDCollapsed ? "Expand HUD" : "Collapse HUD") {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                appState.toggleHUDCollapsed()
            }
        }
        Button("Hide Floating HUD") {
            (NSApp.delegate as? AppDelegate)?.hideRecordingHUD()
        }
        Divider()
        Button("Stop Recording", role: .destructive) {
            appState.stopRecording()
        }
    }
    
    // MARK: - Finalizing View
    
    private var finalizingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Saving video...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fixedSize()
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12)
    }
    
    private func formattedTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - WindowDragHandle (AppKit 60fps Native Dragging)

public final class WindowDragNSView: NSView {
    public var onDoubleClick: (() -> Void)?
    
    override public var mouseDownCanMoveWindow: Bool { true }
    
    override public func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }
    
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

public struct WindowDragHandle: NSViewRepresentable {
    public var onDoubleClick: (() -> Void)?
    
    public init(onDoubleClick: (() -> Void)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }
    public func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}
