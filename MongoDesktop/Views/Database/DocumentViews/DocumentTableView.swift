import SwiftUI
import SwiftBSON

// MARK: - DocumentTableView

struct DocumentTableView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var columnCustomization = TableColumnCustomization<DocumentRow>()
    @State private var localSelection: Set<String> = []
    @State private var selectedRowForDetail: DocumentRow? = nil
    
    let rows: [DocumentRow]
    let columns: [String]
    let columnTypes: [String: String]
    @Binding var selection: Set<String>
    let isLoading: Bool

    init(rows: [DocumentRow], columns: [String], columnTypes: [String: String], selection: Binding<Set<String>>, isLoading: Bool) {
        self.rows = rows
        self.columns = columns
        self.columnTypes = columnTypes
        self._selection = selection
        self.isLoading = isLoading
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
                    let colType = columnTypes[key] ?? ""
                    TableColumn(
                        Text("\(Text(key).bold()) \(Text(colType).foregroundStyle(.secondary))")
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
                        let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                        let wrapper = JSONDocumentWrapper(
                            id: row.id,
                            index: index,
                            document: row.document,
                            nodes: JSONNode.rootNodes(for: row.document, timeZone: globalSettings.displayTimeZone)
                        )
                        JSONDocumentCardContainer(wrapper: wrapper)
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
