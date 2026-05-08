import SwiftUI

// MARK: - CollectionSidebarView

struct CollectionSidebarView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @Environment(\.databaseTabContext) private var tabContext
    @State private var collectionFilterText = ""

    private var filteredCollections: [String] {
        let keyword = collectionFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return sessionViewModel.collections }
        return sessionViewModel.collections.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    private func iconName(for collection: String) -> String {
        if sessionViewModel.timeSeriesCollections.contains(collection) {
            return "chart.xyaxis.line"
        }
        return "tablecells"
    }

    private var selectedCollectionBinding: Binding<String?> {
        Binding(
            get: { sessionViewModel.selectedCollection },
            set: { newValue in
                DispatchQueue.main.async {
                    if sessionViewModel.selectedCollection != newValue {
                        sessionViewModel.selectCollection(
                            database: sessionViewModel.selectedDatabase,
                            collection: newValue
                        )
                        if let db = sessionViewModel.selectedDatabase, let col = newValue {
                            tabContext?.open(db, col)
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text("Collections")
                    .font(.headline)
                Spacer()
                Text("\(filteredCollections.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter collections", text: $collectionFilterText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 8)

            if sessionViewModel.collections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No collections")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCollections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No collections found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCollections, id: \.self, selection: selectedCollectionBinding) { col in
                    Label(col, systemImage: iconName(for: col))
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.ultraThinMaterial)
    }
}
