import SwiftUI
import AppKit

/// SwiftUI Representable wrapper for the native AppKit Area Selection View
public struct AreaSelectionOverlayView: NSViewRepresentable {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public func makeNSView(context: Context) -> AreaSelectionNSView {
        let view = AreaSelectionNSView(appState: appState)
        return view
    }
    
    public func updateNSView(_ nsView: AreaSelectionNSView, context: Context) {
        nsView.appState = appState
        if let crop = appState.selectedCropRect, crop != nsView.rect && !nsView.isDragging {
            nsView.rect = crop
            nsView.needsDisplay = true
        }
    }
}

// MARK: - Native AppKit Area Selection View (Exact macOS Replicate)

public final class AreaSelectionNSView: NSView {
    var appState: AppState
    var rect: CGRect = .zero
    
    // Dragging state
    private enum DragMode {
        case none
        case moving(startLocation: CGPoint, startOrigin: CGPoint)
        case resizing(handle: Handle, startLocation: CGPoint, startRect: CGRect)
        case creating(anchor: CGPoint)
    }
    
    private var dragMode: DragMode = .none
    var isDragging: Bool {
        if case .none = dragMode { return false }
        return true
    }
    
    enum Handle: CaseIterable {
        case topLeft, topCenter, topRight
        case leftCenter, rightCenter
        case bottomLeft, bottomCenter, bottomRight
        
        func point(for rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topCenter: return CGPoint(x: rect.midX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .leftCenter: return CGPoint(x: rect.minX, y: rect.midY)
            case .rightCenter: return CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomCenter: return CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
        
        func hitRect(for rect: CGRect) -> CGRect {
            let p = point(for: rect)
            return CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
        }
        
        var cursor: NSCursor {
            switch self {
            case .leftCenter, .rightCenter:
                return .resizeLeftRight
            case .topCenter, .bottomCenter:
                return .resizeUpDown
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                return .crosshair
            }
        }
    }
    
    private var trackingArea: NSTrackingArea?
    
    // Coordinates: Flipped so (0,0) is Top-Left, exactly matching ScreenCaptureKit
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    
    public init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        self.wantsLayer = true
        if let crop = appState.selectedCropRect {
            self.rect = crop
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if rect == .zero && bounds.width > 0 && bounds.height > 0 {
            initializeDefaultRect()
        }
    }
    
    public override func layout() {
        super.layout()
        if rect == .zero && bounds.width > 0 && bounds.height > 0 {
            initializeDefaultRect()
        }
    }
    
    private func initializeDefaultRect() {
        if let current = appState.selectedCropRect, current.width > 50 && current.height > 50 {
            self.rect = current
        } else {
            let w = min(960.0, bounds.width * 0.65)
            let h = min(540.0, bounds.height * 0.65)
            let x = (bounds.width - w) / 2.0
            let y = (bounds.height - h) / 2.0
            self.rect = CGRect(x: x, y: y, width: w, height: h)
            appState.selectedCropRect = self.rect
        }
        needsDisplay = true
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    // MARK: - Drawing (macOS Native Aesthetic)
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // 1. Dimmed full-screen backdrop with cutout for selection rect
        let backdrop = NSBezierPath(rect: bounds)
        backdrop.append(NSBezierPath(rect: rect))
        backdrop.windingRule = .evenOdd
        NSColor(white: 0.0, alpha: 0.45).setFill()
        backdrop.fill()
        
        guard rect.width > 1 && rect.height > 1 else { return }
        
        // 2. Rule-of-thirds subtle guide lines inside selection
        let thirdW = rect.width / 3.0
        let thirdH = rect.height / 3.0
        if thirdW > 50 && thirdH > 50 {
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: rect.minX + thirdW, y: rect.minY))
            grid.line(to: NSPoint(x: rect.minX + thirdW, y: rect.maxY))
            grid.move(to: NSPoint(x: rect.minX + 2 * thirdW, y: rect.minY))
            grid.line(to: NSPoint(x: rect.minX + 2 * thirdW, y: rect.maxY))
            
            grid.move(to: NSPoint(x: rect.minX, y: rect.minY + thirdH))
            grid.line(to: NSPoint(x: rect.maxX, y: rect.minY + thirdH))
            grid.move(to: NSPoint(x: rect.minX, y: rect.minY + 2 * thirdH))
            grid.line(to: NSPoint(x: rect.maxX, y: rect.minY + 2 * thirdH))
            
            NSColor(white: 1.0, alpha: 0.12).setStroke()
            grid.lineWidth = 1.0
            grid.stroke()
        }
        
        // 3. Crisp selection border (dual-stroke: dark outer shadow + white crisp line)
        let outer = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        NSColor(white: 0.0, alpha: 0.35).setStroke()
        outer.lineWidth = 1.0
        outer.stroke()
        
        let border = NSBezierPath(rect: rect)
        NSColor.white.setStroke()
        border.lineWidth = 1.5
        border.stroke()
        
        // 4. 8 Handles (4 corners + 4 edge centers)
        let handleSize: CGFloat = 8
        for handle in Handle.allCases {
            let p = handle.point(for: rect)
            let hRect = NSRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize)
            
            // Subtle dark halo
            let halo = NSBezierPath(ovalIn: hRect.insetBy(dx: -1, dy: -1))
            NSColor(white: 0.0, alpha: 0.5).setFill()
            halo.fill()
            
            // White handle core
            let core = NSBezierPath(ovalIn: hRect)
            NSColor.white.setFill()
            core.fill()
        }
        
        // 5. Dimension & Quick Record Pill (Float below selection or above if near bottom)
        drawPill()
    }
    
    private func getPillRect() -> CGRect {
        let pillWidth: CGFloat = 200
        let pillHeight: CGFloat = 34
        
        var pillY = rect.maxY + 12
        if pillY + pillHeight + 10 > bounds.height {
            pillY = rect.minY - pillHeight - 12
        }
        let pillX = max(16, min(rect.midX - pillWidth / 2, bounds.width - pillWidth - 16))
        return CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
    }
    
    private func getRecordButtonRect(in pillRect: CGRect) -> CGRect {
        return CGRect(x: pillRect.maxX - 76, y: pillRect.minY + 4, width: 70, height: pillRect.height - 8)
    }
    
    private func drawPill() {
        guard rect.width >= 40 && rect.height >= 40 else { return }
        
        let pillRect = getPillRect()
        
        // Pill background
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 0.92).setFill()
        pillPath.fill()
        NSColor(white: 1.0, alpha: 0.22).setStroke()
        pillPath.lineWidth = 1.0
        pillPath.stroke()
        
        // Dimensions text
        let dimsText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: dimsText, attributes: attrs)
        let textY = pillRect.midY - attrStr.size().height / 2
        attrStr.draw(at: NSPoint(x: pillRect.minX + 12, y: textY))
        
        // Record Button inside Pill
        let btnRect = getRecordButtonRect(in: pillRect)
        let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 5, yRadius: 5)
        NSColor.systemRed.setFill()
        btnPath.fill()
        
        let btnText = "● Record"
        let btnAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let btnStr = NSAttributedString(string: btnText, attributes: btnAttrs)
        let btnX = btnRect.midX - btnStr.size().width / 2
        let btnY = btnRect.midY - btnStr.size().height / 2
        btnStr.draw(at: NSPoint(x: btnX, y: btnY))
    }
    
    // MARK: - Mouse Interaction
    
    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 1. Check if Record button in pill clicked
        let pillRect = getPillRect()
        let btnRect = getRecordButtonRect(in: pillRect)
        if btnRect.contains(point) {
            appState.selectedCropRect = rect
            appState.startRecordingFlow()
            return
        }
        
        // 2. Check handles
        for handle in Handle.allCases {
            if handle.hitRect(for: rect).contains(point) {
                dragMode = .resizing(handle: handle, startLocation: point, startRect: rect)
                handle.cursor.set()
                return
            }
        }
        
        // 3. Check inside crop rect -> Move
        if rect.contains(point) {
            dragMode = .moving(startLocation: point, startOrigin: rect.origin)
            NSCursor.closedHand.set()
            return
        }
        
        // 4. Clicked outside -> Draw a brand-new rectangle from scratch
        dragMode = .creating(anchor: point)
        rect = CGRect(origin: point, size: .zero)
        NSCursor.crosshair.set()
        needsDisplay = true
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        
        switch dragMode {
        case .none:
            break
            
        case .moving(let startLocation, let startOrigin):
            let deltaX = current.x - startLocation.x
            let deltaY = current.y - startLocation.y
            var newX = startOrigin.x + deltaX
            var newY = startOrigin.y + deltaY
            newX = max(0, min(newX, bounds.width - rect.width))
            newY = max(0, min(newY, bounds.height - rect.height))
            self.rect.origin = CGPoint(x: newX, y: newY)
            appState.selectedCropRect = self.rect
            NSCursor.closedHand.set()
            needsDisplay = true
            
        case .resizing(let handle, let startLocation, let startRect):
            let deltaX = current.x - startLocation.x
            let deltaY = current.y - startLocation.y
            let minSize: CGFloat = 60
            var r = startRect
            
            switch handle {
            case .leftCenter:
                let newX = min(startRect.maxX - minSize, startRect.minX + deltaX)
                r.origin.x = max(0, newX)
                r.size.width = startRect.maxX - r.origin.x
            case .rightCenter:
                let newW = max(minSize, startRect.width + deltaX)
                r.size.width = min(bounds.width - r.origin.x, newW)
            case .topCenter:
                let newY = min(startRect.maxY - minSize, startRect.minY + deltaY)
                r.origin.y = max(0, newY)
                r.size.height = startRect.maxY - r.origin.y
            case .bottomCenter:
                let newH = max(minSize, startRect.height + deltaY)
                r.size.height = min(bounds.height - r.origin.y, newH)
            case .topLeft:
                let newX = min(startRect.maxX - minSize, startRect.minX + deltaX)
                let newY = min(startRect.maxY - minSize, startRect.minY + deltaY)
                r.origin.x = max(0, newX)
                r.origin.y = max(0, newY)
                r.size.width = startRect.maxX - r.origin.x
                r.size.height = startRect.maxY - r.origin.y
            case .topRight:
                let newY = min(startRect.maxY - minSize, startRect.minY + deltaY)
                let newW = max(minSize, startRect.width + deltaX)
                r.origin.y = max(0, newY)
                r.size.height = startRect.maxY - r.origin.y
                r.size.width = min(bounds.width - r.origin.x, newW)
            case .bottomLeft:
                let newX = min(startRect.maxX - minSize, startRect.minX + deltaX)
                let newH = max(minSize, startRect.height + deltaY)
                r.origin.x = max(0, newX)
                r.size.width = startRect.maxX - r.origin.x
                r.size.height = min(bounds.height - r.origin.y, newH)
            case .bottomRight:
                let newW = max(minSize, startRect.width + deltaX)
                let newH = max(minSize, startRect.height + deltaY)
                r.size.width = min(bounds.width - r.origin.x, newW)
                r.size.height = min(bounds.height - r.origin.y, newH)
            }
            
            self.rect = r
            appState.selectedCropRect = r
            handle.cursor.set()
            needsDisplay = true
            
        case .creating(let anchor):
            let minX = max(0, min(anchor.x, current.x))
            let minY = max(0, min(anchor.y, current.y))
            let maxX = min(bounds.width, max(anchor.x, current.x))
            let maxY = min(bounds.height, max(anchor.y, current.y))
            self.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            appState.selectedCropRect = self.rect
            NSCursor.crosshair.set()
            needsDisplay = true
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if case .creating = dragMode {
            if rect.width < 30 || rect.height < 30 {
                // Click without drag: reset to standard 960x540 centered box around click
                let w: CGFloat = min(960, bounds.width * 0.65)
                let h: CGFloat = min(540, bounds.height * 0.65)
                let x = max(0, min(current.x - w / 2, bounds.width - w))
                let y = max(0, min(current.y - h / 2, bounds.height - h))
                self.rect = CGRect(x: x, y: y, width: w, height: h)
            }
        }
        dragMode = .none
        appState.selectedCropRect = self.rect
        updateCursor(at: current)
        needsDisplay = true
    }
    
    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
    }
    
    private func updateCursor(at point: CGPoint) {
        let pillRect = getPillRect()
        if pillRect.contains(point) {
            NSCursor.arrow.set()
            return
        }
        for handle in Handle.allCases {
            if handle.hitRect(for: rect).contains(point) {
                handle.cursor.set()
                return
            }
        }
        if rect.contains(point) {
            NSCursor.openHand.set()
            return
        }
        NSCursor.crosshair.set()
    }
    
    // MARK: - Keyboard Shortcuts (Escape to cancel, Return/Space to record)
    
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            appState.setCaptureMode(.entireScreen)
        case 36, 49: // Return or Space
            appState.selectedCropRect = rect
            appState.startRecordingFlow()
        default:
            super.keyDown(with: event)
        }
    }
}
