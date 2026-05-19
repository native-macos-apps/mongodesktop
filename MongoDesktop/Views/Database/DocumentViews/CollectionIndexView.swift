import SwiftUI
import SwiftBSON

struct CollectionIndexView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Index Header/Toolbar
            HStack {
                Label("Indexes", systemImage: "magnifyingglass.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: refreshIndexes) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            if tabViewModel.isIndexesLoading {
                VStack {
                    Spacer()
                    ProgressView("Retrieving collection indexes...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = tabViewModel.indexesError {
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
            } else if tabViewModel.indexes.isEmpty {
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
                Table(indexRows) {
                    TableColumn("Name") { row in
                        HStack(spacing: 8) {
                            Text(row.name)
                                .font(.body.bold())
                                .foregroundColor(.primary)
                            
                            if row.name == "_id_" {
                                Text("Primary")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    
                    TableColumn("Keys") { row in
                        Text(row.key.toCanonicalExtendedJSONString())
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    TableColumn("Unique") { row in
                        if row.isUnique {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Unique")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("No")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    TableColumn("Sparse") { row in
                        if row.isSparse {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Sparse")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        } else {
                            Text("No")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    TableColumn("TTL") { row in
                        if let ttl = row.ttl {
                            Text("\(ttl)s")
                                .foregroundColor(.secondary)
                        } else {
                            Text("-")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    TableColumn("Version") { row in
                        Text("v\(row.version)")
                            .foregroundColor(.secondary)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            refreshIndexes()
        }
    }
    
    private func refreshIndexes() {
        Task { await tabViewModel.fetchIndexes(using: sessionViewModel) }
    }
    
    private var indexRows: [IndexRow] {
        tabViewModel.indexes.enumerated().map { offset, doc in
            let name = doc["name"]?.stringValue ?? "index-\(offset)"
            let key = doc["key"]?.documentValue ?? BSONDocument()
            let isUnique = doc["unique"]?.boolValue ?? false
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
            
            return IndexRow(
                id: name,
                name: name,
                key: key,
                isUnique: isUnique,
                isSparse: isSparse,
                ttl: ttl,
                version: version,
                rawDocument: doc
            )
        }
    }
}

struct IndexRow: Identifiable {
    let id: String
    let name: String
    let key: BSONDocument
    let isUnique: Bool
    let isSparse: Bool
    let ttl: Int?
    let version: String
    let rawDocument: BSONDocument
}
