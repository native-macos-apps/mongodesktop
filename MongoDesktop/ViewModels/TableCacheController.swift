import Foundation
import SwiftBSON

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

@MainActor
final class TableCacheController {
    private var task: Task<TableDataCache, Never>?
    private var taskGeneration: Int?
    private(set) var generation = 0

    func invalidate() {
        task?.cancel()
        task = nil
        taskGeneration = nil
        generation += 1
    }

    func prepareCache(currentCache: TableDataCache?, documents: [BSONDocument]) async -> TableDataCache? {
        if let currentCache {
            return currentCache
        }

        let requestedGeneration = generation
        if documents.isEmpty {
            return TableDataCache(documents: [])
        }

        let cacheTask: Task<TableDataCache, Never>
        if let task, taskGeneration == requestedGeneration {
            cacheTask = task
        } else {
            let snapshot = documents
            cacheTask = Task {
                await Task.detached(priority: .userInitiated) {
                    TableDataCache(documents: snapshot)
                }.value
            }
            task = cacheTask
            taskGeneration = requestedGeneration
        }

        let cache = await cacheTask.value
        guard !cacheTask.isCancelled, generation == requestedGeneration else {
            return nil
        }

        if taskGeneration == requestedGeneration {
            task = nil
            taskGeneration = nil
        }
        return cache
    }
}
