import SwiftUI
import AppKit

/// Interactive Drag & Drop Application Installation View
public struct InstallPromptView: View {
    
    @ObservedObject var appSettings = AppSettings.shared
    @State private var isTargeted: Bool = false
    @State private var isHoveringApp: Bool = false
    @State private var isHoveringAppsFolder: Bool = false
    @State private var installError: String? = nil
    
    public var onDismiss: () -> Void
    
    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install RecLite")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Drag to Applications or click to move automatically")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.top, 4)
            
            // Drag & Drop Workspace
            HStack(spacing: 32) {
                // Source: App Icon (Draggable)
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(isHoveringApp ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isHoveringApp ? 2 : 1)
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 68, height: 68)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                    .scaleEffect(isHoveringApp ? 1.05 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHoveringApp)
                    .onHover { hover in
                        isHoveringApp = hover
                    }
                    .onDrag {
                        NSItemProvider(object: AppInstaller.shared.currentBundleURL as NSURL)
                    }
                    
                    Text("RecLite.app")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Drag me")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Animated Arrow / Transfer Line
                VStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.7))
                        .scaleEffect(isTargeted ? 1.25 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                    
                    Text("Drop here")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
                }
                
                // Target: Applications Folder (Drop Destination)
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        isTargeted ? Color.accentColor : (isHoveringAppsFolder ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12)),
                                        style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1, dash: isTargeted ? [6, 4] : [])
                                    )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "folder.fill.badge.plus")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 52))
                            .foregroundColor(isTargeted ? .accentColor : .blue)
                    }
                    .scaleEffect(isTargeted ? 1.08 : (isHoveringAppsFolder ? 1.03 : 1.0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
                    .onHover { hover in
                        isHoveringAppsFolder = hover
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                        performMoveToApplications()
                        return true
                    }
                    
                    Text("Applications")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("/Applications")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            
            if let error = installError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Footer Controls & Buttons
            VStack(spacing: 14) {
                Toggle("Do not ask again for this location", isOn: $appSettings.suppressInstallPrompt)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Button(action: {
                        onDismiss()
                    }) {
                        Text("Keep Running Here")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button(action: {
                        performMoveToApplications()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.app.fill")
                            Text("Move to Applications")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(24)
        .frame(width: 440, height: 330)
        .background(.ultraThinMaterial)
    }
    
    private func performMoveToApplications() {
        let success = AppInstaller.shared.moveToApplicationsFolder()
        if !success {
            installError = "Failed to move application. Please drag RecLite manually to /Applications."
        }
    }
}
