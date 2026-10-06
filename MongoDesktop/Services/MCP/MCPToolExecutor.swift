import Foundation
import SwiftBSON

// MARK: - MCPToolExecutor

actor MCPToolExecutor {
    static let shared = MCPToolExecutor()

    private var cachedServices: [UUID: MongoService] = [:]

    private init() {}

    /// Executes an MCP tool by name with the given dictionary arguments.
    func executeTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "mongodb_list_connections":
            return try await listConnections()

        case "mongodb_list_databases":
            let connection = arguments["connection"] as? String
            return try await listDatabases(connection: connection)

        case "mongodb_list_collections":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            return try await listCollections(connection: connection, database: database)

        case "mongodb_find":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            let filter = arguments["filter"] as? String ?? "{}"
            let projection = arguments["projection"] as? String
            let sort = arguments["sort"] as? String
            let limit = (arguments["limit"] as? Int) ?? 20
            let skip = (arguments["skip"] as? Int) ?? 0
            return try await findDocuments(
                connection: connection,
                database: database,
                collection: collection,
                filter: filter,
                projection: projection,
                sort: sort,
                limit: limit,
                skip: skip
            )

        case "mongodb_count":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            let filter = arguments["filter"] as? String ?? "{}"
            return try await countDocuments(connection: connection, database: database, collection: collection, filter: filter)

        case "mongodb_aggregate":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            guard let pipeline = arguments["pipeline"] as? String, !pipeline.isEmpty else {
                throw MCPError.invalidParams("Parameter 'pipeline' (JSON array) is required.")
            }
            return try await runAggregate(connection: connection, database: database, collection: collection, pipeline: pipeline)

        case "mongodb_explain":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            let filter = arguments["filter"] as? String ?? "{}"
            return try await explainQuery(connection: connection, database: database, collection: collection, filter: filter)

        case "mongodb_list_indexes":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            return try await listIndexes(connection: connection, database: database, collection: collection)

        case "mongodb_server_status":
            let connection = arguments["connection"] as? String
            return try await getServerStatus(connection: connection)

        case "mongodb_db_stats":
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            return try await getDbStats(connection: connection, database: database)

        case "mongodb_insert_document":
            try await checkWriteAllowed()
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            guard let documentJson = arguments["document"] as? String, !documentJson.isEmpty else {
                throw MCPError.invalidParams("Parameter 'document' (JSON string) is required.")
            }
            return try await insertDocument(connection: connection, database: database, collection: collection, documentJson: documentJson)

        case "mongodb_update_documents":
            try await checkWriteAllowed()
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            guard let filterJson = arguments["filter"] as? String, !filterJson.isEmpty else {
                throw MCPError.invalidParams("Parameter 'filter' (JSON string) is required.")
            }
            guard let updateJson = arguments["update"] as? String, !updateJson.isEmpty else {
                throw MCPError.invalidParams("Parameter 'update' (JSON string) is required.")
            }
            return try await updateDocuments(connection: connection, database: database, collection: collection, filterJson: filterJson, updateJson: updateJson)

        case "mongodb_delete_document":
            try await checkWriteAllowed()
            let connection = arguments["connection"] as? String
            guard let database = arguments["database"] as? String, !database.isEmpty else {
                throw MCPError.invalidParams("Parameter 'database' is required.")
            }
            guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
                throw MCPError.invalidParams("Parameter 'collection' is required.")
            }
            guard let filterJson = arguments["filter"] as? String, !filterJson.isEmpty else {
                throw MCPError.invalidParams("Parameter 'filter' (JSON string) is required.")
            }
            return try await deleteDocument(connection: connection, database: database, collection: collection, filterJson: filterJson)

        default:
            throw MCPError.methodNotFound("Tool '\(name)' is not recognized.")
        }
    }

    // MARK: - Connection & Service Resolution

    private func resolveService(for connectionQuery: String?) async throws -> (service: MongoService, connectionName: String) {
        let (profile, fallbackShared) = await MainActor.run { () -> (ConnectionProfile?, Bool) in
            let store = ConnectionStore.shared
            if let query = connectionQuery, !query.isEmpty {
                return (store.find(namedOrId: query), false)
            }
            // If no specific connection was provided, try using first saved profile or active session
            if let first = store.connections.first {
                return (first, false)
            }
            return (nil, true)
        }

        if let profile {
            if let existing = cachedServices[profile.id] {
                return (existing, profile.name)
            }
            let service = MongoService()
            if profile.useSSHTunnel {
                let targets: [SSHForwardTarget]
                let extraOptions: [String: String]
                let directConnection: Bool

                if profile.useSRV {
                    let (records, txt) = await DNSDebugService.resolveSRVAndTXT(host: profile.host)
                    guard !records.isEmpty else {
                        throw MCPError.executionFailed("No SRV records found for \(profile.host)")
                    }
                    targets = records.map { SSHForwardTarget(host: $0.target, port: Int($0.port)) }
                    extraOptions = txt.items
                    directConnection = false
                } else {
                    targets = [SSHForwardTarget(host: profile.host, port: profile.port)]
                    extraOptions = [:]
                    directConnection = true
                }

                let forwards = try await SSHTunnelService.shared.startLocalForwarding(
                    config: profile.sshTunnel,
                    targets: targets
                )
                let endpoints = forwards.map { "\($0.remoteHost):\($0.remotePort)" }
                let forwardMap = Dictionary(
                    uniqueKeysWithValues: forwards.map {
                        ("\($0.remoteHost.lowercased()):\($0.remotePort)", $0.localPort)
                    }
                )
                let uri = profile.localForwardConnectionString(
                    endpoints: endpoints,
                    extraOptions: extraOptions,
                    directConnection: directConnection
                )
                try await service.connect(uri: uri, tunnelForwardMap: forwardMap)
            } else {
                try await service.connect(uri: profile.connectionString)
            }
            cachedServices[profile.id] = service
            return (service, profile.name)
        }

        if fallbackShared {
            // Fallback to MongoService.shared
            return (MongoService.shared, "Active Session")
        }

        throw MCPError.executionFailed("No MongoDB connection configured or found for '\(connectionQuery ?? "")'.")
    }

    private func checkWriteAllowed() async throws {
        let isReadOnly = await MainActor.run { GlobalSettings.shared.mcpServerReadOnly }
        if isReadOnly {
            throw MCPError.executionFailed("Operation blocked: MCP Server is in Read-Only mode. Disable Read-Only mode in MongoDesktop Settings to permit modifications.")
        }
    }

    // MARK: - Tool Implementations

    private func listConnections() async throws -> String {
        let connections = await MainActor.run {
            ConnectionStore.shared.connections.map { profile in
                [
                    "id": profile.id.uuidString,
                    "name": profile.name,
                    "host": profile.host,
                    "port": profile.port,
                    "database": profile.database,
                    "useSRV": profile.useSRV,
                    "useSSL": profile.useSSL,
                    "useSSHTunnel": profile.useSSHTunnel
                ] as [String: Any]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: connections, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func listDatabases(connection: String?) async throws -> String {
        let (service, connName) = try await resolveService(for: connection)
        let databases = try await service.listDatabases()
        let result: [String: Any] = [
            "connection": connName,
            "databases": databases
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func listCollections(connection: String?, database: String) async throws -> String {
        let (service, connName) = try await resolveService(for: connection)
        let infos = try await service.listCollectionInfos(database: database)
        let collectionList = infos.map { info in
            [
                "name": info.name,
                "isTimeSeries": info.isTimeSeries
            ] as [String: Any]
        }
        let result: [String: Any] = [
            "connection": connName,
            "database": database,
            "collections": collectionList
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func findDocuments(
        connection: String?,
        database: String,
        collection: String,
        filter: String,
        projection: String?,
        sort: String?,
        limit: Int,
        skip: Int
    ) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let filterDoc = try MongoQueryParsing.parseFilter(filter)
        let projectionDoc = try projection.flatMap { try MongoQueryParsing.parseQueryOption($0) }
        let sortDoc = try sort.flatMap { try MongoQueryParsing.parseQueryOption($0) }
        let clampedLimit = min(max(1, limit), 100)

        let docs = try await service.findDocuments(
            database: database,
            collection: collection,
            filter: filterDoc,
            sort: sortDoc,
            projection: projectionDoc,
            limit: clampedLimit,
            skip: skip
        )

        let jsonArray = "[" + docs.map { $0.toExtendedJSONString() }.joined(separator: ",\n") + "]"
        return jsonArray
    }

    private func countDocuments(connection: String?, database: String, collection: String, filter: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let filterDoc = try MongoQueryParsing.parseFilter(filter)
        let count = try await service.countDocuments(database: database, collection: collection, filter: filterDoc)
        return "{\"database\": \"\(database)\", \"collection\": \"\(collection)\", \"count\": \(count)}"
    }

    private func runAggregate(connection: String?, database: String, collection: String, pipeline: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let pipelineDocs = try MongoQueryParsing.parsePipeline(pipeline)
        let docs = try await service.runAggregate(database: database, collection: collection, pipeline: pipelineDocs)
        let jsonArray = "[" + docs.map { $0.toExtendedJSONString() }.joined(separator: ",\n") + "]"
        return jsonArray
    }

    private func explainQuery(connection: String?, database: String, collection: String, filter: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let filterDoc = try MongoQueryParsing.parseFilter(filter)
        let explanation = try await service.explainFind(database: database, collection: collection, filter: filterDoc)
        return explanation.toExtendedJSONString()
    }

    private func listIndexes(connection: String?, database: String, collection: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let indexes = try await service.listIndexes(database: database, collection: collection)
        return "[" + indexes.map { $0.toExtendedJSONString() }.joined(separator: ",\n") + "]"
    }

    private func getServerStatus(connection: String?) async throws -> String {
        let (service, connName) = try await resolveService(for: connection)
        let serverInfo = try await service.getServerInfo()
        let status = try await service.fetchServerStatus()
        let result: [String: Any] = [
            "connection": connName,
            "version": serverInfo.version,
            "hostURI": serverInfo.hostURI,
            "clusterMode": serverInfo.clusterMode,
            "databasesCount": serverInfo.databasesCount,
            "collectionsCount": serverInfo.collectionsCount,
            "status": status.toExtendedJSONString()
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func getDbStats(connection: String?, database: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let stats = try await service.fetchDbStats(database: database)
        return stats.toExtendedJSONString()
    }

    private func insertDocument(connection: String?, database: String, collection: String, documentJson: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let doc = try MongoQueryParsing.parseFilter(documentJson)
        try await service.insertDocument(database: database, collection: collection, document: doc)
        return "{\"status\": \"inserted\", \"document\": \(doc.toExtendedJSONString())}"
    }

    private func updateDocuments(connection: String?, database: String, collection: String, filterJson: String, updateJson: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let filterDoc = try MongoQueryParsing.parseFilter(filterJson)
        let updateDoc = try MongoQueryParsing.parseFilter(updateJson)
        let modifiedCount = try await service.updateDocuments(database: database, collection: collection, filter: filterDoc, update: updateDoc)
        return "{\"status\": \"updated\", \"modifiedCount\": \(modifiedCount)}"
    }

    private func deleteDocument(connection: String?, database: String, collection: String, filterJson: String) async throws -> String {
        let (service, _) = try await resolveService(for: connection)
        let filterDoc = try MongoQueryParsing.parseFilter(filterJson)
        try await service.deleteDocument(database: database, collection: collection, filter: filterDoc)
        return "{\"status\": \"deleted\"}"
    }
}
