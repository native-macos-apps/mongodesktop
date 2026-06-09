import Foundation
import SwiftBSON

enum MongoQueryParsing {
    static func parseFilter(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return BSONDocument()
        }
        let converted = BSONQueryParser.convertBSONToJSON(trimmed)
        return try BSONDocument(fromJSON: converted)
    }

    static func parseQueryOption(_ text: String) throws -> BSONDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return nil
        }
        let converted = BSONQueryParser.convertBSONToJSON(trimmed)
        return try BSONDocument(fromJSON: converted)
    }

    static func parsePipeline(_ text: String) throws -> [BSONDocument] {
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

        return try jsonArray.map { object in
            let objectData = try JSONSerialization.data(withJSONObject: object, options: [])
            let jsonString = String(data: objectData, encoding: .utf8) ?? "{}"
            return try BSONDocument(fromJSON: jsonString)
        }
    }
}
