import SwiftUI

/// Floating countdown indicator displayed in the center of the screen
public struct CountdownHUDView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            if case .countingDown(let seconds) = appState.recordingState {
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
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                }
                .frame(width: 140, height: 140)
                .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 16)
            } else {
                EmptyView()
            }
        }
    }
}
