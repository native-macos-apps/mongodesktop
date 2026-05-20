import SwiftUI
import SwiftBSON

// MARK: - IndexQueryViewModel

@MainActor
final class IndexQueryViewModel: ObservableObject {

    // MARK: - State

    @Published var indexes: [BSONDocument] = []
    @Published var indexStats: [String: (size: Int64, usage: Int64)] = [:]
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Fetch Indexes

    func fetchIndexes(database: String, collection: String, session: DatabaseSessionViewModel) async {
        isLoading = true
        error = nil

        let start = Date()

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
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: "listIndexes()",
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
                queryType: .index,
                queryText: "listIndexes()",
                duration: duration,
                isError: true,
                errorMessage: err.localizedDescription
            )
        }

        isLoading = false
    }

    // MARK: - Clear

    func clear() {
        indexes = []
        indexStats = [:]
        error = nil
    }
}
