import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - MCPServerManager

@MainActor
final class MCPServerManager: ObservableObject {
    static let shared = MCPServerManager()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var activePort: Int = 27123
    @Published private(set) var statusDescription: String = "Stopped"
    @Published private(set) var lastErrorMessage: String? = nil
    @Published private(set) var connectedClientsCount: Int = 0

    private let server = MCPServer()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupServerCallbacks()
        setupSettingsObservation()
    }

    private func setupServerCallbacks() {
        server.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .running(let port):
                    self.isRunning = true
                    self.activePort = port
                    self.statusDescription = "Running on port \(port)"
                    self.lastErrorMessage = nil
                case .stopped:
                    self.isRunning = false
                    self.statusDescription = "Stopped"
                    self.connectedClientsCount = 0
                case .starting:
                    self.isRunning = false
                    self.statusDescription = "Starting..."
                    self.lastErrorMessage = nil
                case .error(let message):
                    self.isRunning = false
                    self.statusDescription = "Error"
                    self.lastErrorMessage = message
                }
            }
        }

        server.onClientCountChange = { [weak self] count in
            DispatchQueue.main.async {
                self?.connectedClientsCount = count
            }
        }
    }

    private func setupSettingsObservation() {
        let settings = GlobalSettings.shared

        Publishers.CombineLatest(settings.$mcpServerEnabled, settings.$mcpServerPort)
            .dropFirst()
            .sink { [weak self] enabled, port in
                self?.handleSettingsChange(enabled: enabled, port: port)
            }
            .store(in: &cancellables)
    }

    private func handleSettingsChange(enabled: Bool, port: Int) {
        if enabled {
            start(port: port)
        } else {
            stop()
        }
    }

    // MARK: - Lifecycle Controls

    func startIfNeeded() {
        let settings = GlobalSettings.shared
        if settings.mcpServerEnabled {
            start(port: settings.mcpServerPort)
        }
    }

    func start(port: Int) {
        activePort = port
        lastErrorMessage = nil
        server.start(port: port)
    }

    func stop() {
        server.stop()
    }

    func restart(port: Int) {
        start(port: port)
    }

    // MARK: - Quick Configuration Helpers

    var sseURLString: String {
        "http://127.0.0.1:\(activePort)/sse"
    }

    var claudeConfigSnippet: String {
        """
        {
          "mcpServers": {
            "mongodesktop": {
              "url": "\(sseURLString)"
            }
          }
        }
        """
    }

    var cursorConfigSnippet: String {
        """
        {
          "mcpServers": {
            "mongodesktop": {
              "url": "\(sseURLString)"
            }
          }
        }
        """
    }

    func copyClaudeConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(claudeConfigSnippet, forType: .string)
    }

    func copyCursorConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cursorConfigSnippet, forType: .string)
    }
}
