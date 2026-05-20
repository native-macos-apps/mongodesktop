import SwiftUI

// MARK: - DatabaseWindowView

struct DatabaseWindowView: View {
    let connectionId: ConnectionProfile.ID?

    @EnvironmentObject private var connectionStore: ConnectionStore
    @StateObject private var sessionViewModel = DatabaseSessionViewModel()
    @StateObject private var windowViewModel = DatabaseWindowViewModel()

    var body: some View {
        Group {
            if let connection = resolvedConnection {
                if let selectedTab = windowViewModel.selectedTab {
                    DatabaseTabContentView(
                        connection: connection,
                        connectionStore: connectionStore,
                        sessionViewModel: sessionViewModel,
                        tabViewModel: selectedTab.viewModel
                    )
                    .environment(\.addDatabaseTab) {
                        windowViewModel.addTab(prefillingFrom: sessionViewModel)
                    }
                    .environment(\.databaseTabContext, windowViewModel.tabContext(session: sessionViewModel))
                } else {
                    loadingTabView
                }
            } else {
                missingConnectionView
            }
        }
        .onAppear { windowViewModel.ensureInitialTab(session: sessionViewModel) }
        .onAppear { connectIfNeeded() }
        .onDisappear {
            Task { try? await sessionViewModel.disconnect() }
            // Show the Connections window again when a Database window closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowCoordinator.shared.showConnectionsWindow()
            }
        }
        .frame(minWidth: 900, idealWidth: 1080, minHeight: 600, idealHeight: 720)
    }

    private var missingConnectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Connection not found")
                .font(.title2.weight(.semibold))
            Text("Please reopen from the Connections list.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedConnection: ConnectionProfile? {
        guard let id = connectionId else { return nil }
        return connectionStore.connections.first { $0.id == id }
    }

    private func connectIfNeeded() {
        guard let connection = resolvedConnection else { return }
        guard !sessionViewModel.isConnected, !sessionViewModel.isLoading else { return }
        sessionViewModel.connect(using: connection, store: connectionStore)
    }

    private var loadingTabView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing tab…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DatabaseTabContentView: View {
    let connection: ConnectionProfile
    let connectionStore: ConnectionStore
    @ObservedObject var sessionViewModel: DatabaseSessionViewModel
    @ObservedObject var tabViewModel: QueryTabViewModel

    var body: some View {
        Group {
            if sessionViewModel.isConnected {
                DatabaseBrowserView()
                    .environmentObject(sessionViewModel)
                    .environmentObject(tabViewModel)
                    .environmentObject(tabViewModel.find)
                    .environmentObject(tabViewModel.aggregate)
                    .environmentObject(tabViewModel.index)
                    .environmentObject(connectionStore)
            } else if sessionViewModel.isLoading {
                connectingView
            } else {
                failedView
            }
        }
        .onAppear { connectIfNeeded() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectIfNeeded() {
        guard !sessionViewModel.isConnected, !sessionViewModel.isLoading else { return }
        sessionViewModel.connect(using: connection, store: connectionStore)
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 20, height: 20)
                .fixedSize()
            Text("Connecting…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(connection.displayConnectionString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Could not connect")
                .font(.title2.weight(.semibold))
            if let error = sessionViewModel.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("Retry") { sessionViewModel.connect(using: connection, store: connectionStore) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
