import Foundation
import SwiftUI
import SwiftBSON

// MARK: - DatabaseDetailView

struct DatabaseDetailView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @EnvironmentObject private var globalSettings: GlobalSettings
    @Environment(\.databaseTabContext) private var tabContext
    @State private var filterError: String? = nil
    @State private var sortError: String? = nil
    @State private var projectionError: String? = nil
    @State private var localViewMode: DocumentViewMode = .json
    var body: some View {
        VStack(spacing: 0) {
            if let tabContext {
                if tabContext.tabs.count > 1 {
                    tabBar(tabContext)
                }
            }
            
            if sessionViewModel.selectedDatabase == nil || sessionViewModel.selectedCollection == nil {
                WelcomeScreenView()
            } else {
                toolbarArea
                Divider().opacity(0.4)
                contentArea
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            localViewMode = tabViewModel.viewMode
        }
        .onChange(of: tabViewModel.viewMode) { _, newValue in
            guard localViewMode != newValue else { return }
            localViewMode = newValue
        }
        .onChange(of: localViewMode) { _, newValue in
            guard tabViewModel.viewMode != newValue else { return }
            DispatchQueue.main.async {
                tabViewModel.viewMode = newValue
            }
        }
    }

    // MARK: Toolbar Area
    private var toolbarArea: some View {
        VStack(spacing: 0) {
            // Filter Row
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                    .font(.body)

                JSONEditorView(
                    text: $tabViewModel.filterText,
                    errorMessage: $filterError,
                    minHeight: 28
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filterError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(filterError ?? "Filter JSON { \"field\": \"value\" }")

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { tabViewModel.isAdvancedQuery.toggle() } }) {
                    Label(tabViewModel.isAdvancedQuery ? "Simple" : "Advanced", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: runFind) {
                    Label("Run", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(hasSyntaxError)
                .opacity(hasSyntaxError ? 0.55 : 1)

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if tabViewModel.isAdvancedQuery {
                advancedQueryRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider()
                .opacity(0.4)

            // Pagination Row
            paginationRow
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private var advancedQueryRow: some View {
        HStack(spacing: 10) {
            Text("Sort")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $tabViewModel.sortText,
                errorMessage: $sortError,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(sortError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(sortError ?? "Sort JSON { \"field\": 1 }")

            Text("Projection")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $tabViewModel.projectionText,
                errorMessage: $projectionError,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(projectionError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(projectionError ?? "Projection JSON { \"field\": 1 }")
        }
    }



    // MARK: View Mode Picker
    private var viewModePicker: some View {
        Picker("", selection: $localViewMode) {
            ForEach(DocumentViewMode.allCases) { mode in
                Image(systemName: mode == .table ? "tablecells" : "curlybraces")
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 70)
    }

    // MARK: Pagination
    private var paginationRow: some View {
        HStack(spacing: 12) {
            Button(action: { Task { await tabViewModel.previousPage(using: sessionViewModel) } }) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(tabViewModel.currentPage == 0)

            Text("Page \(tabViewModel.currentPage + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: { Task { await tabViewModel.nextPage(using: sessionViewModel) } }) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!tabViewModel.hasMore)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            Text("\(tabViewModel.documents.count) docs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Text("Limit \(tabViewModel.pageSize)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            viewModePicker
        }
    }

    // MARK: Content Area
    private var contentArea: some View {
        Group {
            if localViewMode == .table {
                DocumentTableView(documents: tabViewModel.documents, selection: $tabViewModel.selectedRowIds, isLoading: tabViewModel.isLoading)
            } else {
                DocumentJSONView(documents: tabViewModel.documents, timeZone: globalSettings.displayTimeZone, isLoading: tabViewModel.isLoading)
            }
        }
    }

    // MARK: Actions
    private func runFind() {
        guard !hasSyntaxError else { return }
        tabViewModel.resetPaging()
        Task { await tabViewModel.runFind(using: sessionViewModel) }
    }

    private var hasSyntaxError: Bool {
        if filterError != nil { return true }
        if tabViewModel.isAdvancedQuery && (sortError != nil || projectionError != nil) { return true }
        return false
    }

    private func tabBar(_ context: DatabaseTabContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Tab track
                HStack(spacing: 0) {
                    ForEach(context.tabs) { tab in
                        TabPill(
                            title: tab.title,
                            isSelected: tab.id == context.selectedId,
                            onSelect: { context.select(tab.id) },
                            onClose: { context.close(tab.id) }
                        )
                    }
                }
                .padding(3)
                .background(
                    Capsule(style: .continuous)
                        .fill(.regularMaterial) // "liquid glass" track
                )
                
                // Add tab button (+)
                Button(action: context.add) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .help("New Tab")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct TabPill: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(isHovered ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - DocumentRow

struct DocumentRow: Identifiable {
    let id: String
    let document: BSONDocument

    init(document: BSONDocument, fallbackIndex: Int) {
        self.document = document
        if let rawId = document["_id"] {
            self.id = "id-\(String(describing: rawId))"
        } else {
            self.id = "row-\(fallbackIndex)"
        }
    }
}

// MARK: - DocumentTableView

struct DocumentTableView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var columnCustomization = TableColumnCustomization<DocumentRow>()
    @State private var localSelection: Set<String> = []
    let rows: [DocumentRow]
    @Binding var selection: Set<String>
    let isLoading: Bool

    init(documents: [BSONDocument], selection: Binding<Set<String>>, isLoading: Bool) {
        self.rows = documents.enumerated().map { index, doc in
            DocumentRow(document: doc, fallbackIndex: index)
        }
        self._selection = selection
        self.isLoading = isLoading
    }

    private var columns: [String] {
        guard !rows.isEmpty else { return [] }
        var keys = Set<String>()
        for row in rows {
            for pair in row.document {
                keys.insert(pair.key)
            }
        }
        if keys.isEmpty { return [] }
        return keys.sorted { lhs, rhs in
            if lhs == "_id" { return true }
            if rhs == "_id" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func typeString(for key: String) -> String {
        var observedTypes = Set<String>()
        for row in rows {
            if let value = row.document[key] {
                observedTypes.insert(typeName(for: value))
            }
        }
        if observedTypes.isEmpty { return "Unknown" }
        if observedTypes.count == 1 { return observedTypes.first! }
        return "Mixed"
    }

    private func typeName(for value: BSON) -> String {
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

    var body: some View {
        if isLoading && columns.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if columns.isEmpty {
            VStack {
                ContentUnavailableView(
                    "No documents",
                    systemImage: "doc.text",
                    description: Text("This collection is empty or the filter returned no results.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            Table(rows, selection: $localSelection, columnCustomization: $columnCustomization) {
                TableColumnForEach(columns, id: \.self) { key in
                    TableColumn(
                        Text("\(Text(key).bold()) \(Text(typeString(for: key)).foregroundStyle(.secondary))")
                    ) { row in
                        Text(displayValue(row.document[key], timeZone: globalSettings.displayTimeZone))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .customizationID(key)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .id(columns)
            .onAppear {
                localSelection = selection.intersection(Set(rows.map(\.id)))
            }
            .onChange(of: selection) { _, newValue in
                let normalized = newValue.intersection(Set(rows.map(\.id)))
                guard localSelection != normalized else { return }
                localSelection = normalized
            }
            .onChange(of: rows.map(\.id)) { _, rowIds in
                let validIds = Set(rowIds)
                let normalizedLocal = localSelection.intersection(validIds)
                if localSelection != normalizedLocal {
                    localSelection = normalizedLocal
                }
                if selection != normalizedLocal {
                    DispatchQueue.main.async {
                        selection = normalizedLocal
                    }
                }
            }
            .onChange(of: localSelection) { _, newValue in
                guard selection != newValue else { return }
                DispatchQueue.main.async {
                    selection = newValue
                }
            }
            .overlay {
                if isLoading {
                    VStack {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
    }

}

fileprivate let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter
}()

fileprivate func displayValue(_ value: BSON?, timeZone: TimeZone) -> String {
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

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone
    let isLoading: Bool

    var body: some View {
        if isLoading && documents.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documents.isEmpty {
            VStack {
                ContentUnavailableView(
                    "No documents",
                    systemImage: "curlybraces",
                    description: Text("This collection is empty or the filter returned no results.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(documents.enumerated()), id: \.offset) { index, doc in
                        JSONDocumentCard(index: index, document: doc, timeZone: timeZone)
                    }
                }
                .padding(16)
            }
            .overlay {
                if isLoading {
                    VStack {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - JSONDocumentCard

struct JSONDocumentCard: View {
    let index: Int
    let document: BSONDocument
    let timeZone: TimeZone

    private var nodes: [JSONNode] {
        document.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(nodes) { node in
                    JSONNodeView(node: node, depth: 0)
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

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
    }

    private var nodes: [JSONNode] {
        document.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
    }
}

// MARK: - JSONNode

struct JSONNode: Identifiable {
    let id = UUID()
    let key: String?
    let value: String
    let children: [JSONNode]?
    let rawValue: BSON

    init(key: String? = nil, value: BSON, timeZone: TimeZone) {
        self.key = key
        self.rawValue = value
        switch value {
        case .document(let doc):
            self.value = "{ \(doc.count) fields }"
            self.children = doc.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
        case .array(let array):
            self.value = "[ \(array.count) items ]"
            self.children = array.enumerated().map { index, item in
                JSONNode(key: "[\(index)]", value: item, timeZone: timeZone)
            }
        default:
            self.value = displayValue(value, timeZone: timeZone)
            self.children = nil
        }
    }
}

// MARK: - JSONNodeView

struct JSONNodeView: View {
    let node: JSONNode
    let depth: Int
    @State private var isExpanded: Bool = false

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

                if node.children != nil {
                    Button(action: { withAnimation(.spring(duration: 0.2)) { isExpanded.toggle() } }) {
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

            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    JSONNodeView(node: child, depth: depth + 1)
                }
            }
        }
    }

    private var valueColor: Color {
        if node.children != nil { return .secondary }
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
}

// MARK: - WelcomeScreenView

struct WelcomeScreenView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(isAnimating ? 0.3 : 0.15), Color.mint.opacity(isAnimating ? 0.15 : 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                
                Image(systemName: "leaf.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .green.opacity(0.4), radius: 12, y: 6)
            }
            .onAppear { isAnimating = true }
            
            VStack(spacing: 12) {
                if let db = sessionViewModel.selectedDatabase, !db.isEmpty {
                    Text("Viewing Database: \(db)")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Select a collection from the sidebar to continue")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Welcome to MongoDesktop")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Select a database and a collection to start exploring")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color.clear
                RadialGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.05), Color.clear]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
            }
        )
    }
}
