import SwiftUI
import AppKit

// MARK: - DatabaseBrowserView

struct DatabaseBrowserView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @EnvironmentObject private var findVM: DocumentQueryViewModel
    @EnvironmentObject private var aggregateVM: AggregateQueryViewModel
    @EnvironmentObject private var indexVM: IndexQueryViewModel
    @Environment(\.addDatabaseTab) private var addDatabaseTab
    @State private var showServerInfo = false
    @State private var showQueryConsole = false

    var body: some View {
        NavigationSplitView {
            CollectionSidebarView()
                .environmentObject(sessionViewModel)
        } detail: {
            DatabaseDetailView(showQueryConsole: $showQueryConsole)
                .environmentObject(sessionViewModel)
                .environmentObject(tabViewModel)
                .environmentObject(findVM)
                .environmentObject(aggregateVM)
                .environmentObject(indexVM)
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
                    .environmentObject(findVM)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addDatabaseTab) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .help("New Tab")

                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        showQueryConsole.toggle()
                    }
                }) {
                    Image(systemName: showQueryConsole ? "terminal.fill" : "terminal")
                }
                .help(showQueryConsole ? "Hide Query Console" : "Show Query Console")
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
