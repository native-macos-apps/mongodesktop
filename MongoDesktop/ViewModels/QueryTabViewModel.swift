import SwiftUI
import SwiftBSON

enum DocumentViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case json = "JSON"

    var id: String { rawValue }
}

enum CollectionTab: String, CaseIterable, Identifiable {
    case document = "Document"
    case aggregate = "Aggregate"
    case index = "Index"

    var id: String { rawValue }
}

@MainActor
final class QueryTabViewModel: ObservableObject {
    @Published var title = ""
    @Published var databaseName: String?
    @Published var collectionName: String?
    @Published var filterText = "{}"
    @Published var sortText = "{}"
    @Published var projectionText = "{}"
    @Published var isAdvancedQuery = false
    @Published var viewMode: DocumentViewMode = .json
    @Published var pageSize = 100
    @Published var currentPage = 0
    @Published var hasMore = false
    @Published var documents: [BSONDocument] = [] {
        didSet {
            documentTableCache = TableDataCache(documents: documents)
            documentJSONCache = nil
        }
    }
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading = false
    @Published var lastQueryDuration: TimeInterval?

    @Published var selectedTab: CollectionTab = .document
    @Published var aggregatePipelineText = "[\n    {\n        \"$match\": {}\n    }\n]"
    @Published var aggregateDocuments: [BSONDocument] = [] {
        didSet {
            aggregateTableCache = TableDataCache(documents: aggregateDocuments)
            aggregateJSONCache = nil
        }
    }
    @Published var isAggregateLoading = false
    @Published var aggregateError: String? = nil
    @Published var aggregateQueryDuration: TimeInterval? = nil
    
    @Published var indexes: [BSONDocument] = []
    @Published var indexStats: [String: (size: Int64, usage: Int64)] = [:]
    @Published var isIndexesLoading = false
    @Published var indexesError: String? = nil

    // MARK: - Caching for Performance
    @Published var documentTableCache = TableDataCache(documents: [])
    @Published var aggregateTableCache = TableDataCache(documents: [])

    private var documentJSONCache: [JSONDocumentWrapper]? = nil
    private var documentJSONTimeZone: TimeZone? = nil
    
    private var aggregateJSONCache: [JSONDocumentWrapper]? = nil
    private var aggregateJSONTimeZone: TimeZone? = nil

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

    func getAggregateJSONCache(timeZone: TimeZone) -> [JSONDocumentWrapper] {
        if let cache = aggregateJSONCache, aggregateJSONTimeZone == timeZone {
            return cache
        }
        let cache = aggregateDocuments.enumerated().map { index, doc in
            let id: String
            if let rawId = doc["_id"] {
                id = "id-\(String(describing: rawId))"
            } else {
                id = "idx-\(index)"
            }
            let nodes = doc.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
            return JSONDocumentWrapper(id: id, index: index, document: doc, nodes: nodes)
        }
        self.aggregateJSONCache = cache
        self.aggregateJSONTimeZone = timeZone
        return cache
    }


    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    func configure(database: String?, collection: String?) {
        if let database, !database.isEmpty {
            databaseName = database
        }
        if let collection, !collection.isEmpty {
            collectionName = collection
            title = collection
        } else if let database, !database.isEmpty, title.isEmpty {
            title = database
        }
    }

    func clearSelection() {
        databaseName = nil
        collectionName = nil
        title = ""
        documents = []
        selectedRowIds = []
        hasMore = false
        currentPage = 0
        lastQueryDuration = nil
        
        selectedTab = .document
        aggregateDocuments = []
        aggregateError = nil
        aggregateQueryDuration = nil
        indexes = []
        indexStats = [:]
        indexesError = nil
    }

    func resetPaging() {
        currentPage = 0
    }

    func runFind(using session: DatabaseSessionViewModel) async {
        guard let database = databaseName ?? session.selectedDatabase,
              let collection = collectionName ?? session.selectedCollection else {
            return
        }

        if databaseName == nil {
            databaseName = database
        }
        if collectionName == nil {
            collectionName = collection
        }

        await runFind(database: database, collection: collection, session: session)
    }

    func nextPage(using session: DatabaseSessionViewModel) async {
        guard hasMore else { return }
        currentPage += 1
        await runFind(using: session)
    }

    func previousPage(using session: DatabaseSessionViewModel) async {
        guard currentPage > 0 else { return }
        currentPage -= 1
        await runFind(using: session)
    }

    private func runFind(database: String, collection: String, session: DatabaseSessionViewModel) async {
        isLoading = true
        title = collection
        session.lastError = nil
        lastQueryDuration = nil

        let start = Date()

        do {
            let filter = try parseFilter(filterText)
            let sort = isAdvancedQuery ? try parseQueryOption(sortText) : nil
            let projection = isAdvancedQuery ? try parseQueryOption(projectionText) : nil
            let skip = currentPage * pageSize
            let documents = try await mongoService.findDocuments(
                database: database,
                collection: collection,
                filter: filter,
                sort: sort,
                projection: projection,
                limit: pageSize,
                skip: skip
            )

            self.documents = documents
            hasMore = documents.count == pageSize
            selectedRowIds = []
            lastQueryDuration = Date().timeIntervalSince(start)
        } catch {
            session.lastError = error.localizedDescription
        }

        isLoading = false
    }

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

    func runAggregate(using session: DatabaseSessionViewModel) async {
        guard let database = databaseName ?? session.selectedDatabase,
              let collection = collectionName ?? session.selectedCollection else {
            return
        }
        
        isAggregateLoading = true
        aggregateError = nil
        aggregateQueryDuration = nil
        
        let start = Date()
        
        do {
            let pipeline = try parsePipeline(aggregatePipelineText)
            let results = try await mongoService.runAggregate(
                database: database,
                collection: collection,
                pipeline: pipeline
            )
            self.aggregateDocuments = results
            self.aggregateQueryDuration = Date().timeIntervalSince(start)
        } catch {
            self.aggregateError = error.localizedDescription
            session.lastError = error.localizedDescription
        }
        
        isAggregateLoading = false
    }
    
    func fetchIndexes(using session: DatabaseSessionViewModel) async {
        guard let database = databaseName ?? session.selectedDatabase,
              let collection = collectionName ?? session.selectedCollection else {
            return
        }
        
        isIndexesLoading = true
        indexesError = nil
        
        do {
            let results = try await mongoService.listIndexes(
                database: database,
                collection: collection
            )
            let stats = (try? await mongoService.getIndexStats(
                database: database,
                collection: collection
            )) ?? [:]
            
            self.indexes = results
            self.indexStats = stats
        } catch {
            self.indexesError = error.localizedDescription
            session.lastError = error.localizedDescription
        }
        
        isIndexesLoading = false
    }
    
    private func parsePipeline(_ text: String) throws -> [BSONDocument] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" {
            return []
        }
        
        let converted = BSONQueryParser.convertBSONToJSON(trimmed)
        
        guard let data = converted.data(using: .utf8) else {
            throw MongoServiceError.bsonError("Invalid encoding in pipeline text.")
        }
        
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let jsonArray = jsonObject as? [[String: Any]] else {
            throw MongoServiceError.bsonError("Pipeline must be a JSON Array of objects.")
        }
        
        var pipelineDocs: [BSONDocument] = []
        for obj in jsonArray {
            let objData = try JSONSerialization.data(withJSONObject: obj, options: [])
            let jsonString = String(data: objData, encoding: .utf8) ?? "{}"
            let doc = try BSONDocument(fromJSON: jsonString)
            pipelineDocs.append(doc)
        }
        
        return pipelineDocs
    }
}

// MARK: - TableDataCache

struct TableDataCache {
    let rows: [DocumentRow]
    let columns: [String]
    let columnTypes: [String: String]
    
    init(documents: [BSONDocument]) {
        self.rows = documents.enumerated().map { index, doc in
            DocumentRow(document: doc, fallbackIndex: index)
        }
        
        var keys = Set<String>()
        for row in rows {
            for pair in row.document {
                keys.insert(pair.key)
            }
        }
        
        if keys.isEmpty {
            self.columns = []
            self.columnTypes = [:]
            return
        }
        
        self.columns = keys.sorted { lhs, rhs in
            if lhs == "_id" { return true }
            if rhs == "_id" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        
        var types: [String: String] = [:]
        for key in columns {
            var observedTypes = Set<String>()
            for row in rows {
                if let value = row.document[key] {
                    observedTypes.insert(Self.typeName(for: value))
                }
            }
            if observedTypes.isEmpty {
                types[key] = "Unknown"
            } else if observedTypes.count == 1 {
                types[key] = observedTypes.first!
            } else {
                types[key] = "Mixed"
            }
        }
        self.columnTypes = types
    }
    
    private static func typeName(for value: BSON) -> String {
        switch value {
        case .double: return "Double"
        case .string: return "String"
        case .document: return "Object"
        case .array: return "Array"
        case .binary: return "Binary"
        case .objectID: return "ObjectId"
        case .bool: return "Bool"
        case .datetime: return "Date"
        case .null: return "Null"
        case .regex: return "Regex"
        case .int32: return "Int32"
        case .timestamp: return "Timestamp"
        case .int64: return "Int64"
        case .decimal128: return "Decimal"
        case .maxKey: return "MaxKey"
        case .minKey: return "MinKey"
        default: return "Unknown"
        }
    }
}

// MARK: - JSONDocumentWrapper

struct JSONDocumentWrapper: Identifiable {
    let id: String
    let index: Int
    let document: BSONDocument
    let nodes: [JSONNode]
}

