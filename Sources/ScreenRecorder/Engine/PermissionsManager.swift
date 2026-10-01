import Foundation
import AppKit
import AVFoundation
import CoreGraphics

@MainActor
public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()
    
    @Published public private(set) var hasScreenRecordingPermission: Bool = false
    @Published public private(set) var hasMicrophonePermission: Bool = false
    
    private init() {
        checkPermissions()
    }
    
    public func checkPermissions() {
        // Screen recording permission
        self.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        
        // Microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.hasMicrophonePermission = (micStatus == .authorized)
    }
    
    public func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
        // Re-check after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.checkPermissions()
        }
    }
    
    public func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        self.hasMicrophonePermission = granted
        return granted
    }
    
    public func openScreenRecordingSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openMicrophoneSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
