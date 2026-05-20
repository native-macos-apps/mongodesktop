import SwiftUI

// MARK: - QueryConsoleView

struct QueryConsoleView: View {
    @ObservedObject private var store = QueryHistoryStore.shared
    @State private var selectedEntryId: UUID?
    @State private var searchText = ""
    @State private var filterType: QueryHistoryType? = nil

    private var filteredEntries: [QueryHistoryEntry] {
        store.entries.filter { entry in
            let matchesType = filterType == nil || entry.queryType == filterType
            let matchesSearch = searchText.isEmpty
                || entry.database.localizedCaseInsensitiveContains(searchText)
                || entry.collection.localizedCaseInsensitiveContains(searchText)
                || entry.queryText.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            consoleHeader
            Divider().opacity(0.4)

            if filteredEntries.isEmpty {
                emptyState
            } else {
                HSplitView {
                    entryList
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                    detailPanel
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var consoleHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Query Console")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text("\(store.entries.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

            Spacer()

            // Filter by type
            HStack(spacing: 4) {
                filterButton(label: "find", type: .find)
                filterButton(label: "agg", type: .aggregate)
                filterButton(label: "idx", type: .index)
            }

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 120)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            Button(action: { store.clear() }) {
                Label("Clear", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Clear history")
            .disabled(store.entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func filterButton(label: String, type: QueryHistoryType) -> some View {
        let isActive = filterType == type
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                filterType = isActive ? nil : type
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? type.color : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    isActive ? type.color.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entry List

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEntries) { entry in
                    EntryRow(entry: entry, isSelected: selectedEntryId == entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEntryId = entry.id }
                    Divider().opacity(0.25)
                }
            }
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let id = selectedEntryId,
           let entry = store.entries.first(where: { $0.id == id }) {
            EntryDetailView(entry: entry)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a query to view details")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No queries yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Queries you run will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EntryRow

private struct EntryRow: View {
    let entry: QueryHistoryEntry
    let isSelected: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            // Type badge
            Image(systemName: entry.queryType.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(entry.isError ? .red : entry.queryType.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(entry.database).\(entry.collection)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if entry.isError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }

                Text(entry.queryText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if let duration = entry.duration {
                    Text(String(format: "%.0fms", duration * 1000))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(durationColor(duration))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private func durationColor(_ duration: TimeInterval) -> Color {
        if duration < 0.1 { return .green }
        if duration < 0.5 { return .yellow }
        return .red
    }
}

// MARK: - EntryDetailView

private struct EntryDetailView: View {
    let entry: QueryHistoryEntry

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Meta header
                HStack(spacing: 12) {
                    Label(entry.queryType.rawValue, systemImage: entry.queryType.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(entry.isError ? .red : entry.queryType.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (entry.isError ? Color.red : entry.queryType.color).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                    if entry.isError {
                        Label("Error", systemImage: "exclamationmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Spacer()

                    Text(Self.fullFormatter.string(from: entry.timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                detailRow(label: "Namespace", value: "\(entry.database).\(entry.collection)")

                if let duration = entry.duration {
                    detailRow(label: "Duration", value: String(format: "%.3f s (%.0f ms)", duration, duration * 1000))
                }

                if let count = entry.resultCount {
                    detailRow(label: "Results", value: "\(count) document\(count == 1 ? "" : "s")")
                }

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Query")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(entry.queryText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }

                if let errMsg = entry.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Error")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.8))
                            .textCase(.uppercase)

                        Text(errMsg)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
