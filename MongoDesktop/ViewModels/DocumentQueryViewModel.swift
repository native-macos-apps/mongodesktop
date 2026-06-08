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
            documentTableCache = nil
        }
    }
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading = false
    @Published var lastQueryDuration: TimeInterval?

    // MARK: - Cache

    private var documentTableCache: TableDataCache?

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Cache Access

    var documentKeysForCompletion: [String] {
        documentTableCache?.columns ?? []
    }

    func getDocumentTableCache() -> TableDataCache {
        if let documentTableCache {
            return documentTableCache
        }

        let cache = TableDataCache(documents: documents)
        documentTableCache = cache
        return cache
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

            let results = try await mongoService.findDocuments(
                database: database,
                collection: collection,
                filter: filter,
                sort: sort,
                projection: projection,
                limit: pageSize,
                skip: skip
            )

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

        isLoading = false
    }

    // MARK: - Clear

    func clear() {
        documents = []
        selectedRowIds = []
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
}
