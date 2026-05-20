import SwiftUI
import SwiftBSON

struct CollectionIndexView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var indexVM: IndexQueryViewModel
    @State private var isShowingCreateDialog = false
    @State private var selectedIndexId: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Index Header/Toolbar
            HStack {
                Label("Indexes", systemImage: "magnifyingglass.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: refreshIndexes) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: {
                        isShowingCreateDialog = true
                    }) {
                        Label("Create Index", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            if indexVM.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Retrieving collection indexes...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = indexVM.error {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.red)
                    Text("Failed to retrieve indexes")
                        .font(.headline)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if indexVM.indexes.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No Indexes Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(indexRows, children: \.children, selection: $selectedIndexId) {
                    TableColumn("Name and Definition") { row in
                        if row.children != nil {
                            // Parent row: Index Name
                            Text(row.name)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.primary)
                        } else {
                            // Child row: Field path and value
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(row.name)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(":")
                                    .foregroundColor(.secondary)
                                Text(row.definition ?? "")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                    
                    TableColumn("Type") { row in
                        if let type = row.type {
                            IndexBadgeView(label: type)
                        }
                    }
                    
                    TableColumn("Size") { row in
                        if let sizeBytes = row.sizeBytes {
                            Text(formatSize(sizeBytes) ?? "-")
                                .font(.body.monospacedDigit())
                        }
                    }
                    
                    TableColumn("Usage") { row in
                        if let usageCount = row.usageCount {
                            Text("\(usageCount)")
                                .font(.body.monospacedDigit())
                        }
                    }
                    
                    TableColumn("Properties") { row in
                        if row.children != nil {
                            HStack(spacing: 6) {
                                if row.isUnique {
                                    IndexBadgeView(label: "UNIQUE")
                                }
                                if row.isCompound {
                                    IndexBadgeView(label: "COMPOUND")
                                }
                                if row.isSparse {
                                    IndexBadgeView(label: "SPARSE")
                                }
                                if row.ttl != nil {
                                    IndexBadgeView(label: "TTL")
                                }
                            }
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            refreshIndexes()
        }
        .alert("Create Index", isPresented: $isShowingCreateDialog) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Index creation interface will be added in a future update.")
        }
    }
    
    private func refreshIndexes() {
        guard let db = sessionViewModel.selectedDatabase,
              let col = sessionViewModel.selectedCollection else { return }
        Task { await indexVM.fetchIndexes(database: db, collection: col, session: sessionViewModel) }
    }
    
    private func formatSize(_ bytes: Int64) -> String? {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private var indexRows: [IndexRow] {
        indexVM.indexes.enumerated().map { offset, doc in
            let name = doc["name"]?.stringValue ?? "index-\(offset)"
            let key = doc["key"]?.documentValue ?? BSONDocument()
            
            // Build children representing key paths
            var children: [IndexRow] = []
            for (keyPath, valueBson) in key {
                let valStr: String
                switch valueBson {
                case .int32(let i): valStr = String(i)
                case .int64(let i): valStr = String(i)
                case .double(let d): valStr = String(Int(d))
                case .string(let s): valStr = "\"\(s)\""
                default: valStr = String(describing: valueBson)
                }
                children.append(IndexRow(
                    id: "\(name)-\(keyPath)",
                    name: keyPath,
                    definition: valStr,
                    type: nil,
                    sizeBytes: nil,
                    usageCount: nil,
                    isUnique: false,
                    isCompound: false,
                    isSparse: false,
                    ttl: nil,
                    version: "",
                    children: nil
                ))
            }
            
            // Determine type
            var type = "REGULAR"
            for (_, val) in key {
                if let str = val.stringValue {
                    if str == "2dsphere" || str == "2d" {
                        type = "GEOSPATIAL"
                        break
                    } else if str == "text" {
                        type = "TEXT"
                        break
                    } else if str == "hashed" {
                        type = "HASHED"
                        break
                    }
                }
            }
            
            let isUnique = doc["unique"]?.boolValue ?? false
            let isCompound = key.count > 1
            let isSparse = doc["sparse"]?.boolValue ?? false
            let ttl = doc["expireAfterSeconds"]?.intValue
            
            let v = doc["v"]
            let version: String
            if let v {
                switch v {
                case .int32(let i): version = String(i)
                case .int64(let i): version = String(i)
                case .double(let d): version = String(Int(d))
                default: version = String(describing: v)
                }
            } else {
                version = "unknown"
            }
            
            let stats = indexVM.indexStats[name]
            
            return IndexRow(
                id: name,
                name: name,
                definition: nil,
                type: type,
                sizeBytes: stats?.size,
                usageCount: stats?.usage,
                isUnique: isUnique,
                isCompound: isCompound,
                isSparse: isSparse,
                ttl: ttl,
                version: version,
                children: children.isEmpty ? nil : children
            )
        }
    }
}

struct IndexBadgeView: View {
    let label: String
    
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
            Image(systemName: "info.circle.fill")
                .font(.system(size: 9))
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(white: 0.22))
        )
    }
}

struct IndexRow: Identifiable {
    let id: String
    let name: String
    let definition: String?
    let type: String?
    let sizeBytes: Int64?
    let usageCount: Int64?
    let isUnique: Bool
    let isCompound: Bool
    let isSparse: Bool
    let ttl: Int?
    let version: String
    var children: [IndexRow]?
}
