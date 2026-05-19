import SwiftUI
import SwiftBSON

// MARK: - DocumentTableView

struct DocumentTableView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var columnCustomization = TableColumnCustomization<DocumentRow>()
    @State private var localSelection: Set<String> = []
    @State private var selectedRowForDetail: DocumentRow? = nil
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
            .contextMenu {
                if let firstId = localSelection.first,
                   let row = rows.first(where: { $0.id == firstId }) {
                    Button {
                        selectedRowForDetail = row
                    } label: {
                        Label("View Document Detail", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    Divider()
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.document.toCanonicalExtendedJSONString(), forType: .string)
                    } label: {
                        Label("Copy (BSON)", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.document.toRelaxedExtendedJSONString(), forType: .string)
                    } label: {
                        Label("Copy JSON", systemImage: "curlybraces")
                    }
                }
            }
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
            .sheet(item: $selectedRowForDetail) { row in
                NavigationStack {
                    ScrollView {
                        JSONDocumentCard(
                            index: rows.firstIndex(where: { $0.id == row.id }) ?? 0,
                            document: row.document,
                            timeZone: globalSettings.displayTimeZone
                        )
                        .padding()
                    }
                    .navigationTitle("Document Detail")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                selectedRowForDetail = nil
                            }
                        }
                    }
                }
                .frame(minWidth: 500, minHeight: 400)
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
