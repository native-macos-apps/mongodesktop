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
            tableCacheTask?.cancel()
            tableCacheTask = nil
            tableCacheGeneration += 1
            tableCache = nil
        }
    }
    @Published var isLoading = false
    @Published var error: String?
    @Published var queryDuration: TimeInterval?

    // MARK: - Cache

    @Published private(set) var tableCache: TableDataCache?
    private var tableCacheTask: Task<Void, Never>?
    private var tableCacheGeneration = 0

    // MARK: - Task Tracking

    private var activeAggregateTask: Task<Void, Never>?
    private var aggregateGeneration = 0

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Cache Access

    var tableCacheRequestID: Int {
        tableCacheGeneration
    }

    func prepareTableCache() async {
        guard tableCache == nil, tableCacheTask == nil else { return }

        let snapshot = documents
        let generation = tableCacheGeneration
        if snapshot.isEmpty {
            tableCache = TableDataCache(documents: [])
            return
        }

        let task = Task { [weak self] in
            let cache = await Task.detached(priority: .userInitiated) {
                TableDataCache(documents: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            await self?.applyTableCache(cache, generation: generation)
        }
        tableCacheTask = task
        await task.value
    }

    // MARK: - Run Aggregate

    func runAggregate(database: String, collection: String, session: DatabaseSessionViewModel) async {
        activeAggregateTask?.cancel()
        aggregateGeneration += 1
        let generation = aggregateGeneration

        let task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            await self.performAggregate(database: database, collection: collection, session: session, generation: generation)
        }
        activeAggregateTask = task
        await task.value
    }

    private func performAggregate(database: String, collection: String, session: DatabaseSessionViewModel, generation: Int) async {
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
            guard isCurrentAggregate(generation), !Task.isCancelled else { return }
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

        if isCurrentAggregate(generation) {
            isLoading = false
            activeAggregateTask = nil
        }
    }

    // MARK: - Clear

    func clear() {
        activeAggregateTask?.cancel()
        tableCacheTask?.cancel()
        activeAggregateTask = nil
        tableCacheTask = nil
        aggregateGeneration += 1
        tableCacheGeneration += 1
        documents = []
        error = nil
        isLoading = false
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

    private func applyTableCache(_ cache: TableDataCache, generation: Int) {
        guard tableCacheGeneration == generation else { return }
        tableCache = cache
        tableCacheTask = nil
    }

    private func isCurrentAggregate(_ generation: Int) -> Bool {
        aggregateGeneration == generation
    }
}
