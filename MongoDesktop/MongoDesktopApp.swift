import SwiftUI
import AppKit

// MARK: - WindowCoordinator

/// Manages the singleton Connections window (hide / show).
@MainActor
final class WindowCoordinator: ObservableObject {
    static let shared = WindowCoordinator()
    private init() {}

    private weak var connectionsWindow: NSWindow?

    func registerConnectionsWindow(_ window: NSWindow?) {
        connectionsWindow = window
    }

    /// Hides the Connections window (called after connecting)
    func hideConnectionsWindow() {
        connectionsWindow?.orderOut(nil)
    }

    /// Shows the Connections window again (called when a database window closes)
    func showConnectionsWindow() {
        if let win = connectionsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - App

@main
struct MongoDesktopApp: App {
    @StateObject private var connectionStore = ConnectionStore()

    var body: some Scene {
        // Main window: Connections list (singleton)
        WindowGroup("Connections") {
            ConnectionsListView()
                .environmentObject(connectionStore)
                .environmentObject(GlobalSettings.shared)
        }
        .defaultSize(width: 720, height: 500)

        // Database windows: one per connection (opened via openWindow(value:))
        WindowGroup("Database", for: ConnectionProfile.ID.self) { $connectionId in
            DatabaseWindowView(connectionId: connectionId)
                .environmentObject(connectionStore)
                .environmentObject(GlobalSettings.shared)
        }
        .defaultSize(width: 1000, height: 720)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(GlobalSettings.shared)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
    }
}
