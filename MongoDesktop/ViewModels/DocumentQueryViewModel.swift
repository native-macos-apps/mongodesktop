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

    // MARK: - Pagination

    @Published var pageSize = 100
    @Published var currentPage = 0
    @Published var offset = 0
    @Published var totalDocuments = 0
    @Published var hasMore = false

    // MARK: - Results

    @Published var documents: [BSONDocument] = [] {
        didSet {
            tableCacheTask?.cancel()
            tableCacheTask = nil
            tableCacheGeneration += 1
            documentTableCache = nil
        }
    }
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading = false
    @Published var lastQueryDuration: TimeInterval?

    // MARK: - Cache

    @Published private(set) var documentTableCache: TableDataCache?
    private var tableCacheTask: Task<Void, Never>?
    private var tableCacheGeneration = 0

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
        tableCacheGeneration
    }

    func prepareDocumentTableCache() async {
        guard documentTableCache == nil, tableCacheTask == nil else { return }

        let snapshot = documents
        let generation = tableCacheGeneration
        if snapshot.isEmpty {
            documentTableCache = TableDataCache(documents: [])
            return
        }

        let task = Task { [weak self] in
            let cache = await Task.detached(priority: .userInitiated) {
                TableDataCache(documents: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            await self?.applyDocumentTableCache(cache, generation: generation)
        }
        tableCacheTask = task
        await task.value
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
            let filter = try parseFilter(filterText)
            let sort = isAdvancedQuery ? try parseQueryOption(sortText) : nil
            let projection = isAdvancedQuery ? try parseQueryOption(projectionText) : nil
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
        tableCacheTask?.cancel()
        activeFindTask = nil
        tableCacheTask = nil
        findGeneration += 1
        tableCacheGeneration += 1
        documents = []
        selectedRowIds = []
        isLoading = false
        hasMore = false
        currentPage = 0
        offset = 0
        totalDocuments = 0
        lastQueryDuration = nil
    }

    // MARK: - Parsing

    private func parseFilter(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return BSONDocument()
        }
        let converted = BSONQueryParser.convertBSONToJSON(trimmed)
        return try BSONDocument(fromJSON: converted)
    }

    private func parseQueryOption(_ text: String) throws -> BSONDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return nil
        }
        let converted = BSONQueryParser.convertBSONToJSON(trimmed)
        return try BSONDocument(fromJSON: converted)
    }

    private func applyDocumentTableCache(_ cache: TableDataCache, generation: Int) {
        guard tableCacheGeneration == generation else { return }
        documentTableCache = cache
        tableCacheTask = nil
    }

    private func isCurrentFind(_ generation: Int) -> Bool {
        findGeneration == generation
    }
}
