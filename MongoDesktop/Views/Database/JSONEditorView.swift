import Foundation
import SwiftUI
import AppKit

#if canImport(SwiftTreeSitter) && canImport(TreeSitterJSON)
import SwiftTreeSitter
import TreeSitterJSON
#endif

struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var errorMessage: String?
    var documentKeys: [String] = []

    var minHeight: CGFloat = 72

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = JSONTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true

        context.coordinator.refresh(in: textView, forceValidation: true)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? JSONTextView else { return }
        context.coordinator.parent = self
        context.coordinator.documentKeys = documentKeys
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            // Highlight synchronously (suppressed from textDidChange via isUpdating)
            context.coordinator.applyHighlight(in: textView)
            context.coordinator.isUpdating = false
            // Defer validation completely out of the SwiftUI render cycle
            context.coordinator.scheduleValidationDeferred(in: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONEditorView
        private let highlighter = JSONSyntaxHighlighter()
        private var validateWorkItem: DispatchWorkItem?
        /// Set to true when we are programmatically mutating the text view so that
        /// `textDidChange` does not write back to the @Binding (which would publish
        /// a state change inside a SwiftUI view-update and trigger the warning).
        var isUpdating: Bool = false
        private let autoPairs: [String: String] = [
            "\"": "\"",
            "{": "}",
            "[": "]",
            "(": ")"
        ]
        private let closers: Set<String> = ["\"", "}", "]", ")"]

        init(_ parent: JSONEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            // Ignore notifications we caused ourselves during programmatic updates.
            guard !isUpdating else { return }
            guard let textView = notification.object as? JSONTextView else { return }
            let current = textView.string
            if parent.text != current {
                parent.text = current
            }

            applyHighlight(in: textView)
            scheduleValidation(in: textView)
            
            if let event = NSApp.currentEvent, event.type == .keyDown {
                let chars = event.characters ?? ""
                if let first = chars.first, (first.isLetter || first == "$") {
                    DispatchQueue.main.async {
                        textView.complete(nil)
                    }
                }
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString else { return true }
            guard replacementString.count == 1 else { return true }

            let selected = textView.selectedRange()
            let typed = replacementString

            if shouldSkipCloser(typed, selected: selected, in: textView.string) {
                textView.setSelectedRange(NSRange(location: selected.location + 1, length: 0))
                return false
            }

            guard let closer = autoPairs[typed] else { return true }

            if selected.length > 0 {
                let nsText = textView.string as NSString
                let selectedText = nsText.substring(with: selected)
                replaceText(
                    in: textView,
                    range: selected,
                    with: typed + selectedText + closer,
                    cursorLocation: selected.location + selectedText.utf16.count + 2
                )
                return false
            }

            replaceText(
                in: textView,
                range: affectedCharRange,
                with: typed + closer,
                cursorLocation: affectedCharRange.location + 1
            )
            return false
        }

        // Called from makeNSView: apply highlight and schedule initial validation.
        fileprivate func refresh(in textView: JSONTextView, forceValidation: Bool) {
            applyHighlight(in: textView)
            if forceValidation {
                scheduleValidationDeferred(in: textView)
            } else {
                scheduleValidation(in: textView)
            }
        }

        // Applies syntax highlight while suppressing any textDidChange side-effects.
        fileprivate func applyHighlight(in textView: JSONTextView) {
            isUpdating = true
            highlighter.apply(to: textView, source: textView.string)
            isUpdating = false
        }

        // Validates after a true runloop hop so we never mutate @Binding during a
        // SwiftUI render pass (DispatchQueue.main.async guarantees a new runloop turn).
        fileprivate func scheduleValidationDeferred(in textView: JSONTextView) {
            let source = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let validation = JSONEditorFormatter.validate(source)
                self.parent.errorMessage = validation?.message
            }
        }

        // Debounced validation for user typing (runs on background then hops to main).
        private func scheduleValidation(in textView: JSONTextView) {
            validateWorkItem?.cancel()
            let source = textView.string
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let validation = JSONEditorFormatter.validate(source)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.errorMessage = validation?.message
                }
            }
            validateWorkItem = task
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: task)
        }

        private func shouldSkipCloser(_ typed: String, selected: NSRange, in source: String) -> Bool {
            guard selected.length == 0 else { return false }
            guard closers.contains(typed) else { return false }
            let nsSource = source as NSString
            guard selected.location < nsSource.length else { return false }
            let next = nsSource.substring(with: NSRange(location: selected.location, length: 1))
            return next == typed
        }

        private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String, cursorLocation: Int) {
            guard let textStorage = textView.textStorage else { return }
            textStorage.replaceCharacters(in: range, with: replacement)
            textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
            textView.didChangeText()
        }

        var documentKeys: [String] = []
        private let mongoKeywords = [
            "$eq", "$gt", "$gte", "$in", "$lt", "$lte", "$ne", "$nin",
            "$and", "$not", "$nor", "$or",
            "$exists", "$type",
            "$expr", "$jsonSchema", "$mod", "$regex", "$text", "$where",
            "$all", "$elemMatch", "$size",
            "$bitsAllClear", "$bitsAllSet", "$bitsAnyClear", "$bitsAnySet",
            "$match", "$group", "$project", "$sort", "$limit", "$skip", "$unwind", "$lookup", "$addFields", "$out", "$merge", "$set", "$unset", "$push", "$pull", "$inc", "$mul"
        ]
        private let mongoValueHelpers = [
            "ObjectId", "ISODate", "NumberInt", "NumberLong", "NumberDecimal",
            "BinData", "Timestamp", "MinKey", "MaxKey", "RegExp"
        ]

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partialWord = (textView.string as NSString).substring(with: charRange)
            guard !partialWord.isEmpty else { return [] }
            
            var allCompletions = Set<String>()
            
            for kw in mongoKeywords {
                if kw.lowercased().hasPrefix(partialWord.lowercased()) {
                    allCompletions.insert(kw)
                }
            }
            
            for helper in mongoValueHelpers {
                if helper.lowercased().hasPrefix(partialWord.lowercased()) {
                    allCompletions.insert(helper)
                }
            }
            
            for key in documentKeys {
                if key.lowercased().hasPrefix(partialWord.lowercased()) {
                    allCompletions.insert(key)
                }
            }
            
            return Array(allCompletions).sorted()
        }
    }
}

enum JSONEditorFormatter {
    struct ValidationError {
        let message: String
    }

    static func prettyFormatted(_ source: String) throws -> String {
        let object = try parseObject(from: source)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard var pretty = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JSONEditorFormatter", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to display formatted JSON."])
        }
        if !pretty.hasSuffix("\n") {
            pretty.append("\n")
        }
        return pretty
    }

    static func validate(_ source: String) -> ValidationError? {
        do {
            _ = try parseObject(from: source)
            return nil
        } catch let error as NSError {
            let base = error.localizedDescription
            let converted = BSONQueryParser.convertBSONToJSON(source)
            let detail = indexedMessage(source: converted, error: error)
            return ValidationError(message: detail.isEmpty ? base : "\(base) (\(detail))")
        } catch {
            return ValidationError(message: error.localizedDescription)
        }
    }

    private static func parseObject(from source: String) throws -> Any {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "{}" : source
        let converted = BSONQueryParser.convertBSONToJSON(candidate)
        guard let data = converted.data(using: .utf8) else {
            throw NSError(domain: "JSONEditorFormatter", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to read JSON content."])
        }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func indexedMessage(source: String, error: NSError) -> String {
        guard let index = error.userInfo["NSJSONSerializationErrorIndex"] as? Int else { return "" }
        let (line, column) = lineColumn(utf8Offset: index, in: source)
        return "line \(line), column \(column)"
    }

    private static func lineColumn(utf8Offset: Int, in source: String) -> (Int, Int) {
        let utf8View = source.utf8
        let clamped = max(0, min(utf8Offset, utf8View.count))
        let utf8Index = utf8View.index(utf8View.startIndex, offsetBy: clamped)
        let scalarIndex = String.Index(utf8Index, within: source) ?? source.endIndex
        let prefix = source[..<scalarIndex]

        var line = 1
        var column = 1
        for ch in prefix {
            if ch == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}

fileprivate final class JSONTextView: NSTextView {
    override var frame: NSRect {
        didSet {
            guard let container = textContainer else { return }
            if container.containerSize.width != frame.width {
                container.containerSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
            }
        }
    }

    override var rangeForUserCompletion: NSRange {
        let selected = selectedRange()
        guard selected.length == 0 else { return selected }

        let nsText = string as NSString
        var start = selected.location
        var end = selected.location

        while start > 0, isCompletionCharacter(nsText.substring(with: NSRange(location: start - 1, length: 1))) {
            start -= 1
        }

        while end < nsText.length, isCompletionCharacter(nsText.substring(with: NSRange(location: end, length: 1))) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private func isCompletionCharacter(_ value: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

private final class JSONSyntaxHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func apply(to textView: NSTextView, source: String) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let selectedRanges = textView.selectedRanges

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: fullRange)
        let tokens = tokenRanges(in: source)
        for token in tokens {
            storage.addAttributes(tokenAttributes(for: token.kind), range: token.range)
        }
        storage.endEditing()

        textView.setSelectedRanges(selectedRanges, affinity: .downstream, stillSelecting: false)
        textView.typingAttributes = baseAttributes
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor]
    }

    private func tokenAttributes(for kind: TokenKind) -> [NSAttributedString.Key: Any] {
        let color: NSColor
        switch kind {
        case .key:
            color = NSColor.systemBlue
        case .string:
            color = NSColor.systemRed
        case .number:
            color = NSColor.systemOrange
        case .keyword:
            color = NSColor.systemPurple
        case .punctuation:
            color = NSColor.secondaryLabelColor
        case .regex:
            color = NSColor.systemGreen
        case .comment:
            color = NSColor.secondaryLabelColor
        }
        return [.font: baseFont, .foregroundColor: color]
    }

    private func tokenRanges(in source: String) -> [Token] {
        let bsonTokens = BSONQueryParser.tokenize(source)
        var tokens: [Token] = []
        var i = 0
        
        while i < bsonTokens.count {
            let token = bsonTokens[i]
            
            switch token.kind {
            case .whitespace:
                break
                
            case .comment:
                tokens.append(Token(range: token.range, kind: .comment))
                
            case .regex:
                tokens.append(Token(range: token.range, kind: .regex))
                
            case .string:
                if isKey(index: i, in: bsonTokens) {
                    tokens.append(Token(range: token.range, kind: .key))
                } else {
                    tokens.append(Token(range: token.range, kind: .string))
                }
                
            case .punctuation:
                tokens.append(Token(range: token.range, kind: .punctuation))
                
            case .number:
                tokens.append(Token(range: token.range, kind: .number))
                
            case .identifier(let name):
                if name == "true" || name == "false" || name == "null" {
                    tokens.append(Token(range: token.range, kind: .keyword))
                } else if BSONQueryParser.isBSONHelper(name) {
                    tokens.append(Token(range: token.range, kind: .keyword))
                } else if name == "new" {
                    tokens.append(Token(range: token.range, kind: .keyword))
                } else if isKey(index: i, in: bsonTokens) {
                    tokens.append(Token(range: token.range, kind: .key))
                } else {
                    break
                }
            }
            i += 1
        }
        
        return tokens
    }

    private func isKey(index: Int, in tokens: [BSONToken]) -> Bool {
        var j = index + 1
        while j < tokens.count {
            switch tokens[j].kind {
            case .whitespace, .comment:
                j += 1
            case .punctuation(let c):
                return c == ":"
            default:
                return false
            }
        }
        return false
    }
}

private struct Token {
    let range: NSRange
    let kind: TokenKind
}

private enum TokenKind {
    case key
    case string
    case number
    case keyword
    case punctuation
    case regex
    case comment
}

#if canImport(SwiftTreeSitter) && canImport(TreeSitterJSON)
private enum TreeSitterJSONTokenCollector {
    private static let parser: Parser? = {
        let parser = Parser()
        guard let rawLanguage = tree_sitter_json() else { return nil }
        do {
            try parser.setLanguage(Language(rawLanguage))
            return parser
        } catch {
            return nil
        }
    }()

    static func collect(source: String) -> [Token] {
        guard let parser, let tree = parser.parse(source), let root = tree.rootNode else {
            return []
        }

        var tokens: [Token] = []
        walk(node: root, tokens: &tokens)
        return tokens
    }

    private static func walk(node: Node, tokens: inout [Token]) {
        guard let type = node.nodeType else { return }
        if node.range.length > 0, let kind = tokenKind(for: node, type: type) {
            tokens.append(Token(range: node.range, kind: kind))
        }

        for idx in 0..<node.childCount {
            guard let child = node.child(at: idx) else { continue }
            walk(node: child, tokens: &tokens)
        }
    }

    private static func tokenKind(for node: Node, type: String) -> TokenKind? {
        switch type {
        case "string":
            if isObjectKey(node) { return .key }
            return .string
        case "number":
            return .number
        case "true", "false", "null":
            return .keyword
        case "{", "}", "[", "]", ":", ",":
            return .punctuation
        default:
            return nil
        }
    }

    private static func isObjectKey(_ node: Node) -> Bool {
        guard let parent = node.parent, parent.nodeType == "pair" else { return false }
        guard let keyNode = parent.namedChild(at: 0) else { return false }
        return keyNode.range == node.range
    }
}
#endif
