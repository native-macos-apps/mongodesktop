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
        } catch let err {
            self.error = err.localizedDescription
            session.lastError = err.localizedDescription
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
