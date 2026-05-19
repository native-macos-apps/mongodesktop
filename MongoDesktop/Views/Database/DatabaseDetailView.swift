import Foundation
import SwiftUI
import SwiftBSON

// MARK: - DatabaseDetailView

struct DatabaseDetailView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @Environment(\.databaseTabContext) private var tabContext


    var body: some View {
        VStack(spacing: 0) {
            if let tabContext {
                if tabContext.tabs.count > 1 {
                    tabBar(tabContext)
                }
            }

            if sessionViewModel.selectedDatabase == nil || sessionViewModel.selectedCollection == nil {
                WelcomeScreenView()
            } else {
                VStack(spacing: 0) {
                    switch tabViewModel.selectedTab {
                    case .document:
                        CollectionDocumentView()
                    case .aggregate:
                        CollectionAggregateView()
                    case .index:
                        CollectionIndexView()
                    }
                    
                    footerArea
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab Bar

    private func tabBar(_ context: DatabaseTabContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Tab track
                HStack(spacing: 0) {
                    ForEach(context.tabs) { tab in
                        TabPill(
                            title: tab.title,
                            isSelected: tab.id == context.selectedId,
                            onSelect: { context.select(tab.id) },
                            onClose: { context.close(tab.id) }
                        )
                    }
                }
                .padding(3)
                .background(
                    Capsule(style: .continuous)
                        .fill(.regularMaterial)
                )

                // Add tab button (+)
                Button(action: context.add) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .help("New Tab")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - Footer UI

    private var footerArea: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            
            HStack {
                Picker("", selection: $tabViewModel.selectedTab) {
                    Text("Document").tag(CollectionTab.document)
                    Text("Aggregate").tag(CollectionTab.aggregate)
                    Text("Index").tag(CollectionTab.index)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Spacer()
                
                Group {
                    switch tabViewModel.selectedTab {
                    case .document:
                        HStack(spacing: 12) {
                            if let duration = tabViewModel.lastQueryDuration {
                                Text(String(format: "Query took %.3fs", duration))
                            }
                            Text("\(tabViewModel.documents.count) docs")
                        }
                    case .aggregate:
                        HStack(spacing: 12) {
                            if let duration = tabViewModel.aggregateQueryDuration {
                                Text(String(format: "Pipeline took %.3fs", duration))
                            }
                            Text("\(tabViewModel.aggregateDocuments.count) results")
                        }
                    case .index:
                        Text("\(tabViewModel.indexes.count) indexes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
