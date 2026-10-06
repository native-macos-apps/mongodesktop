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

    @State private var editingDocument: BSONDocument? = nil
    @State private var documentsToDelete: [BSONDocument]? = nil

    @State private var showUpdateSheet = false
    @State private var showExportSheet = false
    @State private var confirmBulkDelete = false
    @State private var showExplainSheet = false
    @State private var explainResult: ExplainResult? = nil
    @State private var isExplaining = false

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
        .sheet(isPresented: $findVM.showAddSheet) {
            if let db = sessionViewModel.selectedDatabase,
               let col = sessionViewModel.selectedCollection {
                DocumentEditorSheet(
                    title: "Add Document",
                    isPresented: $findVM.showAddSheet,
                    initialDocument: nil,
                    documentKeys: findVM.documentKeysForCompletion,
                    onSave: { newDoc in
                        await findVM.insertDocument(
                            database: db,
                            collection: col,
                            document: newDoc,
                            session: sessionViewModel
                        )
                    }
                )
            }
        }
        .sheet(isPresented: Binding(get: { editingDocument != nil }, set: { if !$0 { editingDocument = nil } })) {
            if let db = sessionViewModel.selectedDatabase,
               let col = sessionViewModel.selectedCollection,
               let doc = editingDocument {
                DocumentEditorSheet(
                    title: "Edit Document",
                    isPresented: Binding(get: { editingDocument != nil }, set: { if !$0 { editingDocument = nil } }),
                    initialDocument: doc,
                    documentKeys: findVM.documentKeysForCompletion,
                    onSave: { updatedDoc in
                        await findVM.replaceDocument(
                            database: db,
                            collection: col,
                            originalDocument: doc,
                            replacement: updatedDoc,
                            session: sessionViewModel
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showUpdateSheet) {
            if let db = sessionViewModel.selectedDatabase,
               let col = sessionViewModel.selectedCollection {
                CollectionUpdateSheet(
                    database: db,
                    collection: col,
                    filterText: findVM.filterText,
                    existingDocuments: findVM.documents,
                    totalCount: findVM.totalDocuments,
                    documentKeys: findVM.documentKeysForCompletion,
                    isPresented: $showUpdateSheet,
                    onUpdate: { filter, updateDoc in
                        _ = await findVM.updateDocuments(
                            database: db,
                            collection: col,
                            filter: filter,
                            update: updateDoc,
                            session: sessionViewModel
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let db = sessionViewModel.selectedDatabase,
               let col = sessionViewModel.selectedCollection {
                CollectionExportSheet(
                    database: db,
                    collection: col,
                    defaultFilter: findVM.filterText,
                    defaultSort: findVM.sortText,
                    defaultProjection: findVM.projectionText,
                    documentKeys: findVM.documentKeysForCompletion,
                    isPresented: $showExportSheet
                )
            }
        }
        .sheet(isPresented: $showExplainSheet) {
            if let result = explainResult {
                ExplainResultView(result: result, isPresented: $showExplainSheet)
            }
        }
        .alert("Delete \(documentsToDelete?.count == 1 ? "Document" : "Documents")", isPresented: Binding(get: { documentsToDelete != nil }, set: { if !$0 { documentsToDelete = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let docs = documentsToDelete,
                   let db = sessionViewModel.selectedDatabase,
                   let col = sessionViewModel.selectedCollection {
                    Task {
                        _ = await findVM.deleteDocuments(
                            database: db,
                            collection: col,
                            documents: docs,
                            session: sessionViewModel
                        )
                    }
                }
            }
        } message: {
            if let count = documentsToDelete?.count, count > 1 {
                Text("Are you sure you want to delete these \(count) documents? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete this document? This action cannot be undone.")
            }
        }
        .alert("Delete Filtered Documents", isPresented: $confirmBulkDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let db = sessionViewModel.selectedDatabase,
                   let col = sessionViewModel.selectedCollection {
                    let docsToDelete = findVM.documents
                    Task {
                        _ = await findVM.deleteDocuments(
                            database: db,
                            collection: col,
                            documents: docsToDelete,
                            session: sessionViewModel
                        )
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete all \(findVM.documents.count) loaded documents matching the query filter? This action cannot be undone.")
        }
    }

    // MARK: - Toolbar Area

    private var toolbarArea: some View {
        VStack(spacing: 0) {
            // Filter Row
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        findVM.isAdvancedQuery.toggle()
                    }
                }) {
                    Image(systemName: findVM.isAdvancedQuery ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help(findVM.isAdvancedQuery ? "Simple Query" : "Advanced Query")

                JSONEditorView(
                    text: $findVM.filterText,
                    errorMessage: $filterError,
                    documentKeys: findVM.documentKeysForCompletion,
                    schemaFields: findVM.schemaFieldsForCompletion,
                    editorMode: .findFilter,
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



                // Explain button
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
                .disabled(hasSyntaxError || isExplaining)
                .opacity(hasSyntaxError ? 0.55 : 1)
                .help("Run explain plan for current query")

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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Sort")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                JSONEditorView(
                    text: $findVM.sortText,
                    errorMessage: $sortError,
                    documentKeys: findVM.documentKeysForCompletion,
                    schemaFields: findVM.schemaFieldsForCompletion,
                    editorMode: .sort,
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
                    schemaFields: findVM.schemaFieldsForCompletion,
                    editorMode: .projection,
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

            // Action buttons row: Update, Delete, Export
            HStack(spacing: 10) {
                Button(action: { showUpdateSheet = true }) {
                    Label("Update", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Update documents matching current filter")

                Button(action: { confirmBulkDelete = true }) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete documents matching current filter")

                Button(action: { showExportSheet = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export collection to JSON/NDJSON")

                Spacer()
            }
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
        let tableCache = findVM.documentTableCache
        let isPreparingTable = tableCache == nil && !findVM.documents.isEmpty

        return DocumentTableView(
            rows: tableCache?.rows ?? [],
            columns: tableCache?.columns ?? [],
            columnTypes: tableCache?.columnTypes ?? [:],
            selection: $findVM.selectedRowIds,
            isLoading: findVM.isLoading || isPreparingTable,
            onEdit: { doc in editingDocument = doc },
            onDelete: { docs in documentsToDelete = docs }
        )
        .task(id: findVM.tableCacheRequestID) {
            await findVM.prepareDocumentTableCache()
        }
    }

    private var jsonContent: some View {
        DocumentJSONView(
            documents: findVM.documents,
            timeZone: globalSettings.displayTimeZone,
            isLoading: findVM.isLoading,
            onSave: { originalDoc, updatedDoc in
                guard let db = sessionViewModel.selectedDatabase,
                      let col = sessionViewModel.selectedCollection else { return false }
                return await findVM.replaceDocument(
                    database: db,
                    collection: col,
                    originalDocument: originalDoc,
                    replacement: updatedDoc,
                    session: sessionViewModel
                )
            },
            onEdit: { doc in editingDocument = doc },
            onDelete: { docs in documentsToDelete = docs }
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

    private func runExplain() {
        guard !hasSyntaxError else { return }
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task {
            isExplaining = true
            defer { isExplaining = false }
            do {
                let filter = try MongoQueryParsing.parseFilter(findVM.filterText)
                let sort = findVM.isAdvancedQuery ? try MongoQueryParsing.parseQueryOption(findVM.sortText) : nil
                let projection = findVM.isAdvancedQuery ? try MongoQueryParsing.parseQueryOption(findVM.projectionText) : nil
                let raw = try await MongoService.shared.explainFind(
                    database: db,
                    collection: col,
                    filter: filter,
                    sort: sort,
                    projection: projection
                )
                let queryPlanner = raw["queryPlanner"]?.documentValue
                let executionStats = raw["executionStats"]?.documentValue
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

    private var hasSyntaxError: Bool {
        if filterError != nil { return true }
        if findVM.isAdvancedQuery && (sortError != nil || projectionError != nil) { return true }
        return false
    }
}
