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
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(findVM.isAdvancedQuery ? Color.accentColor : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help(findVM.isAdvancedQuery ? "Simple Query" : "Advanced Query")

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

    private var hasSyntaxError: Bool {
        if filterError != nil { return true }
        if findVM.isAdvancedQuery && (sortError != nil || projectionError != nil) { return true }
        return false
    }
}
