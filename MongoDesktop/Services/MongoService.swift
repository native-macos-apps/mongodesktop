import Foundation
import Darwin
import SwiftBSON

struct CollectionInfo {
    let name: String
    let isTimeSeries: Bool
}

actor MongoService {
    static let shared = MongoService()

    private var client: OpaquePointer?
    private var connectedURI: String?

    private static let initialized: Void = {
        // Prefer TCP for SRV lookups to avoid resolver/network paths that drop UDP DNS responses.
        setenv("MONGOC_EXPERIMENTAL_SRV_PREFER_TCP", "true", 0)
        mongoc_init()
#if DEBUG
        let version = String(cString: mongoc_get_version())
        print("Mongo C Driver Version (mongoc): \(version)")
#endif
    }()

    private func ensureInitialized() {
        _ = MongoService.initialized
    }

    func connect(uri: String) async throws {
        if connectedURI == uri, client != nil {
            return
        }

        try await disconnect()
        ensureInitialized()

        let newClient = try await createClient(uri: uri)

        do {
            try ping(client: newClient)
        } catch {
            mongoc_client_destroy(newClient)
            throw error
        }

        self.client = newClient
        self.connectedURI = uri
    }

    func testConnection(uri: String) async throws {
        ensureInitialized()
        let tempClient = try await createClient(uri: uri)
        defer { mongoc_client_destroy(tempClient) }
        try ping(client: tempClient)
    }

    func debugConnection(uri: String) async -> String {
        ensureInitialized()
        let redacted = redactedURI(uri)
        var lines: [String] = []
        lines.append("Mongo Connection Debug")
        lines.append("URI: \(redacted)")
        lines.append("isSRV: \(uri.lowercased().hasPrefix("mongodb+srv://"))")
        var error = bson_error_t()
        if let parsed = mongoc_uri_new_with_error(uri, &error) {
            mongoc_uri_destroy(parsed)
            lines.append("Parse URI: OK")
        } else {
            lines.append("Parse URI: FAILED")
            let msg = errorMessage(error)
            lines.append("Error: \(msg.isEmpty ? "(empty)" : msg)")
            lines.append("Domain: \(error.domain)  Code: \(error.code)")
        }
        // Try create client to surface any SRV resolution / option issues.
        var createError = bson_error_t()
        if let parsed = mongoc_uri_new_with_error(uri, &createError) {
            let client = mongoc_client_new_from_uri_with_error(parsed, &createError)
            if let client {
                mongoc_client_destroy(client)
                lines.append("Create Client: OK")
            } else {
                let msg = errorMessage(createError)
                lines.append("Create Client: FAILED")
                lines.append("Error: \(msg.isEmpty ? "(empty)" : msg)")
                lines.append("Domain: \(createError.domain)  Code: \(createError.code)")
            }
            mongoc_uri_destroy(parsed)
        }
        return lines.joined(separator: "\n")
    }

    func disconnect() async throws {
        if let client {
            mongoc_client_destroy(client)
            self.client = nil
        }
        connectedURI = nil
    }

    func listDatabases() async throws -> [String] {
        let client = try requireClient()
        var error = bson_error_t()
        guard let names = mongoc_client_get_database_names_with_opts(client, nil, &error) else {
            throw MongoServiceError.commandFailed(errorMessage(error))
        }
        defer { bson_strfreev(names) }

        var results: [String] = []
        var index = 0
        while let namePtr = names.advanced(by: index).pointee {
            results.append(String(cString: namePtr))
            index += 1
        }

        return results.sorted()
    }

    func listCollections(database: String) async throws -> [String] {
        let infos = try await listCollectionInfos(database: database)
        return infos.map(\.name)
    }

    func listCollectionInfos(database: String) async throws -> [CollectionInfo] {
        let client = try requireClient()
        let command: BSONDocument = [
            "listCollections": .int32(1)
        ]
        let reply = try runCommand(client: client, database: database, command: command)

        guard case .document(let cursor)? = reply["cursor"],
              case .array(let batch)? = cursor["firstBatch"] else {
            throw MongoServiceError.commandFailed("Unable to read collection metadata.")
        }

        var results: [CollectionInfo] = []
        results.reserveCapacity(batch.count)
        for item in batch {
            guard case .document(let doc) = item,
                  case .string(let name)? = doc["name"] else { continue }

            let isTimeSeriesByType: Bool
            if case .string(let type)? = doc["type"] {
                isTimeSeriesByType = type.caseInsensitiveCompare("timeseries") == .orderedSame
            } else {
                isTimeSeriesByType = false
            }

            let isTimeSeriesByOptions: Bool
            if case .document(let options)? = doc["options"] {
                isTimeSeriesByOptions = options["timeseries"] != nil
            } else {
                isTimeSeriesByOptions = false
            }

            results.append(
                CollectionInfo(
                    name: name,
                    isTimeSeries: isTimeSeriesByType || isTimeSeriesByOptions
                )
            )
        }

        return results.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func serverVersion() async throws -> String {
        let client = try requireClient()
        let reply = try runCommand(client: client, database: "admin", command: ["buildInfo": .int32(1)])
        if case let .string(version) = reply["version"] {
            return version
        }
        return "unknown"
    }

    func getServerInfo() async throws -> ServerInfo {
        let client = try requireClient()
        
        let helloReply = try? runCommand(client: client, database: "admin", command: ["hello": .int32(1)])
        var clusterMode = "Standalone"
        if let msg = helloReply?["msg"], case .string(let text) = msg, text == "isdbgrid" {
            clusterMode = "Sharded Cluster"
        } else if let setName = helloReply?["setName"], case .string(_) = setName {
            clusterMode = "Replica Set"
        }
        
        let version = (try? await serverVersion()) ?? "unknown"
        
        // Fetch databases list locally without async boundary inside a loop that calls actor, wait, we are inside the actor
        // Wait, listDatabases() returns an array, and this method is in the actor, so we can just call it
        let dbs = (try? await listDatabases()) ?? []
        let databasesCount = dbs.count
        
        var collectionsCount = 0
        for db in dbs {
            if let infos = try? await listCollectionInfos(database: db) {
                collectionsCount += infos.count
            }
        }
        
        let uri = connectedURI.map { redactedURI($0) } ?? "unknown"
        
        return ServerInfo(
            databasesCount: databasesCount,
            collectionsCount: collectionsCount,
            clusterMode: clusterMode,
            version: version,
            hostURI: uri
        )
    }

    func findDocuments(
        database: String,
        collection: String,
        filter: BSONDocument,
        sort: BSONDocument? = nil,
        projection: BSONDocument? = nil,
        limit: Int = 100,
        skip: Int = 0
    ) async throws -> [BSONDocument] {
        let client = try requireClient()
        guard let db = mongoc_client_get_database(client, database) else {
            throw MongoServiceError.commandFailed("Could not open database '\(database)'.")
        }
        defer { mongoc_database_destroy(db) }

        guard let coll = mongoc_database_get_collection(db, collection) else {
            throw MongoServiceError.commandFailed("Could not open collection '\(collection)'.")
        }
        defer { mongoc_collection_destroy(coll) }

        let filterJSON = filter.toCanonicalExtendedJSONString()
        let filterBson = try bsonFromJSON(filterJSON)
        defer { bson_destroy(filterBson) }

        var opts = bson_t()
        bson_init(&opts)
        bson_append_int64(&opts, "limit", -1, Int64(limit))
        bson_append_int64(&opts, "skip", -1, Int64(skip))

        var sortBson: UnsafeMutablePointer<bson_t>?
        var projectionBson: UnsafeMutablePointer<bson_t>?
        if let sort, !sort.isEmpty {
            let json = sort.toCanonicalExtendedJSONString()
            sortBson = try bsonFromJSON(json)
            bson_append_document(&opts, "sort", -1, sortBson)
        }
        if let projection, !projection.isEmpty {
            let json = projection.toCanonicalExtendedJSONString()
            projectionBson = try bsonFromJSON(json)
            bson_append_document(&opts, "projection", -1, projectionBson)
        }
        defer {
            if let sortBson { bson_destroy(sortBson) }
            if let projectionBson { bson_destroy(projectionBson) }
            bson_destroy(&opts)
        }

        guard let cursor = mongoc_collection_find_with_opts(coll, filterBson, &opts, nil) else {
            throw MongoServiceError.queryFailed("Could not create cursor.")
        }
        defer { mongoc_cursor_destroy(cursor) }

        var documents: [BSONDocument] = []
        var docPtr: UnsafePointer<bson_t>?
        while mongoc_cursor_next(cursor, &docPtr) {
            if let docPtr {
                let json = bsonToCanonicalJSON(docPtr)
                if let doc = try? BSONDocument(fromJSON: json) {
                    documents.append(doc)
                }
            }
        }

        var error = bson_error_t()
        if mongoc_cursor_error(cursor, &error) {
            throw MongoServiceError.queryFailed(errorMessage(error))
        }

        return documents
    }

    func runAggregate(
        database: String,
        collection: String,
        pipeline: [BSONDocument]
    ) async throws -> [BSONDocument] {
        let client = try requireClient()
        var command: BSONDocument = [
            "aggregate": .string(collection),
            "cursor": .document([:])
        ]
        
        let bsonPipeline = pipeline.map { BSON.document($0) }
        command["pipeline"] = .array(bsonPipeline)
        
        let reply = try runCommand(client: client, database: database, command: command)
        
        guard case .document(let cursor)? = reply["cursor"],
              case .array(let batch)? = cursor["firstBatch"] else {
            throw MongoServiceError.commandFailed("Unable to read aggregate cursor.")
        }
        
        var results: [BSONDocument] = []
        for item in batch {
            if case .document(let doc) = item {
                results.append(doc)
            }
        }
        return results
    }

    func listIndexes(
        database: String,
        collection: String
    ) async throws -> [BSONDocument] {
        let client = try requireClient()
        let command: BSONDocument = [
            "listIndexes": .string(collection)
        ]
        
        let reply = try runCommand(client: client, database: database, command: command)
        
        guard case .document(let cursor)? = reply["cursor"],
              case .array(let batch)? = cursor["firstBatch"] else {
            throw MongoServiceError.commandFailed("Unable to read indexes.")
        }
        
        var results: [BSONDocument] = []
        for item in batch {
            if case .document(let doc) = item {
                results.append(doc)
            }
        }
        return results
    }

    func getIndexStats(
        database: String,
        collection: String
    ) async throws -> [String: (size: Int64, usage: Int64)] {
        let client = try requireClient()
        var stats: [String: (size: Int64, usage: Int64)] = [:]
        
        // 1. Get index sizes using collStats command
        let collStatsCmd: BSONDocument = [
            "collStats": .string(collection)
        ]
        if let reply = try? runCommand(client: client, database: database, command: collStatsCmd),
           case .document(let indexSizes)? = reply["indexSizes"] {
            for (key, val) in indexSizes {
                let bytes: Int64
                switch val {
                case .int32(let i): bytes = Int64(i)
                case .int64(let i): bytes = i
                case .double(let d): bytes = Int64(d)
                default: bytes = 0
                }
                stats[key] = (size: bytes, usage: 0)
            }
        }
        
        // 2. Get index usage using $indexStats aggregate stage
        let indexStatsPipeline: [BSONDocument] = [
            ["$indexStats": .document([:])]
        ]
        if let results = try? await runAggregate(database: database, collection: collection, pipeline: indexStatsPipeline) {
            for doc in results {
                guard let name = doc["name"]?.stringValue else { continue }
                var usageCount: Int64 = 0
                if let accesses = doc["accesses"]?.documentValue,
                   let ops = accesses["ops"] {
                    switch ops {
                    case .int32(let i): usageCount = Int64(i)
                    case .int64(let i): usageCount = i
                    case .double(let d): usageCount = Int64(d)
                    default: break
                    }
                }
                let current = stats[name] ?? (size: 0, usage: 0)
                stats[name] = (size: current.size, usage: usageCount)
            }
        }
        
        return stats
    }



    private func ping(client: OpaquePointer) throws {
        var command = bson_t()
        bson_init(&command)
        bson_append_int32(&command, "ping", -1, 1)

        var reply = bson_t()
        bson_init(&reply)
        var error = bson_error_t()

        let ok = mongoc_client_command_simple(client, "admin", &command, nil, &reply, &error)
        bson_destroy(&command)
        bson_destroy(&reply)

        guard ok else {
            throw MongoServiceError.connectionFailed(errorMessage(error))
        }
    }

    private func runCommand(client: OpaquePointer, database: String, command: BSONDocument) throws -> BSONDocument {
        let json = command.toCanonicalExtendedJSONString()
        let commandBson = try bsonFromJSON(json)
        defer { bson_destroy(commandBson) }

        var reply = bson_t()
        bson_init(&reply)
        var error = bson_error_t()

        let ok = mongoc_client_command_simple(client, database, commandBson, nil, &reply, &error)
        guard ok else {
            bson_destroy(&reply)
            throw MongoServiceError.commandFailed(errorMessage(error))
        }

        let replyJSON = bsonToCanonicalJSON(&reply)
        bson_destroy(&reply)
        return try BSONDocument(fromJSON: replyJSON)
    }

    private func requireClient() throws -> OpaquePointer {
        guard let client else { throw MongoServiceError.notConnected }
        return client
    }

    private func createClient(uri: String) async throws -> OpaquePointer {
        var error = bson_error_t()
        guard let parsed = mongoc_uri_new_with_error(uri, &error) else {
            let msg = errorMessage(error)
            let detail = msg.isEmpty ? "Failed to parse URI." : "Failed to parse URI: \(msg)"
            throw MongoServiceError.connectionFailed("\(detail)\nURI: \(redactedURI(uri))\nDomain: \(error.domain)  Code: \(error.code)")
        }
        defer { mongoc_uri_destroy(parsed) }

        var createError = bson_error_t()
        guard let client = mongoc_client_new_from_uri_with_error(parsed, &createError) else {
            let msg = errorMessage(createError)
            let detail = msg.isEmpty ? "Failed to initialize Mongo client." : "Failed to initialize Mongo client: \(msg)"
            throw MongoServiceError.connectionFailed("\(detail)\nURI: \(redactedURI(uri))\nDomain: \(createError.domain)  Code: \(createError.code)")
        }
        return client
    }

    private func bsonFromJSON(_ json: String) throws -> UnsafeMutablePointer<bson_t> {
        var error = bson_error_t()
        let result = json.withCString { ptr in
            bson_new_from_json(ptr, -1, &error)
        }
        guard let bson = result else {
            throw MongoServiceError.bsonError(errorMessage(error))
        }
        return bson
    }

    private func bsonToCanonicalJSON(_ bson: UnsafePointer<bson_t>) -> String {
        var length: UInt = 0
        guard let jsonPtr = bson_as_canonical_extended_json(bson, &length) else { return "{}" }
        let json = String(cString: jsonPtr)
        bson_free(jsonPtr)
        return json
    }

    private func errorMessage(_ error: bson_error_t) -> String {
        var mutableError = error
        return withUnsafePointer(to: &mutableError.message) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private func redactedURI(_ uri: String) -> String {
        guard let schemeRange = uri.range(of: "://") else { return uri }
        let scheme = uri[..<schemeRange.upperBound]
        let rest = uri[schemeRange.upperBound...]
        guard let atIndex = rest.firstIndex(of: "@") else { return uri }
        let userInfo = rest[..<atIndex]
        let hostAndPath = rest[atIndex...]
        if let colonIndex = userInfo.firstIndex(of: ":") {
            let user = userInfo[..<colonIndex]
            return "\(scheme)\(user):***\(hostAndPath)"
        }
        return "\(scheme)\(userInfo)\(hostAndPath)"
    }
}

enum MongoServiceError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case commandFailed(String)
    case queryFailed(String)
    case bsonError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MongoDB."
        case .connectionFailed(let message):
            return message.isEmpty ? "MongoDB connection failed." : message
        case .commandFailed(let message):
            return message.isEmpty ? "MongoDB command failed." : message
        case .queryFailed(let message):
            return message.isEmpty ? "MongoDB query failed." : message
        case .bsonError(let message):
            return message.isEmpty ? "Invalid BSON data." : message
        }
    }
}
