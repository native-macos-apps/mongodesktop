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
                    documentKeys: findVM.documentTableCache.columns,
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

            Divider()
                .opacity(0.4)

            // Pagination Row
            paginationRow
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
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
                documentKeys: findVM.documentTableCache.columns,
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
                documentKeys: findVM.documentTableCache.columns,
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

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        Picker("", selection: $localViewMode) {
            ForEach(DocumentViewMode.allCases) { mode in
                Image(systemName: mode == .table ? "tablecells" : "curlybraces")
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 70)
    }

    // MARK: - Pagination

    private var paginationRow: some View {
        HStack(spacing: 12) {
            Button(action: {
                guard let db = sessionViewModel.selectedDatabase,
                      let col = sessionViewModel.selectedCollection else { return }
                Task { await findVM.previousPage(database: db, collection: col, session: sessionViewModel) }
            }) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(findVM.currentPage == 0)

            Text("Page \(findVM.currentPage + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: {
                guard let db = sessionViewModel.selectedDatabase,
                      let col = sessionViewModel.selectedCollection else { return }
                Task { await findVM.nextPage(database: db, collection: col, session: sessionViewModel) }
            }) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!findVM.hasMore)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            Text("\(findVM.documents.count) docs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Text("Limit \(findVM.pageSize)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            viewModePicker
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ZStack {
            DocumentTableView(
                rows: findVM.documentTableCache.rows,
                columns: findVM.documentTableCache.columns,
                columnTypes: findVM.documentTableCache.columnTypes,
                selection: $findVM.selectedRowIds,
                isLoading: findVM.isLoading
            )
            .opacity(localViewMode == .table ? 1 : 0)
            .disabled(localViewMode != .table)
            
            DocumentJSONView(
                wrappedDocuments: findVM.getDocumentJSONCache(timeZone: globalSettings.displayTimeZone),
                isLoading: findVM.isLoading
            )
            .opacity(localViewMode == .json ? 1 : 0)
            .disabled(localViewMode != .json)
        }
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
