import SwiftUI
import SwiftBSON

// MARK: - Supporting Types

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

// MARK: - QueryTabViewModel (Coordinator)

@MainActor
final class QueryTabViewModel: ObservableObject {

    // MARK: - Shared State

    @Published var title = ""
    @Published var databaseName: String?
    @Published var collectionName: String?
    @Published var selectedTab: CollectionTab = .document

    // MARK: - Sub-ViewModels

    let find: DocumentQueryViewModel
    let aggregate: AggregateQueryViewModel
    let index: IndexQueryViewModel

    // MARK: - Init

    init(mongoService: MongoService = .shared) {
        self.find = DocumentQueryViewModel(mongoService: mongoService)
        self.aggregate = AggregateQueryViewModel(mongoService: mongoService)
        self.index = IndexQueryViewModel(mongoService: mongoService)
    }

    // MARK: - Configuration

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

    func openCollection(database: String, collection: String, session: DatabaseSessionViewModel) {
        configure(database: database, collection: collection)
        session.selectCollection(database: database, collection: collection)
        loadInitialDocuments(database: database, collection: collection, session: session)
    }

    func loadInitialDocumentsIfPossible(session: DatabaseSessionViewModel) {
        guard let databaseName, let collectionName else { return }
        loadInitialDocuments(database: databaseName, collection: collectionName, session: session)
    }

    func clearSelection() {
        databaseName = nil
        collectionName = nil
        title = ""
        selectedTab = .document

        find.clear()
        aggregate.clear()
        index.clear()
    }

    private func loadInitialDocuments(database: String, collection: String, session: DatabaseSessionViewModel) {
        find.isLoading = true
        find.documents = []
        Task { [find] in
            await find.runFind(database: database, collection: collection, session: session)
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
