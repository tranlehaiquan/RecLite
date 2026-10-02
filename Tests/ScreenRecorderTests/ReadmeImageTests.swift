import Testing
import SwiftUI
import AppKit
@testable import ScreenRecorder

/// Renders README images from the real SwiftUI views — no manual screen captures needed.
/// Skipped during normal test runs. Generate with: ./scripts/generate_readme_images.sh
@Suite("README Images", .enabled(if: ProcessInfo.processInfo.environment["RECLITE_README_IMAGES"] != nil))
@MainActor
struct ReadmeImageTests {

    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["RECLITE_README_IMAGES"] ?? "docs/images")
    }

    @Test("Render README images")
    func renderReadmeImages() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let appState = AppState.shared
        appState.captureMode = .entireScreen
        appState.recordingState = .idle

        // Hero banner: control bar floating over a desktop wallpaper, light and dark
        for scheme in [ColorScheme.light, .dark] {
            try render(
                Wallpaper(scheme: scheme) {
                    FloatingControlBarView(appState: appState).fixedSize()
                },
                scheme: scheme,
                name: "control-bar-\(scheme == .dark ? "dark" : "light")"
            )
        }

        // Recording HUD
        appState.recordingState = .recording(elapsed: 83, bytesWritten: 4_800_000)
        try render(
            Wallpaper(scheme: .dark, padding: 40) {
                RecordingHUDView(appState: appState).fixedSize()
            },
            scheme: .dark,
            name: "recording-hud"
        )
        appState.recordingState = .idle

        // Post-recording completion card
        let result = RecordingResult(
            fileURL: URL(fileURLWithPath: "/Users/me/Movies/RecLite Recording 2026-10-02 at 10.30.00.mp4"),
            duration: 83,
            fileSize: 4_800_000,
            dimensions: CGSize(width: 2880, height: 1800),
            codec: .hevc,
            container: .mp4,
            thumbnail: Self.sampleThumbnail()
        )
        try render(
            Wallpaper(scheme: .dark, padding: 40) {
                CompletionCardView(result: result, autoCloseSeconds: 0) {}
                    .frame(width: 360)
                    .fixedSize()
            },
            scheme: .dark,
            name: "completion-card"
        )

        // Preferences window content
        try render(
            Wallpaper(scheme: .light, padding: 50) {
                WindowChrome(title: "RecLite Preferences") {
                    SettingsView().frame(width: 640, height: 490)
                }
            },
            scheme: .light,
            name: "settings"
        )
    }

    // MARK: - Rendering

    /// Hosts the view offscreen and writes a 2x PNG named `<name>.png` into the output directory
    private func render<V: View>(_ view: V, scheme: ColorScheme, name: String) throws {
        let root = view
            .environment(\.isSnapshotRendering, true)
            .environment(\.colorScheme, scheme)
        let hostingView = NSHostingView(rootView: root)
        hostingView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)

        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)

        // A window is needed for SwiftUI to lay out and draw; it is never shown
        let window = NSWindow(contentRect: hostingView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = hostingView.appearance
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ReadmeImages", code: 1)
        }
        rep.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ReadmeImages", code: 2)
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("Wrote \(url.path)")
    }

    /// Placeholder video frame for the completion card thumbnail
    private static func sampleThumbnail() -> NSImage {
        NSImage(size: NSSize(width: 480, height: 270), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(srgbRed: 0.36, green: 0.55, blue: 0.95, alpha: 1),
                NSColor(srgbRed: 0.68, green: 0.45, blue: 0.92, alpha: 1)
            ])?.draw(in: rect, angle: -35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 70, dy: 50), xRadius: 12, yRadius: 12).fill()
            return true
        }
    }
}

// MARK: - Wallpaper backdrop

/// Soft macOS-style desktop gradient behind floating UI so README images have context
private struct Wallpaper<Content: View>: View {
    let scheme: ColorScheme
    var padding: CGFloat = 70
    @ViewBuilder let content: Content

    var body: some View {
        content
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .padding(padding)
            .background(
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.13, green: 0.16, blue: 0.30), Color(red: 0.30, green: 0.18, blue: 0.38)]
                        : [Color(red: 0.72, green: 0.84, blue: 0.98), Color(red: 0.93, green: 0.86, blue: 0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

// MARK: - Window chrome

/// Minimal macOS window frame (title bar + traffic lights) for windowed views like Preferences
private struct WindowChrome<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                    Spacer()
                }
                .frame(height: 12)
                .padding(.leading, 14)
            }
            .frame(height: 30)
            .background(Color(nsColor: .windowBackgroundColor))

            content
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
        )
    }
}
