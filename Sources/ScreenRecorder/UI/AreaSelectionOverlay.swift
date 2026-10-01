import SwiftUI
import AppKit

/// Interactive crop selection overlay window for custom area recording
public struct AreaSelectionOverlayView: View {
    @ObservedObject var appState: AppState
    
    @State private var rect: CGRect = CGRect(x: 200, y: 150, width: 800, height: 500)
    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingBody: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
        if let current = appState.selectedCropRect {
            _rect = State(initialValue: current)
        }
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background with cutout for the selection rect
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRect(rect)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                
                // Crop Rectangle with border & handles
                CropBoxView(
                    rect: $rect,
                    screenSize: geo.size,
                    onRectChange: { updated in
                        appState.selectedCropRect = updated
                    },
                    onRecord: {
                        appState.selectedCropRect = rect
                        appState.startRecordingFlow()
                    },
                    onCancel: {
                        appState.setCaptureMode(.entireScreen)
                    }
                )
            }
            .onAppear {
                if appState.selectedCropRect == nil {
                    // Default to center 60% of screen
                    let w = min(1280.0, geo.size.width * 0.7)
                    let h = min(720.0, geo.size.height * 0.7)
                    let x = (geo.size.width - w) / 2.0
                    let y = (geo.size.height - h) / 2.0
                    self.rect = CGRect(x: x, y: y, width: w, height: h)
                    appState.selectedCropRect = self.rect
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - CropBoxView

struct CropBoxView: View {
    @Binding var rect: CGRect
    let screenSize: CGSize
    let onRectChange: (CGRect) -> Void
    let onRecord: () -> Void
    let onCancel: () -> Void
    
    @GestureState private var bodyDragDelta: CGSize = .zero
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main draggable area
            Rectangle()
                .fill(Color.white.opacity(0.001)) // invisible hit target
                .frame(width: max(40, rect.width), height: max(40, rect.height))
                .border(Color.white, width: 2)
                .overlay(
                    // Subtle crosshair guides inside
                    ZStack {
                        Rectangle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        // Rule of thirds lines
                        HStack {
                            Spacer()
                            Divider().background(Color.white.opacity(0.15))
                            Spacer()
                            Divider().background(Color.white.opacity(0.15))
                            Spacer()
                        }
                        VStack {
                            Spacer()
                            Divider().background(Color.white.opacity(0.15))
                            Spacer()
                            Divider().background(Color.white.opacity(0.15))
                            Spacer()
                        }
                    }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            var newX = rect.origin.x + value.translation.width
                            var newY = rect.origin.y + value.translation.height
                            newX = max(0, min(newX, screenSize.width - rect.width))
                            newY = max(0, min(newY, screenSize.height - rect.height))
                            rect.origin = CGPoint(x: newX, y: newY)
                            onRectChange(rect)
                        }
                )
            
            // Corner & Edge Resize Handles
            ResizeHandle(x: rect.minX - 4, y: rect.minY - 4) { d in
                resize(dx: d.width, dy: d.height, isLeft: true, isTop: true)
            }
            ResizeHandle(x: rect.maxX - 6, y: rect.minY - 4) { d in
                resize(dx: d.width, dy: d.height, isLeft: false, isTop: true)
            }
            ResizeHandle(x: rect.minX - 4, y: rect.maxY - 6) { d in
                resize(dx: d.width, dy: d.height, isLeft: true, isTop: false)
            }
            ResizeHandle(x: rect.maxX - 6, y: rect.maxY - 6) { d in
                resize(dx: d.width, dy: d.height, isLeft: false, isTop: false)
            }
            
            // Dimension Badge on top edge
            HStack(spacing: 8) {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(aspectRatioString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
            .offset(x: rect.midX - 60, y: max(10, rect.minY - 32))
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                // Preset buttons
                Button("1080p") {
                    setDimensions(width: 1920, height: 1080)
                }
                .buttonStyle(PresetBadgeStyle())
                
                Button("720p") {
                    setDimensions(width: 1280, height: 720)
                }
                .buttonStyle(PresetBadgeStyle())
                
                Button("1:1") {
                    let side = min(rect.width, rect.height)
                    setDimensions(width: side, height: side)
                }
                .buttonStyle(PresetBadgeStyle())
                
                Divider()
                    .frame(height: 18)
                    .opacity(0.3)
                
                // Cancel
                Button("Cancel") {
                    onCancel()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                
                // Record
                Button(action: onRecord) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Record Area")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .offset(x: max(20, rect.midX - 160), y: min(screenSize.height - 60, rect.maxY + 14))
        }
    }
    
    private var aspectRatioString: String {
        guard rect.height > 0 else { return "" }
        let ratio = rect.width / rect.height
        if abs(ratio - (16.0 / 9.0)) < 0.05 { return "16:9" }
        if abs(ratio - (4.0 / 3.0)) < 0.05 { return "4:3" }
        if abs(ratio - 1.0) < 0.05 { return "1:1" }
        return String(format: "%.2f:1", ratio)
    }
    
    private func setDimensions(width: CGFloat, height: CGFloat) {
        let w = min(width, screenSize.width)
        let h = min(height, screenSize.height)
        var originX = rect.midX - (w / 2)
        var originY = rect.midY - (h / 2)
        originX = max(0, min(originX, screenSize.width - w))
        originY = max(0, min(originY, screenSize.height - h))
        self.rect = CGRect(x: originX, y: originY, width: w, height: h)
        onRectChange(rect)
    }
    
    private func resize(dx: CGFloat, dy: CGFloat, isLeft: Bool, isTop: Bool) {
        var newRect = rect
        if isLeft {
            let proposedW = newRect.width - dx
            if proposedW >= 100 {
                newRect.origin.x += dx
                newRect.size.width = proposedW
            }
        } else {
            let proposedW = newRect.width + dx
            if proposedW >= 100 {
                newRect.size.width = proposedW
            }
        }
        
        if isTop {
            let proposedH = newRect.height - dy
            if proposedH >= 100 {
                newRect.origin.y += dy
                newRect.size.height = proposedH
            }
        } else {
            let proposedH = newRect.height + dy
            if proposedH >= 100 {
                newRect.size.height = proposedH
            }
        }
        
        self.rect = newRect
        onRectChange(rect)
    }
}

// MARK: - ResizeHandle

struct ResizeHandle: View {
    let x: CGFloat
    let y: CGFloat
    let onDrag: (CGSize) -> Void
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .offset(x: x, y: y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onDrag(value.translation)
                    }
            )
    }
}

// MARK: - PresetBadgeStyle

struct PresetBadgeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.7 : 0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12))
            .cornerRadius(4)
    }
}
