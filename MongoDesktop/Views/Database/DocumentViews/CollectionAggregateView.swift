import SwiftUI
import SwiftBSON

struct CollectionAggregateView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var aggregateError: String? = nil
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
                
                if !tabViewModel.aggregateDocuments.isEmpty {
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
                .disabled(aggregateError != nil)
                .opacity(aggregateError != nil ? 0.55 : 1)
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
                    text: $tabViewModel.aggregatePipelineText,
                    errorMessage: $aggregateError,
                    minHeight: 80
                )
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(aggregateError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(aggregateError ?? "Aggregation Pipeline: [ { \"$match\": { ... } }, ... ]")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Result Area
            Group {
                if tabViewModel.isAggregateLoading {
                    VStack {
                        Spacer()
                        ProgressView("Running aggregation pipeline...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = tabViewModel.aggregateError {
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
                } else if tabViewModel.aggregateDocuments.isEmpty {
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
                    if localViewMode == .table {
                        DocumentTableView(
                            documents: tabViewModel.aggregateDocuments,
                            selection: $selection,
                            isLoading: false
                        )
                    } else {
                        DocumentJSONView(
                            documents: tabViewModel.aggregateDocuments,
                            timeZone: globalSettings.displayTimeZone,
                            isLoading: false
                        )
                    }
                }
            }
        }
    }
    
    private func runAggregate() {
        guard aggregateError == nil else { return }
        Task { await tabViewModel.runAggregate(using: sessionViewModel) }
    }
}
