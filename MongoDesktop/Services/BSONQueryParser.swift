import Foundation
import SwiftBSON

struct BSONToken {
    enum Kind {
        case string(value: String, quote: Character)
        case number(String)
        case identifier(String)
        case regex(pattern: String, flags: String)
        case punctuation(Character)
        case comment(String)
        case whitespace(String)
    }
    let kind: Kind
    let raw: String
}

enum BSONQueryParser {
    static func convertBSONToJSON(_ source: String) -> String {
        let tokens = tokenize(source)
        var result = ""
        var i = 0
        
        while i < tokens.count {
            let token = tokens[i]
            
            // Check if it's the "new" keyword followed by a BSON helper
            if case .identifier("new") = token.kind {
                if let nextIdx = nextNonWhitespaceIndex(from: i, in: tokens),
                   case .identifier(let name) = tokens[nextIdx].kind,
                   isBSONHelper(name) {
                    // Skip the "new" token and proceed
                    i = nextIdx
                    continue
                }
            }
            
            // Handle BSON helper functions
            if case .identifier(let name) = token.kind, isBSONHelper(name) {
                if let (args, nextIdx) = parseHelperArgs(startingAt: i, in: tokens) {
                    let processed = processBSONHelper(name: name, args: args)
                    result.append(processed)
                    i = nextIdx
                    continue
                } else if name == "MinKey" || name == "MaxKey" {
                    // Handle MinKey/MaxKey without parens
                    let processed = processBSONHelper(name: name, args: [])
                    result.append(processed)
                    i += 1
                    continue
                }
            }
            
            // Handle regex literals
            if case .regex(let pattern, let flags) = token.kind {
                let escapedPattern = escapeStringForJSON(pattern)
                result.append("{\"$regularExpression\": {\"pattern\": \"\(escapedPattern)\", \"options\": \"\(flags)\"}}")
                i += 1
                continue
            }
            
            // Handle object keys (identifier followed by a colon)
            if case .identifier(let name) = token.kind {
                if let nextIdx = nextNonWhitespaceIndex(from: i, in: tokens),
                   case .punctuation(":") = tokens[nextIdx].kind {
                    result.append("\"\(name)\"")
                    i += 1
                    continue
                }
            }
            
            // Handle single-quoted strings: convert them to double-quoted strings
            if case .string(let val, let quote) = token.kind {
                if quote == "'" {
                    let escapedVal = escapeStringForJSON(val)
                    result.append("\"\(escapedVal)\"")
                    i += 1
                    continue
                }
            }
            
            // Default: append raw representation
            result.append(token.raw)
            i += 1
        }
        
        return result
    }
    
    private static func isBSONHelper(_ name: String) -> Bool {
        let helpers: Set<String> = [
            "ObjectId", "ISODate", "Date", "NumberLong", "NumberInt",
            "NumberDecimal", "UUID", "BinData", "MinKey", "MaxKey",
            "Timestamp", "RegExp"
        ]
        return helpers.contains(name)
    }
    
    private static func tokenize(_ source: String) -> [BSONToken] {
        var tokens: [BSONToken] = []
        let chars = Array(source)
        var i = 0
        let n = chars.count
        
        while i < n {
            let c = chars[i]
            
            // Whitespace
            if c.isWhitespace {
                let start = i
                while i < n && chars[i].isWhitespace {
                    i += 1
                }
                let raw = String(chars[start..<i])
                tokens.append(BSONToken(kind: .whitespace(raw), raw: raw))
                continue
            }
            
            // Comments or Regex
            if c == "/" {
                if i + 1 < n && chars[i + 1] == "/" {
                    // Line comment
                    let start = i
                    while i < n && chars[i] != "\n" {
                        i += 1
                    }
                    let raw = String(chars[start..<i])
                    tokens.append(BSONToken(kind: .comment(raw), raw: raw))
                    continue
                } else if i + 1 < n && chars[i + 1] == "*" {
                    // Block comment
                    let start = i
                    i += 2
                    while i < n {
                        if i + 1 < n && chars[i] == "*" && chars[i + 1] == "/" {
                            i += 2
                            break
                        }
                        i += 1
                    }
                    let raw = String(chars[start..<i])
                    tokens.append(BSONToken(kind: .comment(raw), raw: raw))
                    continue
                } else {
                    // Regex literal
                    let start = i
                    i += 1 // skip opening '/'
                    var pattern = ""
                    var escaped = false
                    while i < n {
                        let rc = chars[i]
                        if escaped {
                            pattern.append(rc)
                            escaped = false
                        } else if rc == "\\" {
                            pattern.append(rc)
                            escaped = true
                        } else if rc == "/" {
                            i += 1 // skip closing '/'
                            break
                        } else {
                            pattern.append(rc)
                        }
                        i += 1
                    }
                    var flags = ""
                    while i < n && (chars[i].isLetter) {
                        flags.append(chars[i])
                        i += 1
                    }
                    let raw = String(chars[start..<i])
                    tokens.append(BSONToken(kind: .regex(pattern: pattern, flags: flags), raw: raw))
                    continue
                }
            }
            
            // Strings (double or single quotes)
            if c == "\"" || c == "'" {
                let quote = c
                let start = i
                i += 1 // skip opening quote
                var val = ""
                var escaped = false
                while i < n {
                    let sc = chars[i]
                    if escaped {
                        val.append(sc)
                        escaped = false
                    } else if sc == "\\" {
                        val.append(sc)
                        escaped = true
                    } else if sc == quote {
                        i += 1 // skip closing quote
                        break
                    } else {
                        val.append(sc)
                    }
                    i += 1
                }
                let raw = String(chars[start..<i])
                tokens.append(BSONToken(kind: .string(value: val, quote: quote), raw: raw))
                continue
            }
            
            // Punctuation
            if "{}[],():".contains(c) {
                tokens.append(BSONToken(kind: .punctuation(c), raw: String(c)))
                i += 1
                continue
            }
            
            // Identifiers
            if c.isLetter || c == "_" || c == "$" {
                let start = i
                i += 1
                while i < n && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$") {
                    i += 1
                }
                let raw = String(chars[start..<i])
                tokens.append(BSONToken(kind: .identifier(raw), raw: raw))
                continue
            }
            
            // Numbers
            if c.isNumber || c == "-" || c == "+" || c == "." {
                let start = i
                i += 1
                while i < n && (chars[i].isNumber || chars[i] == "." || chars[i].lowercased() == "e" || chars[i] == "-" || chars[i] == "+") {
                    i += 1
                }
                let raw = String(chars[start..<i])
                tokens.append(BSONToken(kind: .number(raw), raw: raw))
                continue
            }
            
            // Fallback
            tokens.append(BSONToken(kind: .punctuation(c), raw: String(c)))
            i += 1
        }
        
        return tokens
    }
    
    private static func nextNonWhitespaceIndex(from index: Int, in tokens: [BSONToken]) -> Int? {
        var j = index + 1
        while j < tokens.count {
            switch tokens[j].kind {
            case .whitespace, .comment:
                j += 1
            default:
                return j
            }
        }
        return nil
    }
    
    private static func parseHelperArgs(startingAt index: Int, in tokens: [BSONToken]) -> (args: [BSONToken], nextIndex: Int)? {
        guard let openParenIdx = nextNonWhitespaceIndex(from: index, in: tokens),
              case .punctuation("(") = tokens[openParenIdx].kind else {
            return nil
        }
        
        var args: [BSONToken] = []
        var parenCount = 1
        var j = openParenIdx + 1
        
        while j < tokens.count {
            let t = tokens[j]
            if case .punctuation("(") = t.kind {
                parenCount += 1
                args.append(t)
            } else if case .punctuation(")") = t.kind {
                parenCount -= 1
                if parenCount == 0 {
                    return (args, j + 1)
                }
                args.append(t)
            } else {
                args.append(t)
            }
            j += 1
        }
        return nil
    }
    
    private static func cleanArgs(_ args: [BSONToken]) -> [BSONToken] {
        return args.filter {
            switch $0.kind {
            case .whitespace, .comment, .punctuation(","):
                return false
            default:
                return true
            }
        }
    }
    
    private static func escapeStringForJSON(_ s: String) -> String {
        var result = ""
        for char in s {
            switch char {
            case "\\": result.append("\\\\")
            case "\"": result.append("\\\"")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            default: result.append(char)
            }
        }
        return result
    }
    
    private static func processBSONHelper(name: String, args: [BSONToken]) -> String {
        let clean = cleanArgs(args)
        
        switch name {
        case "ObjectId":
            if clean.isEmpty {
                return "{\"$oid\": \"\(BSONObjectID().hex)\"}"
            }
            if let first = clean.first, case .string(let val, _) = first.kind {
                return "{\"$oid\": \"\(val)\"}"
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$oid\": \"\(rawArgs)\"}"
            
        case "ISODate", "Date":
            if clean.isEmpty {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let nowString = formatter.string(from: Date())
                return "{\"$date\": \"\(nowString)\"}"
            }
            if let first = clean.first {
                if case .string(let val, _) = first.kind {
                    return "{\"$date\": \"\(val)\"}"
                } else if case .number(let val) = first.kind {
                    return "{\"$date\": {\"$numberLong\": \"\(val)\"}}"
                }
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$date\": \"\(rawArgs)\"}"
            
        case "NumberLong":
            if let first = clean.first {
                switch first.kind {
                case .string(let val, _):
                    return "{\"$numberLong\": \"\(val)\"}"
                case .number(let val):
                    return "{\"$numberLong\": \"\(val)\"}"
                default:
                    break
                }
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$numberLong\": \"\(rawArgs)\"}"
            
        case "NumberInt":
            if let first = clean.first {
                switch first.kind {
                case .string(let val, _):
                    return val
                case .number(let val):
                    return val
                default:
                    break
                }
            }
            return args.map(\.raw).joined()
            
        case "NumberDecimal":
            if let first = clean.first {
                switch first.kind {
                case .string(let val, _):
                    return "{\"$numberDecimal\": \"\(val)\"}"
                case .number(let val):
                    return "{\"$numberDecimal\": \"\(val)\"}"
                default:
                    break
                }
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$numberDecimal\": \"\(rawArgs)\"}"
            
        case "UUID":
            if let first = clean.first, case .string(let val, _) = first.kind {
                if let uuid = UUID(uuidString: val) {
                    var uuidBytes = uuid.uuid
                    let data = Data(bytes: &uuidBytes, count: 16)
                    let base64 = data.base64EncodedString()
                    return "{\"$binary\": {\"base64\": \"\(base64)\", \"subType\": \"04\"}}"
                }
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$binary\": {\"base64\": \"\", \"subType\": \"04\"}}"
            
        case "BinData":
            if clean.count >= 2,
               case .number(let subTypeStr) = clean[0].kind,
               case .string(let base64Str, _) = clean[1].kind {
                let subTypeHex: String
                if subTypeStr.hasPrefix("0x") {
                    let hexPart = String(subTypeStr.dropFirst(2))
                    subTypeHex = hexPart.count == 1 ? "0" + hexPart : hexPart
                } else if let subTypeInt = Int(subTypeStr) {
                    subTypeHex = String(format: "%02x", subTypeInt)
                } else {
                    subTypeHex = subTypeStr
                }
                return "{\"$binary\": {\"base64\": \"\(base64Str)\", \"subType\": \"\(subTypeHex)\"}}"
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$binary\": {\"base64\": \"\", \"subType\": \"00\"}}"
            
        case "MinKey":
            return "{\"$minKey\": 1}"
            
        case "MaxKey":
            return "{\"$maxKey\": 1}"
            
        case "Timestamp":
            if clean.count >= 2,
               case .number(let tStr) = clean[0].kind,
               case .number(let iStr) = clean[1].kind {
                return "{\"$timestamp\": {\"t\": \(tStr), \"i\": \(iStr)}}"
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$timestamp\": {\"t\": 0, \"i\": 0}}"
            
        case "RegExp":
            if clean.count >= 1, case .string(let pat, _) = clean[0].kind {
                let options: String
                if clean.count >= 2, case .string(let opts, _) = clean[1].kind {
                    options = opts
                } else {
                    options = ""
                }
                let escapedPattern = escapeStringForJSON(pat)
                return "{\"$regularExpression\": {\"pattern\": \"\(escapedPattern)\", \"options\": \"\(options)\"}}"
            }
            let rawArgs = args.map(\.raw).joined()
            return "{\"$regularExpression\": {\"pattern\": \"\", \"options\": \"\"}}"
            
        default:
            return ""
        }
    }
}
