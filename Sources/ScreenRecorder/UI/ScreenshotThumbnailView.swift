import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - ScreenshotResult

/// A saved screenshot and its in-memory image (used for the floating thumbnail)
public struct ScreenshotResult: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let fileURL: URL
    public let image: NSImage
}

// MARK: - ScreenshotWriter

enum ScreenshotWriter {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "ScreenshotWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create image file"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ScreenshotWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG data"])
        }
    }

    /// Plays the same shutter sound macOS uses for Cmd+Shift+3/4/5
    static func playShutterSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}

// MARK: - ScreenshotThumbnailView

/// Floating thumbnail shown after a screenshot, modeled after the macOS one:
/// click to open, drag into any app, right-click for more actions. Auto-dismisses unless hovered.
public struct ScreenshotThumbnailView: View {
    let result: ScreenshotResult
    let autoCloseSeconds: Double
    let onDismiss: () -> Void

    @State private var isHovered: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    public init(result: ScreenshotResult, autoCloseSeconds: Double = 5.0, onDismiss: @escaping () -> Void) {
        self.result = result
        self.autoCloseSeconds = autoCloseSeconds
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Image(nsImage: result.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 200, maxHeight: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help("Dismiss")
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture {
                NSWorkspace.shared.open(result.fileURL)
                onDismiss()
            }
            .onDrag {
                NSItemProvider(contentsOf: result.fileURL) ?? NSItemProvider()
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    dismissTask?.cancel()
                } else {
                    scheduleDismiss()
                }
            }
            .contextMenu {
                Button("Open") {
                    NSWorkspace.shared.open(result.fileURL)
                    onDismiss()
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
                    onDismiss()
                }
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([result.fileURL as NSURL, result.image])
                }
                Divider()
                Button("Delete", role: .destructive) {
                    try? FileManager.default.trashItem(at: result.fileURL, resultingItemURL: nil)
                    onDismiss()
                }
            }
            .help("Click to open • Drag to share")
            .onAppear { scheduleDismiss() }
            .onDisappear { dismissTask?.cancel() }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard autoCloseSeconds > 0 else { return }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoCloseSeconds))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
