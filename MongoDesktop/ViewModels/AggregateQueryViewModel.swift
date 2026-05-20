import SwiftUI
import SwiftBSON

// MARK: - AggregateQueryViewModel

@MainActor
final class AggregateQueryViewModel: ObservableObject {

    // MARK: - Pipeline State

    @Published var pipelineText = "[\n    {\n        \"$match\": {}\n    }\n]"

    // MARK: - Results

    @Published var documents: [BSONDocument] = [] {
        didSet {
            tableCache = TableDataCache(documents: documents)
            jsonCache = nil
        }
    }
    @Published var isLoading = false
    @Published var error: String?
    @Published var queryDuration: TimeInterval?

    // MARK: - Cache

    @Published var tableCache = TableDataCache(documents: [])
    private var jsonCache: [JSONDocumentWrapper]?
    private var jsonCacheTimeZone: TimeZone?

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Cache Access

    func getJSONCache(timeZone: TimeZone) -> [JSONDocumentWrapper] {
        if let cache = jsonCache, jsonCacheTimeZone == timeZone {
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
        self.jsonCache = cache
        self.jsonCacheTimeZone = timeZone
        return cache
    }

    // MARK: - Run Aggregate

    func runAggregate(database: String, collection: String, session: DatabaseSessionViewModel) async {
        isLoading = true
        error = nil
        queryDuration = nil

        let start = Date()
        let pipelineLabel = pipelineText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let pipeline = try parsePipeline(pipelineText)
            let results = try await mongoService.runAggregate(
                database: database,
                collection: collection,
                pipeline: pipeline
            )
            self.documents = results
            let duration = Date().timeIntervalSince(start)
            self.queryDuration = duration
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .aggregate,
                queryText: pipelineLabel,
                duration: duration,
                resultCount: results.count
            )
        } catch let err {
            let duration = Date().timeIntervalSince(start)
            self.error = err.localizedDescription
            session.lastError = err.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .aggregate,
                queryText: pipelineLabel,
                duration: duration,
                isError: true,
                errorMessage: err.localizedDescription
            )
        }

        isLoading = false
    }

    // MARK: - Clear

    func clear() {
        documents = []
        error = nil
        queryDuration = nil
    }

    // MARK: - Parsing

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
