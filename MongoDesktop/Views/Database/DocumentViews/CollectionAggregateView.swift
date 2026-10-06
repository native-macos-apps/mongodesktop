import SwiftUI
import SwiftBSON

struct CollectionAggregateView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var aggregateVM: AggregateQueryViewModel
    @EnvironmentObject private var findVM: DocumentQueryViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var pipelineError: String? = nil
    @Binding var viewMode: DocumentViewMode
    @State private var selection: Set<String> = []
    @State private var showExplainSheet = false
    @State private var explainResult: ExplainResult? = nil
    @State private var isExplaining = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Aggregation Header/Toolbar
            HStack(spacing: 12) {
                Label("Aggregation", systemImage: "square.3.layers.3d.down.right.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: runExplain) {
                    Group {
                        if isExplaining {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Label("Explain", systemImage: "magnifyingglass")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(pipelineError != nil || isExplaining)
                .opacity(pipelineError != nil ? 0.55 : 1)
                .help("Run explain plan for current pipeline")

                Button(action: runAggregate) {
                    Label("Run Pipeline", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(pipelineError != nil)
                .opacity(pipelineError != nil ? 0.55 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Editor Area
            VStack(alignment: .leading, spacing: 4) {
                Text("Pipeline Definition")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                JSONEditorView(
                    text: $aggregateVM.pipelineText,
                    errorMessage: $pipelineError,
                    documentKeys: findVM.documentKeysForCompletion,
                    schemaFields: findVM.schemaFieldsForCompletion,
                    editorMode: .aggregatePipeline,
                    minHeight: 80
                )
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(pipelineError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(pipelineError ?? "Aggregation Pipeline: [ { \"$match\": { ... } }, ... ]")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Result Area
            Group {
                if aggregateVM.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Running aggregation pipeline...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = aggregateVM.error {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                        Text("Aggregation Failed")
                            .font(.headline)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if aggregateVM.documents.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "square.stack.3d.up.dottedline")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No Results")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Run an aggregation pipeline to see results here.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Group {
                        if viewMode == .table {
                            aggregateTableContent
                        } else {
                            aggregateJSONContent
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showExplainSheet) {
            if let result = explainResult {
                ExplainResultView(result: result, isPresented: $showExplainSheet)
            }
        }
    }

    private var aggregateTableContent: some View {
        let tableCache = aggregateVM.tableCache
        let isPreparingTable = tableCache == nil && !aggregateVM.documents.isEmpty

        return DocumentTableView(
            rows: tableCache?.rows ?? [],
            columns: tableCache?.columns ?? [],
            columnTypes: tableCache?.columnTypes ?? [:],
            selection: $selection,
            isLoading: isPreparingTable
        )
        .task(id: aggregateVM.tableCacheRequestID) {
            await aggregateVM.prepareTableCache()
        }
    }

    private var aggregateJSONContent: some View {
        DocumentJSONView(
            documents: aggregateVM.documents,
            timeZone: globalSettings.displayTimeZone,
            isLoading: false
        )
    }
    
    private func runAggregate() {
        guard pipelineError == nil else { return }
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task { await aggregateVM.runAggregate(database: db, collection: col, session: sessionViewModel) }
    }

    private func runExplain() {
        guard pipelineError == nil else { return }
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task {
            isExplaining = true
            defer { isExplaining = false }
            do {
                let pipeline = try MongoQueryParsing.parsePipeline(aggregateVM.pipelineText)
                let raw = try await MongoService.shared.explainAggregate(
                    database: db,
                    collection: col,
                    pipeline: pipeline
                )
                // Aggregate explain may nest results under stages or queryPlanner
                let queryPlanner = (raw["queryPlanner"] ?? raw["stages"]?.arrayValue?.first?.documentValue?["$cursor"]?.documentValue?["queryPlanner"])?.documentValue
                let executionStats = (raw["executionStats"] ?? raw["stages"]?.arrayValue?.first?.documentValue?["$cursor"]?.documentValue?["executionStats"])?.documentValue
                explainResult = ExplainResult(
                    rawDocument: raw,
                    queryPlanner: queryPlanner,
                    executionStats: executionStats
                )
                showExplainSheet = true
            } catch {
                sessionViewModel.lastError = error.localizedDescription
            }
        }
    }
}
