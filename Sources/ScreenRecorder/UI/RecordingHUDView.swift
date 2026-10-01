import SwiftUI

/// Floating status bar / HUD displayed while recording is in progress
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
                recordingBarView(elapsed: elapsed)
            case .finalizing:
                finalizingView
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Recording Bar View
    
    private func recordingBarView(elapsed: TimeInterval) -> some View {
        HStack(spacing: 12) {
            // Blinking Red Dot
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(isBlinking ? 0.25 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isBlinking)
                .onAppear { isBlinking = true }
            
            // Elapsed Time
            Text(formattedTime(elapsed))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize()
                .layoutPriority(2)
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Mic mute toggle — single circular icon button
            Button(action: {
                appState.toggleMute()
            }) {
                Image(systemName: appState.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(appState.isMuted ? .white.opacity(0.4) : .green)
                    .frame(width: 28, height: 28)
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
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.red)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shadow(color: Color.red.opacity(0.4), radius: 4)
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .fixedSize()
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
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
