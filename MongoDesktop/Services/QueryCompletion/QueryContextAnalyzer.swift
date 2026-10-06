import Foundation

enum QueryContextAnalyzer {

    // MARK: - Analyze Context

    static func analyze(
        text: String,
        cursorLocation: Int,
        editorMode: QueryEditorMode
    ) -> QueryContext {
        let nsText = text as NSString
        let clampedCursor = max(0, min(cursorLocation, nsText.length))

        // Determine word boundaries around cursor
        var start = clampedCursor
        var end = clampedCursor

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$.-"))

        while start > 0 {
            let prevCharRange = NSRange(location: start - 1, length: 1)
            let prevCharStr = nsText.substring(with: prevCharRange)
            guard let scalar = prevCharStr.unicodeScalars.first, wordChars.contains(scalar) else {
                break
            }
            start -= 1
        }

        while end < nsText.length {
            let nextCharRange = NSRange(location: end, length: 1)
            let nextCharStr = nsText.substring(with: nextCharRange)
            guard let scalar = nextCharStr.unicodeScalars.first, wordChars.contains(scalar) else {
                break
            }
            end += 1
        }

        let partialWord = (start < end) ? nsText.substring(with: NSRange(location: start, length: end - start)) : ""
        let replacementRange = NSRange(location: start, length: end - start)

        // Check if inside quotes
        let isInsideQuotes = checkInsideQuotes(nsText: nsText, cursor: clampedCursor)

        // Check if after colon (Value position)
        let isAfterColon = checkAfterColon(nsText: nsText, beforeLocation: start)

        // Check if inside array
        let isInsideArray = checkInsideArray(nsText: nsText, cursor: clampedCursor)

        // Check curly brace depth (for operator sub-document scope)
        let braceDepth = checkBraceDepth(nsText: nsText, cursor: clampedCursor)
        let isOperatorScope = (braceDepth >= 2 && editorMode == .findFilter) || partialWord.hasPrefix("$")

        let isKeyPosition = !isAfterColon

        return QueryContext(
            partialWord: partialWord,
            replacementRange: replacementRange,
            isInsideQuotes: isInsideQuotes,
            isAfterColon: isAfterColon,
            isKeyPosition: isKeyPosition,
            isInsideArray: isInsideArray,
            isOperatorScope: isOperatorScope,
            editorMode: editorMode
        )
    }

    // MARK: - Filter & Rank Suggestions

    static func completions(
        context: QueryContext,
        collectionFields: [QueryCompletionItem]
    ) -> [QueryCompletionItem] {
        let query = context.partialWord.trimmingCharacters(in: .whitespacesAndNewlines)

        var pool: [QueryCompletionItem] = []

        switch context.editorMode {
        case .aggregatePipeline:
            if context.isKeyPosition {
                pool.append(contentsOf: QueryCompletionCatalog.aggregateStages)
                pool.append(contentsOf: QueryCompletionCatalog.queryOperators)
                pool.append(contentsOf: collectionFields)
            } else {
                pool.append(contentsOf: QueryCompletionCatalog.bsonHelpers)
                pool.append(contentsOf: QueryCompletionCatalog.aggregateOperators)
                pool.append(contentsOf: collectionFields)
            }

        case .projection:
            pool.append(contentsOf: collectionFields)
            if context.isKeyPosition {
                pool.append(contentsOf: QueryCompletionCatalog.queryOperators.filter { $0.label == "$slice" || $0.label == "$elemMatch" })
            } else {
                pool.append(contentsOf: QueryCompletionCatalog.bsonHelpers)
            }

        case .sort:
            pool.append(contentsOf: collectionFields)

        case .findFilter, .genericJSON:
            if context.isAfterColon {
                pool.append(contentsOf: QueryCompletionCatalog.bsonHelpers)
                pool.append(contentsOf: QueryCompletionCatalog.queryOperators.filter { $0.label.hasPrefix("$") })
            } else if context.isOperatorScope {
                // In operator sub-document { field: { <here> } } or when typing '$'
                pool.append(contentsOf: QueryCompletionCatalog.queryOperators)
                if !query.hasPrefix("$") {
                    pool.append(contentsOf: collectionFields)
                }
            } else {
                // Top-level key position
                if query.hasPrefix("$") {
                    pool.append(contentsOf: QueryCompletionCatalog.queryOperators)
                    pool.append(contentsOf: QueryCompletionCatalog.aggregateStages)
                } else {
                    pool.append(contentsOf: collectionFields)
                    pool.append(contentsOf: QueryCompletionCatalog.queryOperators)
                    pool.append(contentsOf: QueryCompletionCatalog.aggregateStages)
                }
            }
        }

        if query.isEmpty {
            return pool
        }

        let cleanQuery = query.replacingOccurrences(of: "\"", with: "").lowercased()

        struct ScoredItem {
            let item: QueryCompletionItem
            let score: Int
        }

        var scored: [ScoredItem] = []

        for item in pool {
            let label = item.label.lowercased()
            let cleanLabel = label.replacingOccurrences(of: "$", with: "")

            var score = 0

            if label == cleanQuery || cleanLabel == cleanQuery {
                score = 1000
            } else if label.hasPrefix(cleanQuery) {
                score = 500 - (label.count - cleanQuery.count)
            } else if cleanLabel.hasPrefix(cleanQuery) {
                score = 400 - (cleanLabel.count - cleanQuery.count)
            } else if label.contains(cleanQuery) {
                score = 200 - (label.count - cleanQuery.count)
            } else {
                continue
            }

            // Context bonus
            if context.isAfterColon {
                if case .bsonHelper = item.kind {
                    score += 150
                }
            } else if context.isOperatorScope {
                if case .queryOperator = item.kind {
                    score += 180
                }
            } else {
                if case .field = item.kind {
                    score += 50
                } else if case .aggregateStage = item.kind, context.editorMode == .aggregatePipeline {
                    score += 120
                } else if case .queryOperator = item.kind, context.editorMode == .findFilter {
                    score += 80
                }
            }

            scored.append(ScoredItem(item: item, score: score))
        }

        scored.sort { $0.score > $1.score }

        // Deduplicate by item.id
        var seen = Set<String>()
        var result: [QueryCompletionItem] = []
        for s in scored {
            if !seen.contains(s.item.id) {
                seen.insert(s.item.id)
                result.append(s.item)
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private static func checkInsideQuotes(nsText: NSString, cursor: Int) -> Bool {
        var inQuotes = false
        var escaped = false

        for i in 0..<cursor {
            let ch = nsText.character(at: i)
            if escaped {
                escaped = false
                continue
            }
            if ch == 0x5C { // backslash '\'
                escaped = true
                continue
            }
            if ch == 0x22 { // double quote '"'
                inQuotes.toggle()
            }
        }
        return inQuotes
    }

    private static func checkAfterColon(nsText: NSString, beforeLocation: Int) -> Bool {
        var idx = beforeLocation - 1
        while idx >= 0 {
            let ch = nsText.character(at: idx)
            // Skip whitespace, newline, quote
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x22 {
                idx -= 1
                continue
            }
            if ch == 0x3A { // ':'
                return true
            }
            break
        }
        return false
    }

    private static func checkInsideArray(nsText: NSString, cursor: Int) -> Bool {
        var bracketDepth = 0
        var inQuotes = false
        var escaped = false

        for i in 0..<cursor {
            let ch = nsText.character(at: i)
            if escaped {
                escaped = false
                continue
            }
            if ch == 0x5C {
                escaped = true
                continue
            }
            if ch == 0x22 {
                inQuotes.toggle()
                continue
            }
            if !inQuotes {
                if ch == 0x5B { // '['
                    bracketDepth += 1
                } else if ch == 0x5D { // ']'
                    bracketDepth = max(0, bracketDepth - 1)
                }
            }
        }
        return bracketDepth > 0
    }

    private static func checkBraceDepth(nsText: NSString, cursor: Int) -> Int {
        var depth = 0
        var inQuotes = false
        var escaped = false

        for i in 0..<cursor {
            let ch = nsText.character(at: i)
            if escaped {
                escaped = false
                continue
            }
            if ch == 0x5C { // '\'
                escaped = true
                continue
            }
            if ch == 0x22 { // '"'
                inQuotes.toggle()
                continue
            }
            if !inQuotes {
                if ch == 0x7B { // '{'
                    depth += 1
                } else if ch == 0x7D { // '}'
                    depth = max(0, depth - 1)
                }
            }
        }
        return depth
    }
}
