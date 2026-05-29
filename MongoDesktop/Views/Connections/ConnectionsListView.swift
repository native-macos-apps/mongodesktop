import SwiftUI
import AppKit

// MARK: - ConnectionsListView

struct ConnectionsListView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @Environment(\.openWindow) private var openWindow

    @State private var editorMode: EditorMode?
    @State private var draft = ConnectionDraft()
    @State private var selectedId: ConnectionProfile.ID?
    @State private var importURI: String = ""
    @State private var showImportAlert = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .background(ConnectionsWindowAccessor())
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 480, idealWidth: 700, minHeight: 320, idealHeight: 400)
        .sheet(item: $editorMode) { mode in
            ConnectionEditorView(mode: mode, draft: $draft, onSave: saveDraft)
        }
        .alert("Import from URI", isPresented: $showImportAlert) {
            TextField("mongodb://host:port/db", text: $importURI)
            Button("Cancel", role: .cancel) { importURI = "" }
            Button("Import") { importFromURI() }
        } message: {
            Text("Paste your MongoDB connection string here.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Logo / branding
            VStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.top, 28)

                Text("Mongo Desktop")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Text("\(connectionStore.connections.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            Divider().padding(.horizontal, 16)

            Spacer()

            // Credit dungmv
            Text("Credit by dungmv")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 180, idealWidth: 200)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            // Connection list
            if connectionStore.connections.isEmpty {
                emptyState
            } else {
                connectionList
            }
        }
        .background(.ultraThinMaterial)
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    draft = ConnectionDraft()
                    editorMode = .create
                }) {
                    Label("New Server", systemImage: "plus")
                }
                .help("New Server")

                Button(action: { showImportAlert = true }) {
                    Label("Import URI", systemImage: "square.and.arrow.down")
                }
                .help("Import URI")
            }
        }
    }

    // MARK: - Connection List

    private var connectionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(connectionStore.connections) { connection in
                    ConnectionRow(
                        connection: connection,
                        isSelected: selectedId == connection.id,
                        onSelect: { selectedId = connection.id },
                        onConnect: { openConnection(connection) },
                        onEdit: { openEditor(for: connection) },
                        onDelete: {
                            selectedId = connection.id
                            deleteSelected()
                        },
                        onDuplicate: { duplicate(connection) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No connections yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click \"New Server\" or use \"Import URI\" to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var selectedConnection: ConnectionProfile? {
        guard let sid = selectedId else { return nil }
        return connectionStore.connections.first { $0.id == sid }
    }

    private func deleteSelected() {
        guard let connection = selectedConnection else { return }
        connectionStore.delete(connection)
        if selectedId == connection.id { selectedId = nil }
    }

    private func openEditor(for connection: ConnectionProfile) {
        selectedId = connection.id
        draft = ConnectionDraft(from: connection)
        editorMode = .edit(connection.id)
    }

    private func openConnection(_ connection: ConnectionProfile) {
        selectedId = connection.id
        openWindow(value: connection.id)

        Task { @MainActor in
            WindowCoordinator.shared.hideConnectionsWindow()
        }
    }

    private func duplicate(_ connection: ConnectionProfile) {
        var copied = connection
        copied.id = UUID()
        copied.name = "\(connection.name) (copy)"
        copied.lastConnectedAt = nil
        connectionStore.add(copied)
        selectedId = copied.id
    }

    private func importFromURI() {
        let uri = importURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else { return }
        let draft = ConnectionDraft(fromURI: uri)
        let profile = draft.build()
        connectionStore.add(profile)
        importURI = ""
    }

    private func saveDraft(mode: EditorMode) {
        switch mode {
        case .create: connectionStore.add(draft.build())
        case .edit(let id): connectionStore.update(draft.build(id: id))
        }
    }
}

private struct ConnectionsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackingView {
        TrackingView()
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            WindowCoordinator.shared.registerConnectionsWindow(window)
        }
    }
}

// MARK: - ConnectionRow

struct ConnectionRow: View {
    let connection: ConnectionProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(connection.displayConnectionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onConnect() })
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
            Button("Duplicate", action: onDuplicate)
        }
    }
}
