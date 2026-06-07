import Foundation
import SwiftUI
import SwiftBSON

// MARK: - DatabaseDetailView

struct DatabaseDetailView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @EnvironmentObject private var findVM: DocumentQueryViewModel
    @EnvironmentObject private var aggregateVM: AggregateQueryViewModel
    @EnvironmentObject private var indexVM: IndexQueryViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @Environment(\.databaseTabContext) private var tabContext
    @State private var showQueryConsole = false

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

                    // Query Console Panel (slides up from footer)
                    if showQueryConsole {
                        Divider().opacity(0.4)
                        QueryConsoleView()
                            .frame(height: 280)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let trackPadding: CGFloat = 3
            let minimumScrollableTabWidth: CGFloat = 120
            let trackWidth = max(
                0,
                geometry.size.width - (horizontalPadding * 2)
            )
            let trackInnerWidth = max(0, trackWidth - (trackPadding * 2))
            let tabWidth = max(
                minimumScrollableTabWidth,
                trackInnerWidth / CGFloat(max(context.tabs.count, 1))
            )
            let scrollContentWidth = (tabWidth * CGFloat(context.tabs.count)) + (trackPadding * 2)

            ScrollView(.horizontal, showsIndicators: false) {
                // Tab track
                HStack(spacing: 0) {
                    ForEach(context.tabs) { tab in
                        TabPill(
                            title: tab.title,
                            isSelected: tab.id == context.selectedId,
                            onSelect: { context.select(tab.id) },
                            onClose: { context.close(tab.id) }
                        )
                        .frame(width: tabWidth)
                    }
                }
                .padding(trackPadding)
                .frame(width: scrollContentWidth, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(.regularMaterial)
                )
            }
            .frame(width: trackWidth)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: 44)
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
                            if let duration = findVM.lastQueryDuration {
                                Text(String(format: "Query took %.3fs", duration))
                            }
                            Text("\(findVM.documents.count) docs")
                        }
                    case .aggregate:
                        HStack(spacing: 12) {
                            if let duration = aggregateVM.queryDuration {
                                Text(String(format: "Pipeline took %.3fs", duration))
                            }
                            Text("\(aggregateVM.documents.count) results")
                        }
                    case .index:
                        Text("\(indexVM.indexes.count) indexes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                // Console Toggle Button
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        showQueryConsole.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: showQueryConsole ? "terminal.fill" : "terminal")
                            .font(.system(size: 12, weight: .medium))
                        Text("Console")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(showQueryConsole ? Color.accentColor : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        showQueryConsole
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .help(showQueryConsole ? "Hide Query Console" : "Show Query Console")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }
}
