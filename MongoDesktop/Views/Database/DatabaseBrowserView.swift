import SwiftUI
import AppKit

// MARK: - DatabaseBrowserView

struct DatabaseBrowserView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @Environment(\.addDatabaseTab) private var addDatabaseTab
    @State private var showServerInfo = false

    var body: some View {
        NavigationSplitView {
            CollectionSidebarView()
                .environmentObject(sessionViewModel)
                .environmentObject(tabViewModel)
        } detail: {
            DatabaseDetailView()
                .environmentObject(sessionViewModel)
                .environmentObject(tabViewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(sessionViewModel.connectionName)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    WindowCoordinator.shared.showConnectionsWindow()
                }) {
                    Image(systemName: "server.rack")
                }
                .help("Connections")

                DatabasePickerButton()
                    .environmentObject(sessionViewModel)

                DatabaseCollectionInlineView()
                    .environmentObject(sessionViewModel)
            }

            ToolbarItem(placement: .principal) {
                ConnectionStatusCenterView(showServerInfo: $showServerInfo)
                    .environmentObject(sessionViewModel)
                    .environmentObject(tabViewModel)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addDatabaseTab) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .help("New Tab")
            }
        }
        .overlay(alignment: .topLeading) {
            if let error = sessionViewModel.lastError {
                ErrorBannerView(message: error) { sessionViewModel.clearError() }
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: sessionViewModel.lastError)
            }
        }
    }
}


// MARK: - DatabaseCollectionInlineView

struct DatabaseCollectionInlineView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let db = sessionViewModel.selectedDatabase, !db.isEmpty {
                Text(db)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let col = sessionViewModel.selectedCollection, !col.isEmpty {
                Text(col)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 8)
    }
}

// MARK: - Titlebar Leading Content

struct TitlebarLeadingContent: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                WindowCoordinator.shared.showConnectionsWindow()
            }) {
                Image(systemName: "server.rack")
            }
            .help("Connections")

            DatabasePickerButton()
                .environmentObject(sessionViewModel)

            DatabaseCollectionInlineView()
                .environmentObject(sessionViewModel)
        }
        .padding(.leading, 6)
    }
}

// MARK: - Titlebar Leading Accessory Host

struct TitlebarLeadingAccessoryHost<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.hostingView == nil {
            context.coordinator.hostingView = NSHostingView(rootView: content)
        } else {
            context.coordinator.hostingView?.rootView = content
        }

        guard let window = nsView.window,
              let hostingView = context.coordinator.hostingView
        else { return }

        if context.coordinator.controller == nil {
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            context.coordinator.controller = controller
        } else if context.coordinator.controller?.view !== hostingView {
            context.coordinator.controller?.view = hostingView
        }
    }

    final class Coordinator {
        var controller: NSTitlebarAccessoryViewController?
        var hostingView: NSHostingView<Content>?
    }
}

// MARK: - ConnectionStatusCenterView

struct ConnectionStatusCenterView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @Binding var showServerInfo: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button(action: { showServerInfo.toggle() }) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Server Information")
                .popover(isPresented: $showServerInfo, arrowEdge: .bottom) {
                    ServerInfoPopoverView()
                }

                Text(sessionViewModel.connectionName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            if tabViewModel.isLoading || tabViewModel.lastQueryDuration != nil {
                HStack(spacing: 8) {
                    Divider().frame(height: 14)

                    if tabViewModel.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                            .fixedSize()
                            .opacity(tabViewModel.isLoading ? 1 : 0)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tabViewModel.lastQueryDuration.map { formattedDuration($0) } ?? "0ms")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, alignment: .center)
        .padding(.horizontal, 12)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int(seconds * 1000))ms"
        } else {
            return String(format: "%.2fs", seconds)
        }
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
