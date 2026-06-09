import Foundation

@MainActor
final class DatabaseWindowViewModel: ObservableObject {
    struct Tab: Identifiable {
        let id: UUID
        let viewModel: QueryTabViewModel
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedTabId: Tab.ID?

    var selectedTab: Tab? {
        guard let selectedTabId else { return nil }
        return tabs.first { $0.id == selectedTabId }
    }

    func ensureInitialTab(session: DatabaseSessionViewModel) {
        guard tabs.isEmpty else { return }
        addTab(prefillingFrom: session)
    }

    func addTab(prefillingFrom session: DatabaseSessionViewModel) {
        let viewModel = QueryTabViewModel()
        viewModel.configure(database: session.selectedDatabase, collection: session.selectedCollection)
        let tab = Tab(id: UUID(), viewModel: viewModel)
        tabs.append(tab)
        selectedTabId = tab.id
        viewModel.loadInitialDocumentsIfPossible(session: session)
    }

    func openTab(database: String, collection: String, session: DatabaseSessionViewModel) {
        if let existingTab = tabs.first(where: {
            $0.viewModel.databaseName == database && $0.viewModel.collectionName == collection
        }) {
            selectedTabId = existingTab.id
            session.selectCollection(database: database, collection: collection)
            return
        }

        if let selectedTabId,
           let index = tabs.firstIndex(where: { $0.id == selectedTabId }),
           tabs[index].viewModel.collectionName == nil {
            let viewModel = tabs[index].viewModel
            viewModel.openCollection(database: database, collection: collection, session: session)
            return
        }

        let viewModel = QueryTabViewModel()
        viewModel.openCollection(database: database, collection: collection, session: session)

        let tab = Tab(id: UUID(), viewModel: viewModel)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    func selectTab(_ id: UUID, session: DatabaseSessionViewModel) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTabId = id
        session.selectCollection(database: tab.viewModel.databaseName, collection: tab.viewModel.collectionName)
    }

    func closeTab(_ id: UUID, session: DatabaseSessionViewModel) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        if tabs.isEmpty {
            addTab(prefillingFrom: session)
            return
        }

        if selectedTabId == id {
            let newIndex = min(index, tabs.count - 1)
            let replacement = tabs[newIndex]
            selectedTabId = replacement.id
            session.selectCollection(
                database: replacement.viewModel.databaseName,
                collection: replacement.viewModel.collectionName
            )
        }
    }

    func tabContext(session: DatabaseSessionViewModel) -> DatabaseTabContext {
        let items = tabs.enumerated().map { index, tab in
            DatabaseTabItem(
                id: tab.id,
                title: tabTitle(for: tab.viewModel, fallbackIndex: index + 1)
            )
        }

        return DatabaseTabContext(
            tabs: items,
            selectedId: selectedTabId,
            select: { [weak self] id in
                self?.selectTab(id, session: session)
            },
            close: { [weak self] id in
                self?.closeTab(id, session: session)
            },
            add: { [weak self] in
                self?.addTab(prefillingFrom: session)
            },
            open: { [weak self] database, collection in
                self?.openTab(database: database, collection: collection, session: session)
            }
        )
    }

    private func tabTitle(for viewModel: QueryTabViewModel, fallbackIndex: Int) -> String {
        if !viewModel.title.isEmpty { return viewModel.title }
        if let collection = viewModel.collectionName, !collection.isEmpty { return collection }
        if let database = viewModel.databaseName, !database.isEmpty { return database }
        return "Tab \(fallbackIndex)"
    }
}
