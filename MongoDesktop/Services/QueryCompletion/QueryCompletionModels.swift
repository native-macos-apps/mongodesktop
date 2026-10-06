import Foundation
import SwiftUI

// MARK: - Query Editor Mode

enum QueryEditorMode: String, CaseIterable, Sendable {
    case findFilter
    case aggregatePipeline
    case projection
    case sort
    case genericJSON
}

// MARK: - Query Completion Kind

enum QueryCompletionKind: Hashable, Sendable {
    case field(type: String?)
    case queryOperator
    case aggregateStage
    case aggregateOperator
    case bsonHelper
    case snippet

    var title: String {
        switch self {
        case .field(let type):
            if let type = type, !type.isEmpty {
                return type
            }
            return "Field"
        case .queryOperator:
            return "Operator"
        case .aggregateStage:
            return "Stage"
        case .aggregateOperator:
            return "Agg Op"
        case .bsonHelper:
            return "Type"
        case .snippet:
            return "Snippet"
        }
    }

    var iconName: String {
        switch self {
        case .field:
            return "tag.fill"
        case .queryOperator:
            return "function"
        case .aggregateStage:
            return "arrow.triangle.branch"
        case .aggregateOperator:
            return "slider.horizontal.3"
        case .bsonHelper:
            return "cube.fill"
        case .snippet:
            return "scissors"
        }
    }

    var badgeColor: Color {
        switch self {
        case .field:
            return .cyan
        case .queryOperator:
            return .purple
        case .aggregateStage:
            return .orange
        case .aggregateOperator:
            return .indigo
        case .bsonHelper:
            return .green
        case .snippet:
            return .blue
        }
    }
}

// MARK: - Query Completion Item

struct QueryCompletionItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let kind: QueryCompletionKind
    let detail: String
    let documentation: String
    let insertText: String
    /// Relative cursor offset from insertion start. If nil, cursor goes to the end of inserted text.
    let cursorOffset: Int?
    let isKey: Bool

    init(
        label: String,
        kind: QueryCompletionKind,
        detail: String,
        documentation: String = "",
        insertText: String? = nil,
        cursorOffset: Int? = nil,
        isKey: Bool = true
    ) {
        self.id = "\(kind.title):\(label)"
        self.label = label
        self.kind = kind
        self.detail = detail
        self.documentation = documentation
        self.insertText = insertText ?? label
        self.cursorOffset = cursorOffset
        self.isKey = isKey
    }
}

// MARK: - Query Context

struct QueryContext: Sendable {
    var partialWord: String
    var replacementRange: NSRange
    var isInsideQuotes: Bool
    var isAfterColon: Bool
    var isKeyPosition: Bool
    var isInsideArray: Bool
    var isOperatorScope: Bool
    var editorMode: QueryEditorMode

    init(
        partialWord: String,
        replacementRange: NSRange,
        isInsideQuotes: Bool,
        isAfterColon: Bool,
        isKeyPosition: Bool,
        isInsideArray: Bool,
        isOperatorScope: Bool = false,
        editorMode: QueryEditorMode
    ) {
        self.partialWord = partialWord
        self.replacementRange = replacementRange
        self.isInsideQuotes = isInsideQuotes
        self.isAfterColon = isAfterColon
        self.isKeyPosition = isKeyPosition
        self.isInsideArray = isInsideArray
        self.isOperatorScope = isOperatorScope
        self.editorMode = editorMode
    }
}
