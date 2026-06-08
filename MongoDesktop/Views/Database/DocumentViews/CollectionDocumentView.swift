import SwiftUI
import SwiftBSON

struct CollectionDocumentView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var findVM: DocumentQueryViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    
    @State private var filterError: String? = nil
    @State private var sortError: String? = nil
    @State private var projectionError: String? = nil
    @State private var localViewMode: DocumentViewMode = .json

    var body: some View {
        VStack(spacing: 0) {
            toolbarArea
            Divider().opacity(0.4)
            contentArea
        }
        .onAppear {
            localViewMode = findVM.viewMode
        }
        .onChange(of: findVM.viewMode) { _, newValue in
            guard localViewMode != newValue else { return }
            localViewMode = newValue
        }
        .onChange(of: localViewMode) { _, newValue in
            guard findVM.viewMode != newValue else { return }
            DispatchQueue.main.async {
                findVM.viewMode = newValue
            }
        }
    }

    // MARK: - Toolbar Area

    private var toolbarArea: some View {
        VStack(spacing: 0) {
            // Filter Row
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                    .font(.body)

                JSONEditorView(
                    text: $findVM.filterText,
                    errorMessage: $filterError,
                    documentKeys: findVM.documentKeysForCompletion,
                    minHeight: 28
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filterError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(filterError ?? "Filter JSON { \"field\": \"value\" }")

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { findVM.isAdvancedQuery.toggle() } }) {
                    Label(findVM.isAdvancedQuery ? "Simple" : "Advanced", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: runFind) {
                    Label("Run", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(hasSyntaxError)
                .opacity(hasSyntaxError ? 0.55 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if findVM.isAdvancedQuery {
                advancedQueryRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

        }
    }

    private var advancedQueryRow: some View {
        HStack(spacing: 10) {
            Text("Sort")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $findVM.sortText,
                errorMessage: $sortError,
                documentKeys: findVM.documentKeysForCompletion,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(sortError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(sortError ?? "Sort JSON { \"field\": 1 }")

            Text("Projection")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $findVM.projectionText,
                errorMessage: $projectionError,
                documentKeys: findVM.documentKeysForCompletion,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(projectionError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(projectionError ?? "Projection JSON { \"field\": 1 }")
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            if localViewMode == .table {
                tableContent
            } else {
                jsonContent
            }
        }
    }

    private var tableContent: some View {
        let tableCache = findVM.getDocumentTableCache()

        return DocumentTableView(
            rows: tableCache.rows,
            columns: tableCache.columns,
            columnTypes: tableCache.columnTypes,
            selection: $findVM.selectedRowIds,
            isLoading: findVM.isLoading
        )
    }

    private var jsonContent: some View {
        DocumentJSONView(
            documents: findVM.documents,
            timeZone: globalSettings.displayTimeZone,
            isLoading: findVM.isLoading
        )
    }

    // MARK: - Actions

    private func runFind() {
        guard !hasSyntaxError else { return }
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        findVM.resetPaging()
        Task { await findVM.runFind(database: db, collection: col, session: sessionViewModel) }
    }

    private var hasSyntaxError: Bool {
        if filterError != nil { return true }
        if findVM.isAdvancedQuery && (sortError != nil || projectionError != nil) { return true }
        return false
    }
}
