import SwiftUI

/// Floating status bar / HUD displayed while recording is in progress or counting down
public struct RecordingHUDView: View {
    @ObservedObject var appState: AppState
    
    @State private var isBlinking: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            switch appState.recordingState {
            case .countingDown(let seconds):
                countdownView(seconds: seconds)
            case .recording(let elapsed, let bytesWritten):
                recordingBarView(elapsed: elapsed, bytesWritten: bytesWritten)
            case .finalizing:
                finalizingView
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Countdown View
    
    private func countdownView(seconds: Int) -> some View {
        VStack(spacing: 8) {
            Text("\(seconds)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 8)
            
            Button("Cancel") {
                appState.cancelCountdown()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.4))
            .clipShape(Capsule())
        }
        .frame(width: 140, height: 140)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 16)
    }
    
    // MARK: - Recording Bar View
    
    private func recordingBarView(elapsed: TimeInterval, bytesWritten: Int64) -> some View {
        HStack(spacing: 12) {
            // Blinking Red Dot
            Circle()
                .fill(Color.red)
                .frame(width: 11, height: 11)
                .opacity(isBlinking ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isBlinking)
                .onAppear { isBlinking = true }
            
            // Elapsed Time
            Text(formattedTime(elapsed))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Live File Size Badge
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                Text(FileSizeEstimator.formatBytes(bytesWritten))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            
            // Audio Level Meter (if audio is active)
            if appState.settings.audioMode != .none {
                HStack(spacing: 2) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    
                    // Audio VU Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .yellow, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(2, geo.size.width * CGFloat(appState.liveAudioLevel)))
                                .animation(.easeOut(duration: 0.1), value: appState.liveAudioLevel)
                        }
                    }
                    .frame(width: 36, height: 6)
                }
            }
            
            Divider()
                .frame(height: 16)
                .opacity(0.3)
            
            // Format Tag (e.g. MP4 • HEVC)
            Text("\(appState.settings.container.rawValue.uppercased())")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
            
            // Stop Button
            Button(action: {
                appState.stopRecording()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .shadow(color: Color.red.opacity(0.4), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
            Text("Optimizing & saving video...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
