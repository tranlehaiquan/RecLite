import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Mode of capture selected by user (mirrors macOS Cmd+Shift+5 buttons)
public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
    case entireScreen = "entireScreen"
    case selectedWindow = "selectedWindow"
    case selectedArea = "selectedArea"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .entireScreen: return "Record Entire Screen"
        case .selectedWindow: return "Record Window"
        case .selectedArea: return "Record Selected Portion"
        }
    }
    
    public var systemIconName: String {
        switch self {
        case .entireScreen: return "display"
        case .selectedWindow: return "macwindow"
        case .selectedArea: return "rectangle.dashed"
        }
    }
}

/// Concrete target to record
public enum RecordingTarget: Equatable, Sendable {
    case entireScreen(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID, windowTitle: String)
    case area(rect: CGRect, displayID: CGDirectDisplayID)
    
    public var displayName: String {
        switch self {
        case .entireScreen(let id):
            return "Display \(id)"
        case .window(_, let title):
            return title.isEmpty ? "Selected Window" : title
        case .area(let rect, _):
            return "Area \(Int(rect.width))×\(Int(rect.height))"
        }
    }
}

/// State of recording pipeline
public enum RecordingState: Equatable, Sendable {
    case idle
    case countingDown(remainingSeconds: Int)
    case recording(elapsed: TimeInterval, bytesWritten: Int64)
    case paused(elapsed: TimeInterval)
    case finalizing
    case failed(String)
    
    public var isRecordingOrPaused: Bool {
        switch self {
        case .recording, .paused: return true
        default: return false
        }
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}
