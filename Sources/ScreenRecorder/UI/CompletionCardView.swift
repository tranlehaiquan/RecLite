import SwiftUI
import AppKit

/// Floating completion sheet displaying recorded file details and quick actions
public struct CompletionCardView: View {
    let result: RecordingResult
    let autoCloseSeconds: Double
    let onDismiss: () -> Void
    
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false
    @State private var dismissTask: Task<Void, Never>? = nil
    
    public init(
        result: RecordingResult,
        autoCloseSeconds: Double = 5.0,
        onDismiss: @escaping () -> Void
    ) {
        self.result = result
        self.autoCloseSeconds = autoCloseSeconds
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 15))
                
                Text("Recording Saved")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Thumbnail & Metadata
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let thumb = result.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "video.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 140, height: 85)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    // Duration badge in thumbnail
                    Text(result.formattedDuration)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .padding(4),
                    alignment: .bottomTrailing
                )
                
                // File Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.fileURL.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 6) {
                        Badge(text: result.container.rawValue.uppercased(), color: .blue)
                        Badge(text: result.codec.shortName, color: .purple)
                        Badge(text: "\(Int(result.dimensions.width))×\(Int(result.dimensions.height))", color: .secondary)
                    }
                    
                    Spacer()
                    
                    // Actual file size
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(result.formattedFileSize)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Text("(\(result.formattedDuration))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    NSWorkspace.shared.open(result.fileURL)
                    onDismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Open Video")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("In Finder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([result.fileURL as NSURL])
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(isCopied ? .green : .primary)
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Copy Video File")
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .onAppear {
            startAutoCloseTimer()
        }
        .onDisappear {
            dismissTask?.cancel()
            dismissTask = nil
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                dismissTask?.cancel()
                dismissTask = nil
            } else {
                startAutoCloseTimer()
            }
        }
    }
    
    private func startAutoCloseTimer() {
        guard autoCloseSeconds > 0 else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoCloseSeconds * 1_000_000_000))
            if !Task.isCancelled && !isHovered {
                onDismiss()
            }
        }
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}
