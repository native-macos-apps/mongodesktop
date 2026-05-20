import SwiftUI
import SwiftBSON

struct CollectionAggregateView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var aggregateVM: AggregateQueryViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var pipelineError: String? = nil
    @State private var localViewMode: DocumentViewMode = .json
    @State private var selection: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Aggregation Header/Toolbar
            HStack(spacing: 12) {
                Label("Aggregation", systemImage: "square.3.layers.3d.down.right.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !aggregateVM.documents.isEmpty {
                    Picker("", selection: $localViewMode) {
                        Image(systemName: "curlybraces").tag(DocumentViewMode.json)
                        Image(systemName: "tablecells").tag(DocumentViewMode.table)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 70)
                }
                
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
                    ZStack {
                        DocumentTableView(
                            rows: aggregateVM.tableCache.rows,
                            columns: aggregateVM.tableCache.columns,
                            columnTypes: aggregateVM.tableCache.columnTypes,
                            selection: $selection,
                            isLoading: false
                        )
                        .opacity(localViewMode == .table ? 1 : 0)
                        .disabled(localViewMode != .table)
                        
                        DocumentJSONView(
                            wrappedDocuments: aggregateVM.getJSONCache(timeZone: globalSettings.displayTimeZone),
                            isLoading: false
                        )
                        .opacity(localViewMode == .json ? 1 : 0)
                        .disabled(localViewMode != .json)
                    }
                }
            }
        }
    }
    
    private func runAggregate() {
        guard pipelineError == nil else { return }
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task { await aggregateVM.runAggregate(database: db, collection: col, session: sessionViewModel) }
    }
}
