import SwiftUI

// MARK: - QueryHistoryEntry

struct QueryHistoryEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let database: String
    let collection: String
    let queryType: QueryHistoryType
    let queryText: String
    let duration: TimeInterval?
    let resultCount: Int?
    let isError: Bool
    let errorMessage: String?
}

// MARK: - QueryHistoryType

enum QueryHistoryType: String {
    case find = "find"
    case aggregate = "aggregate"
    case index = "listIndexes"
    case insert = "insert"
    case update = "update"
    case delete = "delete"

    var icon: String {
        switch self {
        case .find: return "magnifyingglass"
        case .aggregate: return "square.3.layers.3d.down.right.fill"
        case .index: return "list.bullet.rectangle"
        case .insert: return "plus.circle"
        case .update: return "pencil.circle"
        case .delete: return "trash.circle"
        }
    }

    var color: Color {
        switch self {
        case .find: return .blue
        case .aggregate: return .purple
        case .index: return .orange
        case .insert: return .green
        case .update: return .yellow
        case .delete: return .red
        }
    }
}

// MARK: - QueryHistoryStore

@MainActor
final class QueryHistoryStore: ObservableObject {
    static let shared = QueryHistoryStore()
    private init() {}

    @Published private(set) var entries: [QueryHistoryEntry] = []

    func record(
        database: String,
        collection: String,
        queryType: QueryHistoryType,
        queryText: String,
        duration: TimeInterval? = nil,
        resultCount: Int? = nil,
        isError: Bool = false,
        errorMessage: String? = nil
    ) {
        let entry = QueryHistoryEntry(
            timestamp: Date(),
            database: database,
            collection: collection,
            queryType: queryType,
            queryText: queryText,
            duration: duration,
            resultCount: resultCount,
            isError: isError,
            errorMessage: errorMessage
        )
        entries.insert(entry, at: 0)
        // Cap at 500 entries per session
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
    }

    func clear() {
        entries = []
    }
}
