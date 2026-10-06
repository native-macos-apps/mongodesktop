import Foundation
import AppKit
import SwiftUI

// MARK: - Query Completion View Model

@MainActor
final class QueryCompletionViewModel: ObservableObject {
    @Published var items: [QueryCompletionItem] = []
    @Published var selectedIndex: Int = 0
    @Published var query: String = ""

    var selectedItem: QueryCompletionItem? {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    func moveUp() -> Bool {
        guard !items.isEmpty else { return false }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        return true
    }

    func moveDown() -> Bool {
        guard !items.isEmpty else { return false }
        selectedIndex = (selectedIndex + 1) % items.count
        return true
    }
}

// MARK: - Query Completion Window Controller

@MainActor
final class QueryCompletionWindowController: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<QueryCompletionOverlayView>?
    let viewModel = QueryCompletionViewModel()

    private(set) var isVisible: Bool = false
    private weak var currentParentWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    var onItemSelected: ((QueryCompletionItem) -> Void)?

    var items: [QueryCompletionItem] { viewModel.items }
    var selectedIndex: Int { viewModel.selectedIndex }
    var currentQuery: String { viewModel.query }

    override init() {
        super.init()
    }

    deinit {
        // Safe synchronous cleanup of observers and event monitor
        for obs in windowObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Show & Position Panel

    func show(
        items: [QueryCompletionItem],
        query: String,
        screenRect: NSRect,
        parentWindow: NSWindow? = nil
    ) {
        guard !items.isEmpty else {
            hide()
            return
        }

        viewModel.items = items
        viewModel.query = query
        viewModel.selectedIndex = 0
        self.currentParentWindow = parentWindow

        ensurePanel()

        guard let panel = panel else { return }

        // Position calculation
        let panelWidth: CGFloat = 280
        let itemHeight: CGFloat = 24
        let panelHeight: CGFloat = min(190, max(38, CGFloat(items.count) * itemHeight + 10))
        let screenFrame = parentWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = screenRect.origin.x
        // Avoid overflowing right edge
        if x + panelWidth > screenFrame.maxX - 10 {
            x = screenFrame.maxX - panelWidth - 10
        }
        if x < screenFrame.minX + 10 {
            x = screenFrame.minX + 10
        }

        // Default position: below cursor
        var y = screenRect.origin.y - panelHeight - 4
        // If overflowing bottom edge, flip above cursor
        if y < screenFrame.minY + 10 {
            y = screenRect.origin.y + screenRect.height + 4
        }

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        if let parentWindow = parentWindow {
            if panel.parent !== parentWindow {
                if let oldParent = panel.parent {
                    oldParent.removeChildWindow(panel)
                }
                parentWindow.addChildWindow(panel, ordered: .above)
            }
        } else {
            panel.orderFront(nil)
        }

        setupObservers(for: parentWindow)
        startEventMonitor()
        isVisible = true
    }

    // MARK: - Hide Panel

    func hide() {
        guard isVisible else { return }
        removeObservers()
        stopEventMonitor()

        if let parent = panel?.parent {
            parent.removeChildWindow(panel!)
        }
        panel?.orderOut(nil)
        currentParentWindow = nil
        isVisible = false
        viewModel.items = []
        viewModel.selectedIndex = 0
    }

    // MARK: - Keyboard Navigation

    func moveUp() -> Bool {
        guard isVisible else { return false }
        return viewModel.moveUp()
    }

    func moveDown() -> Bool {
        guard isVisible else { return false }
        return viewModel.moveDown()
    }

    func selectedItem() -> QueryCompletionItem? {
        guard isVisible else { return nil }
        return viewModel.selectedItem
    }

    // MARK: - Private Setup

    private func ensurePanel() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 190),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.hasShadow = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isMovable = false

            let overlayView = QueryCompletionOverlayView(
                viewModel: viewModel,
                onSelect: { [weak self] item in
                    self?.onItemSelected?(item)
                }
            )
            let hosting = NSHostingView(rootView: overlayView)
            panel.contentView = hosting
            self.hostingView = hosting
            self.panel = panel
        }
    }

    private func setupObservers(for parentWindow: NSWindow?) {
        removeObservers()

        if let parentWindow = parentWindow {
            let obsMove = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.hide()
            }
            let obsResize = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.hide()
            }
            let obsResign = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.hide()
            }
            windowObservers.append(contentsOf: [obsMove, obsResize, obsResign])
        }

        let obsApp = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
        windowObservers.append(obsApp)
    }

    private func removeObservers() {
        for obs in windowObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        windowObservers.removeAll()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible, let panel = self.panel else { return event }
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                self.hide()
            }
            return event
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
