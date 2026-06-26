import SwiftUI
import SwiftBSON

// MARK: - DocumentQueryViewModel

@MainActor
final class DocumentQueryViewModel: ObservableObject {

    // MARK: - Query State

    @Published var filterText = "{}"
    @Published var sortText = "{}"
    @Published var projectionText = "{}"
    @Published var isAdvancedQuery = false
    @Published var viewMode: DocumentViewMode = .json
    @Published var showAddSheet = false

    // MARK: - Pagination

    @Published var pageSize = 100
    @Published var currentPage = 0
    @Published var offset = 0
    @Published var totalDocuments = 0
    @Published var hasMore = false

    // MARK: - Results

    @Published var documents: [BSONDocument] = [] {
        didSet {
            tableCacheController.invalidate()
            documentTableCache = nil
        }
    }
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading = false
    @Published var lastQueryDuration: TimeInterval?

    // MARK: - Cache

    @Published private(set) var documentTableCache: TableDataCache?
    private let tableCacheController = TableCacheController()

    // MARK: - Task Tracking

    private var activeFindTask: Task<Void, Never>?
    private var findGeneration = 0

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Cache Access

    var documentKeysForCompletion: [String] {
        documentTableCache?.columns ?? []
    }

    var tableCacheRequestID: Int {
        tableCacheController.generation
    }

    func prepareDocumentTableCache() async {
        documentTableCache = await tableCacheController.prepareCache(
            currentCache: documentTableCache,
            documents: documents
        )
    }

    // MARK: - Paging

    func resetPaging() {
        currentPage = 0
        offset = 0
    }

    func nextPage(database: String, collection: String, session: DatabaseSessionViewModel) async {
        guard hasMore else { return }
        currentPage += 1
        offset += pageSize
        await runFind(database: database, collection: collection, session: session)
    }

    func previousPage(database: String, collection: String, session: DatabaseSessionViewModel) async {
        guard offset > 0 else { return }
        offset = max(0, offset - pageSize)
        currentPage = pageSize > 0 ? offset / pageSize : 0
        await runFind(database: database, collection: collection, session: session)
    }

    func applyPaging(offset: Int, limit: Int, database: String, collection: String, session: DatabaseSessionViewModel) async {
        pageSize = max(1, limit)
        self.offset = max(0, offset)
        currentPage = self.offset / pageSize
        await runFind(database: database, collection: collection, session: session)
    }

    // MARK: - Run Find

    func runFind(database: String, collection: String, session: DatabaseSessionViewModel) async {
        activeFindTask?.cancel()
        findGeneration += 1
        let generation = findGeneration

        let task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            await self.performFind(database: database, collection: collection, session: session, generation: generation)
        }
        activeFindTask = task
        await task.value
    }

    private func performFind(database: String, collection: String, session: DatabaseSessionViewModel, generation: Int) async {
        isLoading = true
        session.lastError = nil
        lastQueryDuration = nil

        let start = Date()
        var queryLabel = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isAdvancedQuery {
            queryLabel += " | sort: \(sortText.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        do {
            let filter = try MongoQueryParsing.parseFilter(filterText)
            let sort = isAdvancedQuery ? try MongoQueryParsing.parseQueryOption(sortText) : nil
            let projection = isAdvancedQuery ? try MongoQueryParsing.parseQueryOption(projectionText) : nil
            let skip = offset
            let total = try await mongoService.countDocuments(
                database: database,
                collection: collection,
                filter: filter
            )
            guard isCurrentFind(generation), !Task.isCancelled else { return }

            let results = try await mongoService.findDocuments(
                database: database,
                collection: collection,
                filter: filter,
                sort: sort,
                projection: projection,
                limit: pageSize,
                skip: skip
            )
            guard isCurrentFind(generation), !Task.isCancelled else { return }

            self.documents = results
            totalDocuments = total
            hasMore = skip + results.count < total
            selectedRowIds = []
            let duration = Date().timeIntervalSince(start)
            lastQueryDuration = duration
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .find,
                queryText: queryLabel,
                duration: duration,
                resultCount: results.count
            )
        } catch {
            let duration = Date().timeIntervalSince(start)
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .find,
                queryText: queryLabel,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
        }

        if isCurrentFind(generation) {
            isLoading = false
            activeFindTask = nil
        }
    }

    // MARK: - Clear

    func clear() {
        activeFindTask?.cancel()
        activeFindTask = nil
        findGeneration += 1
        tableCacheController.invalidate()
        documents = []
        selectedRowIds = []
        isLoading = false
        hasMore = false
        currentPage = 0
        offset = 0
        totalDocuments = 0
        lastQueryDuration = nil
    }

    // MARK: - Mutations

    func insertDocument(
        database: String,
        collection: String,
        document: BSONDocument,
        session: DatabaseSessionViewModel
    ) async -> Bool {
        isLoading = true
        session.lastError = nil
        let start = Date()
        let queryLabel = document.toRelaxedExtendedJSONString()
        do {
            try await mongoService.insertDocument(database: database, collection: collection, document: document)
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .insert,
                queryText: queryLabel,
                duration: duration,
                resultCount: 1
            )
            await runFind(database: database, collection: collection, session: session)
            return true
        } catch {
            let duration = Date().timeIntervalSince(start)
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .insert,
                queryText: queryLabel,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
            isLoading = false
            return false
        }
    }

    func replaceDocument(
        database: String,
        collection: String,
        originalDocument: BSONDocument,
        replacement: BSONDocument,
        session: DatabaseSessionViewModel
    ) async -> Bool {
        isLoading = true
        session.lastError = nil
        let start = Date()

        let filter: BSONDocument
        if let id = originalDocument["_id"] {
            filter = ["_id": id]
        } else {
            filter = originalDocument
        }

        var finalReplacement = replacement
        if let originalId = originalDocument["_id"] {
            if finalReplacement["_id"] == nil {
                finalReplacement["_id"] = originalId
            } else if finalReplacement["_id"] != originalId {
                session.lastError = "Cannot modify the immutable field '_id'."
                isLoading = false
                return false
            }
        }

        let queryLabel = "Filter: \(filter.toRelaxedExtendedJSONString()), Replacement: \(finalReplacement.toRelaxedExtendedJSONString())"

        do {
            try await mongoService.replaceDocument(
                database: database,
                collection: collection,
                filter: filter,
                replacement: finalReplacement
            )
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .update,
                queryText: queryLabel,
                duration: duration,
                resultCount: 1
            )
            await runFind(database: database, collection: collection, session: session)
            return true
        } catch {
            let duration = Date().timeIntervalSince(start)
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .update,
                queryText: queryLabel,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
            isLoading = false
            return false
        }
    }

    func deleteDocuments(
        database: String,
        collection: String,
        documents: [BSONDocument],
        session: DatabaseSessionViewModel
    ) async -> Bool {
        isLoading = true
        session.lastError = nil
        let start = Date()

        // Build filters
        let filters: [BSONDocument] = documents.map { doc in
            if let id = doc["_id"] {
                return ["_id": id]
            } else {
                return doc
            }
        }

        let queryLabel = "Deleted \(documents.count) documents. Filters: " + filters.map { $0.toRelaxedExtendedJSONString() }.joined(separator: ", ")

        do {
            for filter in filters {
                try await mongoService.deleteDocument(database: database, collection: collection, filter: filter)
            }
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .delete,
                queryText: queryLabel,
                duration: duration,
                resultCount: documents.count
            )
            await runFind(database: database, collection: collection, session: session)
            return true
        } catch {
            let duration = Date().timeIntervalSince(start)
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .delete,
                queryText: queryLabel,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
            isLoading = false
            return false
        }
    }

    private func isCurrentFind(_ generation: Int) -> Bool {
        findGeneration == generation
    }
}
