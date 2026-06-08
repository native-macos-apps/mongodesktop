import SwiftUI
import SwiftBSON

// MARK: - JSONTreeView

struct JSONTreeView: View {
    let document: BSONDocument
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                JSONNodeView(node: node, depth: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.document.toCanonicalExtendedJSONString(), forType: .string)
            } label: {
                Label("Copy (BSON)", systemImage: "doc.on.doc")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.document.toRelaxedExtendedJSONString(), forType: .string)
            } label: {
                Label("Copy JSON", systemImage: "curlybraces")
            }
        }
    }

    private var nodes: [JSONNode] {
        JSONNode.rootNodes(for: document, timeZone: timeZone)
    }
}

// MARK: - JSONNode

struct JSONNode: Identifiable {
    let id: String
    let key: String?
    let value: String
    let rawValue: BSON
    let timeZone: TimeZone

    init(key: String? = nil, value: BSON, timeZone: TimeZone, parentID: String) {
        self.id = Self.stableIdentifier(parentID: parentID, keyName: key ?? "")
        self.key = key
        self.rawValue = value
        self.timeZone = timeZone
        switch value {
        case .document(let doc):
            self.value = "{ \(doc.count) fields }"
        case .array(let array):
            self.value = "[ \(array.count) items ]"
        default:
            self.value = displayValue(value, timeZone: timeZone)
        }
    }

    static func rootID(for document: BSONDocument) -> String {
        String(describing: document["_id"] ?? .null)
    }

    static func rootNodes(for document: BSONDocument, timeZone: TimeZone) -> [JSONNode] {
        let rootID = rootID(for: document)
        return document.map { pair in
            JSONNode(
                key: pair.key,
                value: pair.value,
                timeZone: timeZone,
                parentID: rootID
            )
        }
    }

    var hasChildren: Bool {
        switch rawValue {
        case .document(let doc):
            return !doc.isEmpty
        case .array(let array):
            return !array.isEmpty
        default:
            return false
        }
    }

    func makeChildren() -> [JSONNode] {
        switch rawValue {
        case .document(let doc):
            return doc.map { pair in
                JSONNode(
                    key: pair.key,
                    value: pair.value,
                    timeZone: timeZone,
                    parentID: id
                )
            }
        case .array(let array):
            return array.enumerated().map { index, item in
                let key = "[\(index)]"
                return JSONNode(
                    key: key,
                    value: item,
                    timeZone: timeZone,
                    parentID: id
                )
            }
        default:
            return []
        }
    }

    private static func stableIdentifier(parentID: String, keyName: String) -> String {
        let value = parentID + keyName
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - JSONNodeView

struct JSONNodeView: View {
    let node: JSONNode
    let depth: Int
    @State private var isExpanded: Bool = false
    @State private var loadedChildren: [JSONNode]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Indent
                if depth > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                        .padding(.horizontal, 7)
                }

                if node.hasChildren {
                    Button(action: toggleExpansion) {
                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 5, height: 5)
                        .padding(.horizontal, 4)
                }

                if let key = node.key {
                    Text("\(key):")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                        .textSelection(.enabled)
                        .lineLimit(1)
                }

                Text(node.value)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            .padding(.leading, CGFloat(depth) * 16)

            if isExpanded, let children = loadedChildren {
                ForEach(children) { child in
                    JSONNodeView(node: child, depth: depth + 1)
                }
            }
        }
    }

    private var valueColor: Color {
        if node.hasChildren { return .secondary }
        switch node.rawValue {
        case .string: return Color(red: 0.8, green: 0.6, blue: 0.3)
        case .bool: return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .null: return Color(red: 0.7, green: 0.4, blue: 0.4)
        case .int32, .int64, .double, .decimal128: return Color(red: 0.6, green: 0.85, blue: 0.7)
        case .datetime, .objectID, .binary, .regex, .timestamp, .maxKey, .minKey:
            return .orange
        default: return .primary
        }
    }

    private func toggleExpansion() {
        if !isExpanded, loadedChildren == nil {
            loadedChildren = node.makeChildren()
        }

        withAnimation(.spring(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
