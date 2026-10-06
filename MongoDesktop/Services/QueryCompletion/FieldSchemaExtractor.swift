import Foundation
import SwiftBSON

enum FieldSchemaExtractor {

    // MARK: - Extract Schema Fields

    static func extractFields(
        from documents: [BSONDocument],
        maxDepth: Int = 3,
        sampleLimit: Int = 50
    ) -> [QueryCompletionItem] {
        guard !documents.isEmpty else { return [] }

        var fieldTypes: [String: String] = [:]
        let sample = documents.prefix(sampleLimit)

        for doc in sample {
            traverse(doc: doc, prefix: "", depth: 1, maxDepth: maxDepth, fieldTypes: &fieldTypes)
        }

        return fieldTypes.map { (path, typeName) in
            QueryCompletionItem(
                label: path,
                kind: .field(type: typeName),
                detail: "Field (\(typeName))",
                documentation: "Field `\(path)`\nType: `\(typeName)`",
                insertText: path,
                isKey: true
            )
        }.sorted { (a, b) -> Bool in
            // Prioritize _id first, then alphabetical
            if a.label == "_id" { return true }
            if b.label == "_id" { return false }
            return a.label < b.label
        }
    }

    // MARK: - Recursive Traversal

    private static func traverse(
        doc: BSONDocument,
        prefix: String,
        depth: Int,
        maxDepth: Int,
        fieldTypes: inout [String: String]
    ) {
        guard depth <= maxDepth else { return }

        for (key, bsonValue) in doc {
            let fullPath = prefix.isEmpty ? key : "\(prefix).\(key)"
            let typeName = describeBSONType(bsonValue)

            if fieldTypes[fullPath] == nil {
                fieldTypes[fullPath] = typeName
            }

            if case .document(let subDoc) = bsonValue {
                traverse(
                    doc: subDoc,
                    prefix: fullPath,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    fieldTypes: &fieldTypes
                )
            }
        }
    }

    // MARK: - Type Mapping

    static func describeBSONType(_ value: BSON) -> String {
        switch value {
        case .string: return "String"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .double: return "Double"
        case .decimal128: return "Decimal128"
        case .bool: return "Bool"
        case .objectID: return "ObjectId"
        case .datetime: return "Date"
        case .array: return "Array"
        case .document: return "Object"
        case .binary: return "Binary"
        case .regex: return "Regex"
        case .null: return "Null"
        case .timestamp: return "Timestamp"
        case .minKey: return "MinKey"
        case .maxKey: return "MaxKey"
        default: return "Any"
        }
    }
}
