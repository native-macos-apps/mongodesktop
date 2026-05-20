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
    @Published var hasMore = false

    // MARK: - Results

    @Published var documents: [BSONDocument] = [] {
        didSet {
            documentTableCache = TableDataCache(documents: documents)
            documentJSONCache = nil
        }
    }
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading = false
    @Published var lastQueryDuration: TimeInterval?

    // MARK: - Cache

    @Published var documentTableCache = TableDataCache(documents: [])
    private var documentJSONCache: [JSONDocumentWrapper]?
    private var documentJSONTimeZone: TimeZone?

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Cache Access

    func getDocumentJSONCache(timeZone: TimeZone) -> [JSONDocumentWrapper] {
        if let cache = documentJSONCache, documentJSONTimeZone == timeZone {
            return cache
        }
        let cache = documents.enumerated().map { index, doc in
            let id: String
            if let rawId = doc["_id"] {
                id = "id-\(String(describing: rawId))"
            } else {
                id = "idx-\(index)"
            }
            let nodes = doc.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
            return JSONDocumentWrapper(id: id, index: index, document: doc, nodes: nodes)
        }
        self.documentJSONCache = cache
        self.documentJSONTimeZone = timeZone
        return cache
    }

    // MARK: - Paging

    func resetPaging() {
        currentPage = 0
    }

    func nextPage(database: String, collection: String, session: DatabaseSessionViewModel) async {
        guard hasMore else { return }
        currentPage += 1
        await runFind(database: database, collection: collection, session: session)
    }

    func previousPage(database: String, collection: String, session: DatabaseSessionViewModel) async {
        guard currentPage > 0 else { return }
        currentPage -= 1
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
            let skip = currentPage * pageSize

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
            hasMore = results.count == pageSize
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
