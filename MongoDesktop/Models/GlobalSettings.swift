import Foundation

// MARK: - GlobalSettings (shared across windows)

@MainActor
final class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    /// Timezone identifier used to display date fields in the UI (default: local timezone).
    @Published var displayTimeZoneId: String {
        didSet {
            defaults.set(displayTimeZoneId, forKey: Self.displayTimeZoneIdKey)
        }
    }

    /// Polling interval (seconds) for real-time performance monitoring (default: 1.0s).
    @Published var performancePollingInterval: Double {
        didSet {
            defaults.set(performancePollingInterval, forKey: Self.performancePollingIntervalKey)
        }
    }

    /// Whether the MCP (Model Context Protocol) Server is enabled.
    @Published var mcpServerEnabled: Bool {
        didSet {
            defaults.set(mcpServerEnabled, forKey: Self.mcpServerEnabledKey)
        }
    }

    /// Port on which the MCP Server listens (default: 27123).
    @Published var mcpServerPort: Int {
        didSet {
            let clamped = max(1024, min(65535, mcpServerPort))
            if clamped != mcpServerPort {
                mcpServerPort = clamped
                return
            }
            defaults.set(mcpServerPort, forKey: Self.mcpServerPortKey)
        }
    }

    /// Whether the MCP Server operates in read-only mode (prevents write/delete ops).
    @Published var mcpServerReadOnly: Bool {
        didSet {
            defaults.set(mcpServerReadOnly, forKey: Self.mcpServerReadOnlyKey)
        }
    }

    var displayTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZoneId) ?? .current
    }

    private static let displayTimeZoneIdKey = "displayTimeZoneId"
    private static let performancePollingIntervalKey = "performancePollingInterval"
    private static let mcpServerEnabledKey = "mcpServerEnabled"
    private static let mcpServerPortKey = "mcpServerPort"
    private static let mcpServerReadOnlyKey = "mcpServerReadOnly"
    private let defaults = UserDefaults.standard

    private init() {
        if let saved = defaults.string(forKey: Self.displayTimeZoneIdKey), !saved.isEmpty {
            displayTimeZoneId = saved
        } else {
            displayTimeZoneId = TimeZone.current.identifier
        }

        let savedInterval = defaults.double(forKey: Self.performancePollingIntervalKey)
        if savedInterval > 0 {
            performancePollingInterval = savedInterval
        } else {
            performancePollingInterval = 1.0
        }

        if defaults.object(forKey: Self.mcpServerEnabledKey) != nil {
            mcpServerEnabled = defaults.bool(forKey: Self.mcpServerEnabledKey)
        } else {
            mcpServerEnabled = false
        }

        let savedPort = defaults.integer(forKey: Self.mcpServerPortKey)
        if savedPort >= 1024 && savedPort <= 65535 {
            mcpServerPort = savedPort
        } else {
            mcpServerPort = 27123
        }

        if defaults.object(forKey: Self.mcpServerReadOnlyKey) != nil {
            mcpServerReadOnly = defaults.bool(forKey: Self.mcpServerReadOnlyKey)
        } else {
            mcpServerReadOnly = true
        }
    }
}
