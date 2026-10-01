import Foundation
import AppKit

/// Engine to inspect application location and handle drag-and-drop / automated installation to /Applications
@MainActor
public final class AppInstaller {
    
    public static let shared = AppInstaller()
    
    private init() {}
    
    /// Target installation directory: /Applications
    public var applicationsDirectoryURL: URL {
        return URL(fileURLWithPath: "/Applications")
    }
    
    /// Current running application bundle URL
    public var currentBundleURL: URL {
        return Bundle.main.bundleURL
    }
    
    /// Target application path inside /Applications
    public var destinationBundleURL: URL {
        let appName = currentBundleURL.lastPathComponent
        return applicationsDirectoryURL.appendingPathComponent(appName)
    }
    
    /// Checks whether the application is currently running from /Applications or ~/Applications
    public var isInstalledInApplicationsFolder: Bool {
        let currentPath = currentBundleURL.path
        let systemAppsPath = "/Applications"
        let userAppsPath = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        
        return currentPath.hasPrefix(systemAppsPath) || currentPath.hasPrefix(userAppsPath)
    }
    
    /// Determines whether the installation prompt should be shown on launch
    public func shouldPromptForInstallation() -> Bool {
        if isInstalledInApplicationsFolder {
            return false
        }
        if AppSettings.shared.suppressInstallPrompt {
            return false
        }
        return true
    }
    
    /// Moves or copies the current application bundle to /Applications and relaunches it from there
    @discardableResult
    public func moveToApplicationsFolder() -> Bool {
        let sourceURL = currentBundleURL
        let targetURL = destinationBundleURL
        
        // If already in target path, nothing to do
        if sourceURL.path == targetURL.path {
            return true
        }
        
        let fileManager = FileManager.default
        
        do {
            // Remove existing destination bundle if it exists
            if fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.trashItem(at: targetURL, resultingItemURL: nil)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
            }
            
            // Try standard copy item (preserves original in Downloads if running from DMG or temp)
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            
            // Try removing original if not running from read-only DMG volume
            if fileManager.isWritableFile(atPath: sourceURL.deletingLastPathComponent().path) {
                try? fileManager.removeItem(at: sourceURL)
            }
            
            // Relaunch app from /Applications
            relaunchFromPath(targetURL.path)
            return true
        } catch {
            // Fallback: If standard copy fails (e.g. root permissions needed for /Applications),
            // attempt AppleScript copy with elevated privileges
            let script = "do shell script \"rm -rf '\(targetURL.path)' && cp -R '\(sourceURL.path)' '\(targetURL.path)'\" with administrator privileges"
            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let eventResult = appleScript.executeAndReturnError(&errorInfo)
                if errorInfo == nil && eventResult.descriptorType != 0 {
                    relaunchFromPath(targetURL.path)
                    return true
                }
            }
            return false
        }
    }
    
    /// Relaunches the app from specified path and terminates current instance
    public func relaunchFromPath(_ appPath: String) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [appPath]
        try? task.run()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.terminate(nil)
        }
    }
}
