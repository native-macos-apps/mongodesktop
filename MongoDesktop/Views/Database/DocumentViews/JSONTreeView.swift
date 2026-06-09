import SwiftUI
import SwiftBSON

// MARK: - JSONTreeView

struct JSONTreeView: View {
    let document: BSONDocument
    let timeZone: TimeZone
    @State private var selectedNodeID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                JSONNodeView(node: node, depth: 0, selectedNodeID: $selectedNodeID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedNodeID = nil
                }
        }
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

    var copyValue: String {
        switch rawValue {
        case .document(let doc):
            return doc.toRelaxedExtendedJSONString()
        case .array:
            return String(describing: rawValue)
        default:
            return displayValue(rawValue, timeZone: timeZone)
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
    @Binding var selectedNodeID: String?
    @State private var isExpanded: Bool = false
    @State private var loadedChildren: [JSONNode]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if node.hasChildren {
                    Button(action: toggleExpansion) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .frame(width: 12, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 12, height: 14)
                }

                rowLabel
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.vertical, 1)
            .padding(.trailing, 6)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                selectedNodeID = isSelected ? nil : node.id
            }
            .contextMenu {
                if let key = node.key {
                    Button {
                        copyToPasteboard(key)
                    } label: {
                        Label("Copy Key", systemImage: "key")
                    }
                }

                Button {
                    copyToPasteboard(node.copyValue)
                } label: {
                    Label("Copy Value", systemImage: "doc.on.doc")
                }
            }

            if isExpanded, let children = loadedChildren {
                ForEach(children) { child in
                    JSONNodeView(node: child, depth: depth + 1, selectedNodeID: $selectedNodeID)
                }
            }
        }
    }

    private var isSelected: Bool {
        selectedNodeID == node.id
    }

    private var rowLabel: Text {
        let valueText = Text(node.value).foregroundStyle(valueColor)
        guard let key = node.key else { return valueText }
        return Text("\(key): ")
            .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0)) + valueText
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

    private func copyToPasteboard(_ value: String) {
        selectedNodeID = node.id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
