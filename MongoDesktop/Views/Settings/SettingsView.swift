import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @EnvironmentObject private var mcpServerManager: MCPServerManager

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(globalSettings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            MCPSettingsTab()
                .environmentObject(globalSettings)
                .environmentObject(mcpServerManager)
                .tabItem {
                    Label("MCP Server", systemImage: "network")
                }
        }
        .frame(width: 480)
    }
}

// MARK: - GeneralSettingsTab

struct GeneralSettingsTab: View {
    @EnvironmentObject private var globalSettings: GlobalSettings

    private var availableTimeZoneIds: [String] {
        sortedTimeZoneIds(TimeZone.knownTimeZoneIdentifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Performance Monitoring Setting
            VStack(alignment: .leading, spacing: 6) {
                Text("Performance Monitor")
                    .font(.headline)

                HStack(spacing: 10) {
                    Text("Sample Interval:")
                        .font(.callout)
                    Picker("", selection: $globalSettings.performancePollingInterval) {
                        Text("1 second (Default)").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                    }
                    .frame(width: 170)
                    Spacer()
                }

                Text("Frequency of polling serverStatus, top, and currentOp metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Timezone Setting
            VStack(alignment: .leading, spacing: 6) {
                Text("Timezone")
                    .font(.headline)

                Text("Used to format and display all Date/Timestamp fields throughout the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Display Timezone:")
                        .font(.callout)

                    Picker("", selection: $globalSettings.displayTimeZoneId) {
                        if globalSettings.displayTimeZoneId != TimeZone.current.identifier {
                            Text("System: \(timeZoneDisplayName(for: TimeZone.current.identifier))")
                                .tag(TimeZone.current.identifier)
                            Divider()
                        }

                        ForEach(availableTimeZoneIds, id: \.self) { id in
                            Text(timeZoneDisplayName(for: id)).tag(id)
                        }
                    }
                    .frame(maxWidth: 240)

                    Button("System") {
                        globalSettings.displayTimeZoneId = TimeZone.current.identifier
                    }
                    .controlSize(.small)
                    .disabled(globalSettings.displayTimeZoneId == TimeZone.current.identifier)

                    Spacer()
                }

                HStack(spacing: 6) {
                    Text("Preview:")
                        .foregroundStyle(.secondary)
                    Text(exampleDateString())
                        .font(.system(.caption, design: .monospaced))
                }
                .font(.caption)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 480, height: 280)
    }

    private func exampleDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.timeZone = globalSettings.displayTimeZone
        return formatter.string(from: Date())
    }

    private func sortedTimeZoneIds(_ ids: [String]) -> [String] {
        let now = Date()
        return ids.sorted { lhs, rhs in
            let ltz = TimeZone(identifier: lhs)
            let rtz = TimeZone(identifier: rhs)
            let lo = ltz?.secondsFromGMT(for: now) ?? 0
            let ro = rtz?.secondsFromGMT(for: now) ?? 0
            if lo != ro { return lo < ro }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func timeZoneDisplayName(for id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let now = Date()
        let offset = offsetString(seconds: tz.secondsFromGMT(for: now))
        let city = id.replacingOccurrences(of: "_", with: " ")
        return "\(offset)  \(city)"
    }

    private func offsetString(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let total = abs(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }
}

// MARK: - MCPSettingsTab

struct MCPSettingsTab: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @EnvironmentObject private var mcpServerManager: MCPServerManager

    @State private var portString: String = ""
    @State private var showCopiedAlert: Bool = false
    @State private var copiedMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Context Protocol (MCP) Server")
                    .font(.headline)
                Text("Expose MongoDB operations to AI assistants (Claude, Cursor, etc.) over local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Status Card
            statusCard

            Divider()

            // Server Configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Configuration")
                    .font(.subheadline.bold())

                Toggle("Enable MCP Server", isOn: $globalSettings.mcpServerEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack(spacing: 8) {
                    Text("Port:")
                        .font(.callout)
                        .frame(width: 40, alignment: .leading)

                    TextField("Port", text: $portString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            applyPortChange()
                        }

                    Button("Apply") {
                        applyPortChange()
                    }
                    .controlSize(.small)
                    .disabled(Int(portString) == globalSettings.mcpServerPort || !isPortValid(portString))

                    Button("Reset (27123)") {
                        globalSettings.mcpServerPort = 27123
                        portString = "27123"
                    }
                    .controlSize(.small)
                    .disabled(globalSettings.mcpServerPort == 27123)

                    Spacer()
                }

                if !isPortValid(portString) && !portString.isEmpty {
                    Text("Port must be a number between 1024 and 65535.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Read-Only Mode (Recommended)", isOn: $globalSettings.mcpServerReadOnly)
                    .toggleStyle(.checkbox)
                    .font(.callout)

                Text("When enabled, write operations (insert, update, delete) are rejected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Client Configuration
            VStack(alignment: .leading, spacing: 8) {
                Text("Client Configuration")
                    .font(.subheadline.bold())

                Text("Add this to your Claude Desktop or Cursor MCP configuration:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        mcpServerManager.copyClaudeConfig()
                        copiedMessage = "Copied Claude Desktop configuration to clipboard!"
                        showCopiedAlert = true
                    } label: {
                        Label("Copy Claude Config", systemImage: "doc.on.doc")
                    }

                    Button {
                        mcpServerManager.copyCursorConfig()
                        copiedMessage = "Copied Cursor configuration to clipboard!"
                        showCopiedAlert = true
                    } label: {
                        Label("Copy Cursor Config", systemImage: "doc.on.doc")
                    }

                    if let url = URL(string: "http://127.0.0.1:\(globalSettings.mcpServerPort)/health") {
                        Link("Test Health", destination: url)
                            .font(.callout)
                    }

                    Spacer()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 480, height: 380)
        .onAppear {
            portString = String(globalSettings.mcpServerPort)
        }
        .alert(copiedMessage, isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusTitle)
                .font(.callout.weight(.medium))

            if mcpServerManager.isRunning {
                Text("•  \(mcpServerManager.sseURLString)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if let err = mcpServerManager.lastErrorMessage {
                Text("•  \(err)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text("•  Turn on above to allow AI connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if mcpServerManager.isRunning {
                Text("\(mcpServerManager.connectedClientsCount) client(s)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private var statusColor: Color {
        if mcpServerManager.isRunning {
            return .green
        } else if mcpServerManager.lastErrorMessage != nil {
            return .red
        } else if globalSettings.mcpServerEnabled {
            return .orange
        } else {
            return .gray
        }
    }

    private var statusTitle: String {
        if mcpServerManager.isRunning {
            return "Running"
        } else if mcpServerManager.lastErrorMessage != nil {
            return "Error"
        } else if globalSettings.mcpServerEnabled {
            return "Starting..."
        } else {
            return "Stopped"
        }
    }

    private func isPortValid(_ str: String) -> Bool {
        guard let p = Int(str) else { return false }
        return p >= 1024 && p <= 65535
    }

    private func applyPortChange() {
        if let p = Int(portString), p >= 1024 && p <= 65535 {
            globalSettings.mcpServerPort = p
        }
    }
}
