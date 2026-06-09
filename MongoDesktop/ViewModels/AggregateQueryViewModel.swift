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
            tableCacheController.invalidate()
            tableCache = nil
        }
    }
    @Published var isLoading = false
    @Published var error: String?
    @Published var queryDuration: TimeInterval?

    // MARK: - Cache

    @Published private(set) var tableCache: TableDataCache?
    private let tableCacheController = TableCacheController()

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
        tableCacheController.generation
    }

    func prepareTableCache() async {
        tableCache = await tableCacheController.prepareCache(
            currentCache: tableCache,
            documents: documents
        )
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
            let pipeline = try MongoQueryParsing.parsePipeline(pipelineText)
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
        activeAggregateTask = nil
        aggregateGeneration += 1
        tableCacheController.invalidate()
        documents = []
        error = nil
        isLoading = false
        queryDuration = nil
    }

    private func isCurrentAggregate(_ generation: Int) -> Bool {
        aggregateGeneration == generation
    }
}
