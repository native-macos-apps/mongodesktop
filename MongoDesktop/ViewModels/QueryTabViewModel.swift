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

    func clearSelection() {
        databaseName = nil
        collectionName = nil
        title = ""
        selectedTab = .document

        find.clear()
        aggregate.clear()
        index.clear()
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
