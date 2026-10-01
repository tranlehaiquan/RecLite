import SwiftUI
import AppKit

/// Non-interactive live recording frame indicating the exact area being captured
public struct AreaRecordingFrameView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        GeometryReader { geo in
            if let rect = appState.selectedCropRect {
                ZStack(alignment: .topLeading) {
                    // 1. Subtle dark drop shadow boundary
                    Rectangle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 3)
                        .frame(width: rect.width + 2, height: rect.height + 2)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // 2. High-visibility red recording frame
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    
                    // 3. Prominent corner L-brackets
                    CornerBrackets(rect: rect)
                    
                    // 4. Subtle "● REC" tag above or inside frame
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("REC")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(Int(rect.width))×\(Int(rect.height))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .offset(x: rect.minX, y: max(6, rect.minY - 24))
                }
            }
        }
        .allowsHitTesting(false)
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Corner L-Brackets

private struct CornerBrackets: View {
    let rect: CGRect
    let arm: CGFloat = 16
    let strokeWidth: CGFloat = 3
    
    var body: some View {
        Path { path in
            // Top-left
            path.move(to: CGPoint(x: rect.minX + arm, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + arm))
            
            // Top-right
            path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
            
            // Bottom-left
            path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
            
            // Bottom-right
            path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        }
        .stroke(Color.red, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
    }
}
