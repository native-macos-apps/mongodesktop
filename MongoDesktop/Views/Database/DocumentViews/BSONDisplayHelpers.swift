import Foundation
import SwiftBSON

// MARK: - Display Helpers (shared between Table and JSON views)

let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter
}()

func displayValue(_ value: BSON?, timeZone: TimeZone) -> String {
    guard let value else { return "" }
    switch value {
    case .document(let doc):
        return "{} \(doc.count) fields"
    case .array(let arr):
        return "[] \(arr.count) items"
    case .string(let s):
        return s
    case .double(let d):
        return String(d)
    case .int32(let i):
        return String(i)
    case .int64(let i):
        return String(i)
    case .bool(let b):
        return String(b)
    case .null:
        return "null"
    case .datetime(let d):
        displayDateFormatter.timeZone = timeZone
        return displayDateFormatter.string(from: d)
    case .binary(let binary):
        if let uuid = try? binary.toUUID() {
            return "UUID(\"\(uuid.uuidString.lowercased())\")"
        }
        return String(describing: value)
    case .objectID(let id):
        return "ObjectId(\"\(id)\")"
    default:
        return String(describing: value)
    }
}

extension BSON {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var intValue: Int? {
        switch self {
        case .int32(let i): return Int(i)
        case .int64(let i): return Int(i)
        case .double(let d): return Int(d)
        default: return nil
        }
    }
    var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
    var documentValue: BSONDocument? {
        if case .document(let d) = self { return d }
        return nil
    }
}

