import Foundation
import SwiftUI

@MainActor
final class DatabaseSessionViewModel: ObservableObject {
    @Published var selectedConnectionId: ConnectionProfile.ID?
    @Published var isConnected = false
    @Published var statusMessage = "Not connected"
    @Published var databases: [String] = []
    @Published var collections: [String] = []
    @Published var timeSeriesCollections: Set<String> = []
    @Published var selectedDatabase: String?
    @Published var selectedCollection: String?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var connectionName = ""
    @Published var serverVersion = ""

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    func connect(using connection: ConnectionProfile, store: ConnectionStore) {
        Task { @MainActor in
            isLoading = true
            lastError = nil
            statusMessage = "Connecting..."
            connectionName = connection.name
            selectedConnectionId = connection.id
            selectedDatabase = connection.database.isEmpty ? nil : connection.database
            selectedCollection = nil

            do {
                let uri: String
                let fallbackURI: String?
                let forwardMap: [String: Int]?
                let fallbackForwardMap: [String: Int]?
                if connection.useSSHTunnel {
                    statusMessage = "Setting up SSH tunnel…"
                    #if DEBUG
                    print("[SSH] Starting local forwarding → \(connection.sshTunnel.sshUser)@\(connection.sshTunnel.sshHost):\(connection.sshTunnel.sshPort)")
                    #endif

                    let targets: [SSHForwardTarget]
                    let extraOptions: [String: String]
                    let directConnection: Bool

                    if connection.useSRV {
                        statusMessage = "Resolving MongoDB SRV records…"
                        let (records, txt) = await DNSDebugService.resolveSRVAndTXT(host: connection.host)
                        guard !records.isEmpty else {
                            throw SSHTunnelError.configInvalid("No SRV records found for \(connection.host)")
                        }
                        targets = records.map {
                            SSHForwardTarget(host: $0.target, port: Int($0.port))
                        }
                        extraOptions = txt.items
                        directConnection = false
                    } else {
                        targets = [SSHForwardTarget(host: connection.host, port: connection.port)]
                        extraOptions = [:]
                        directConnection = true
                    }

                    statusMessage = "Opening SSH forwards…"
                    let forwards = try await SSHTunnelService.shared.startLocalForwarding(
                        config: connection.sshTunnel,
                        targets: targets
                    )
                    let endpoints = forwards.map { "\($0.remoteHost):\($0.remotePort)" }
                    forwardMap = Dictionary(
                        uniqueKeysWithValues: forwards.map {
                            ("\($0.remoteHost.lowercased()):\($0.remotePort)", $0.localPort)
                        }
                    )
                    uri = connection.localForwardConnectionString(
                        endpoints: endpoints,
                        extraOptions: extraOptions,
                        directConnection: directConnection
                    )
                    if connection.useSRV, let firstForward = forwards.first {
                        let firstEndpoint = "\(firstForward.remoteHost):\(firstForward.remotePort)"
                        fallbackURI = connection.localForwardConnectionString(
                            endpoints: [firstEndpoint],
                            extraOptions: extraOptions,
                            directConnection: true
                        )
                        fallbackForwardMap = [
                            "\(firstForward.remoteHost.lowercased()):\(firstForward.remotePort)": firstForward.localPort
                        ]
                    } else {
                        fallbackURI = nil
                        fallbackForwardMap = nil
                    }
                    #if DEBUG
                    print("[SSH] Local forwards ready: \(forwards)")
                    print("[SSH] MongoDB URI: \(uri)")
                    #endif
                } else {
                    uri = connection.connectionString
                    fallbackURI = nil
                    forwardMap = nil
                    fallbackForwardMap = nil
                }

                do {
                    try await mongoService.connect(uri: uri, tunnelForwardMap: forwardMap)
                } catch {
                    guard let fallbackURI else { throw error }
                    #if DEBUG
                    print("[SSH] Seed-list connection failed, retrying direct local forward: \(fallbackURI)")
                    #endif
                    try await mongoService.connect(uri: fallbackURI, tunnelForwardMap: fallbackForwardMap)
                }
                isConnected = true
                statusMessage = "Connected: \(connection.name)"
                store.markConnected(connection.id)
                async let versionFetch: Void = fetchServerVersion()
                await refreshDatabases()
                await versionFetch
            } catch {
                isConnected = false
                statusMessage = "Connection failed"
                lastError = error.localizedDescription
                if connection.useSSHTunnel {
                    await SSHTunnelService.shared.stopTunnel()
                }
            }

            isLoading = false
        }
    }

    func disconnect() async throws {
        try await mongoService.disconnect()
        await SSHTunnelService.shared.stopTunnel()
        resetConnectionState(statusMessage: "Disconnected")
    }

    func fetchServerVersion() async {
        do {
            serverVersion = try await mongoService.serverVersion()
        } catch {
            // Non-critical metadata.
        }
    }

    func refreshDatabases() async {
        isLoading = true
        lastError = nil

        do {
            let list = try await mongoService.listDatabases()
            databases = list
            if let selectedDatabase, !list.contains(selectedDatabase) {
                self.selectedDatabase = nil
            }
            if selectedDatabase == nil {
                selectedDatabase = list.first
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
        if let selectedDatabase {
            await refreshCollections(database: selectedDatabase)
        }
    }

    func refreshCollections(database: String) async {
        isLoading = true
        lastError = nil

        do {
            let infos = try await mongoService.listCollectionInfos(database: database)
            collections = infos.map(\.name)
            timeSeriesCollections = Set(infos.filter(\.isTimeSeries).map(\.name))
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    func selectDatabase(_ database: String) {
        selectedDatabase = database
        selectedCollection = nil
        Task { await refreshCollections(database: database) }
    }

    func selectCollection(database: String?, collection: String?) {
        if let database {
            selectedDatabase = database
        }
        selectedCollection = collection
    }

    func clearError() {
        lastError = nil
    }

    private func resetConnectionState(statusMessage: String) {
        isConnected = false
        self.statusMessage = statusMessage
        databases = []
        collections = []
        timeSeriesCollections = []
        selectedDatabase = nil
        selectedCollection = nil
        serverVersion = ""
    }
}
