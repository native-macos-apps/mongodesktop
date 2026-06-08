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
    @Binding var showQueryConsole: Bool
    @State private var aggregateViewMode: DocumentViewMode = .json
    @State private var showDocumentPagingSettings = false
    @State private var documentOffsetDraft = 0
    @State private var documentLimitDraft = 100

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
                        CollectionAggregateView(viewMode: $aggregateViewMode)
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

                footerSummary
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                footerControls
                .font(.caption)
                .foregroundStyle(.secondary)

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var footerSummary: some View {
        if tabViewModel.selectedTab == .document {
            Text(documentRangeText)
                .monospacedDigit()
        } else if tabViewModel.selectedTab == .aggregate {
            Text("\(aggregateVM.documents.count) results")
                .monospacedDigit()
        } else {
            Text("\(indexVM.indexes.count) indexes")
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        if tabViewModel.selectedTab == .document {
            documentFooterControls
        } else if tabViewModel.selectedTab == .aggregate {
            aggregateFooterControls
        }
    }

    private var documentFooterControls: some View {
        HStack(spacing: 4) {
            Button(action: previousDocumentPage) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(findVM.offset == 0)
            .help("Previous Page")

            Button(action: openDocumentPagingSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .help("Pagination Settings")
            .popover(isPresented: $showDocumentPagingSettings, arrowEdge: .bottom) {
                documentPagingSettingsPanel
            }

            Button(action: nextDocumentPage) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(!findVM.hasMore)
            .help("Next Page")

            Picker("", selection: $findVM.viewMode) {
                ForEach(DocumentViewMode.allCases) { mode in
                    Image(systemName: mode == .table ? "tablecells" : "curlybraces")
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 70)
        }
    }

    private var documentRangeText: String {
        guard !findVM.documents.isEmpty else {
            return "0 docs of \(findVM.totalDocuments)"
        }

        let from = findVM.offset + 1
        let to = findVM.offset + findVM.documents.count
        return "\(from) - \(to) docs of \(findVM.totalDocuments)"
    }

    private var documentPagingSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Offset")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                TextField("0", value: $documentOffsetDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Text("Limit")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
                TextField("100", value: $documentLimitDraft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()

                Button("Apply") {
                    applyDocumentPagingSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 160)
    }

    private var aggregateFooterControls: some View {
        HStack(spacing: 12) {
            if !aggregateVM.documents.isEmpty {
                Picker("", selection: $aggregateViewMode) {
                    Image(systemName: "tablecells").tag(DocumentViewMode.table)
                    Image(systemName: "curlybraces").tag(DocumentViewMode.json)
                }
                .pickerStyle(.segmented)
                .frame(width: 70)
            }
        }
    }

    private func previousDocumentPage() {
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task { await findVM.previousPage(database: db, collection: col, session: sessionViewModel) }
    }

    private func nextDocumentPage() {
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task { await findVM.nextPage(database: db, collection: col, session: sessionViewModel) }
    }

    private func openDocumentPagingSettings() {
        documentOffsetDraft = findVM.offset
        documentLimitDraft = findVM.pageSize
        showDocumentPagingSettings = true
    }

    private func applyDocumentPagingSettings() {
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }

        showDocumentPagingSettings = false
        Task {
            await findVM.applyPaging(
                offset: documentOffsetDraft,
                limit: documentLimitDraft,
                database: db,
                collection: col,
                session: sessionViewModel
            )
        }
    }
}
