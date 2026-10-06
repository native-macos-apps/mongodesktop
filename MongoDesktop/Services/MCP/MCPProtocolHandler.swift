import Foundation

// MARK: - MCP Errors

enum MCPError: LocalizedError {
    case parseError(String)
    case invalidRequest(String)
    case methodNotFound(String)
    case invalidParams(String)
    case internalError(String)
    case executionFailed(String)

    var code: Int {
        switch self {
        case .parseError: return -32700
        case .invalidRequest: return -32600
        case .methodNotFound: return -32601
        case .invalidParams: return -32602
        case .internalError: return -32603
        case .executionFailed: return -32000
        }
    }

    var errorDescription: String? {
        switch self {
        case .parseError(let m),
             .invalidRequest(let m),
             .methodNotFound(let m),
             .invalidParams(let m),
             .internalError(let m),
             .executionFailed(let m):
            return m
        }
    }
}

// MARK: - MCPProtocolHandler

final class MCPProtocolHandler: Sendable {
    static let shared = MCPProtocolHandler()

    private init() {}

    /// Processes an incoming JSON-RPC string, returning the response JSON string if appropriate.
    func handle(rawMessage: String) async -> String? {
        guard let data = rawMessage.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return makeErrorResponse(id: nil, error: MCPError.parseError("Could not parse JSON body."))
        }

        let id = json["id"] // Can be Int, String, or nil
        guard let method = json["method"] as? String else {
            return makeErrorResponse(id: id, error: MCPError.invalidRequest("Missing 'method' in JSON-RPC request."))
        }

        let params = json["params"] as? [String: Any] ?? [:]

        // Handle notifications (no id -> no response expected)
        if id == nil && method.starts(with: "notifications/") {
            return nil
        }

        do {
            let result = try await dispatch(method: method, params: params)
            return makeSuccessResponse(id: id, result: result)
        } catch let mcpErr as MCPError {
            return makeErrorResponse(id: id, error: mcpErr)
        } catch {
            return makeErrorResponse(id: id, error: MCPError.executionFailed(error.localizedDescription))
        }
    }

    // MARK: - Method Dispatch

    private func dispatch(method: String, params: [String: Any]) async throws -> Any {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["subscribe": false, "listChanged": false]
                ],
                "serverInfo": [
                    "name": "mongodesktop-mcp",
                    "version": "1.0.0"
                ]
            ]

        case "notifications/initialized":
            return [:]

        case "ping":
            return [:]

        case "tools/list":
            return ["tools": toolDefinitions]

        case "tools/call":
            guard let name = params["name"] as? String else {
                throw MCPError.invalidParams("Missing 'name' in tools/call request.")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let output = try await MCPToolExecutor.shared.executeTool(name: name, arguments: arguments)
                return [
                    "content": [
                        [
                            "type": "text",
                            "text": output
                        ]
                    ],
                    "isError": false
                ]
            } catch {
                return [
                    "content": [
                        [
                            "type": "text",
                            "text": "Error: \(error.localizedDescription)"
                        ]
                    ],
                    "isError": true
                ]
            }

        case "resources/list":
            return [
                "resources": [
                    [
                        "uri": "mongodb://connections",
                        "name": "MongoDesktop Connections",
                        "description": "List of all saved MongoDB connection profiles",
                        "mimeType": "application/json"
                    ]
                ]
            ]

        case "resources/read":
            guard let uri = params["uri"] as? String else {
                throw MCPError.invalidParams("Missing 'uri' in resources/read.")
            }
            if uri == "mongodb://connections" {
                let connectionsText = try await MCPToolExecutor.shared.executeTool(name: "mongodb_list_connections", arguments: [:])
                return [
                    "contents": [
                        [
                            "uri": uri,
                            "mimeType": "application/json",
                            "text": connectionsText
                        ]
                    ]
                ]
            }
            throw MCPError.invalidParams("Unknown resource URI: \(uri)")

        default:
            throw MCPError.methodNotFound("Method '\(method)' is not supported.")
        }
    }

    // MARK: - JSON-RPC Response Builders

    private func makeSuccessResponse(id: Any?, result: Any) -> String {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id { response["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed]) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Serialization failure\"}}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func makeErrorResponse(id: Any?, error: MCPError) -> String {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": error.code,
                "message": error.localizedDescription
            ]
        ]
        if let id { response["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.fragmentsAllowed]) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":\(error.code),\"message\":\"\(error.localizedDescription)\"}}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "mongodb_list_connections",
                "description": "List all saved MongoDB connection profiles configured in MongoDesktop.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:]
                ]
            ],
            [
                "name": "mongodb_list_databases",
                "description": "List all database names in a MongoDB connection.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": [
                            "type": "string",
                            "description": "Connection profile name or ID (optional, defaults to active connection or first profile)"
                        ]
                    ]
                ]
            ],
            [
                "name": "mongodb_list_collections",
                "description": "List all collections in a database, including time-series flags.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": [
                            "type": "string",
                            "description": "Connection profile name or ID (optional)"
                        ],
                        "database": [
                            "type": "string",
                            "description": "Database name"
                        ]
                    ],
                    "required": ["database"]
                ]
            ],
            [
                "name": "mongodb_find",
                "description": "Query documents from a MongoDB collection with optional filter, projection, sort, and pagination.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "filter": ["type": "string", "description": "JSON filter query (e.g. {\"status\": \"active\"})"],
                        "projection": ["type": "string", "description": "JSON projection (e.g. {\"name\": 1, \"_id\": 0})"],
                        "sort": ["type": "string", "description": "JSON sort specification (e.g. {\"createdAt\": -1})"],
                        "limit": ["type": "integer", "description": "Maximum number of documents to return (default 20, max 100)"],
                        "skip": ["type": "integer", "description": "Number of documents to skip (default 0)"]
                    ],
                    "required": ["database", "collection"]
                ]
            ],
            [
                "name": "mongodb_count",
                "description": "Count the number of documents in a collection matching an optional filter.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "filter": ["type": "string", "description": "JSON filter query (default {})"]
                    ],
                    "required": ["database", "collection"]
                ]
            ],
            [
                "name": "mongodb_aggregate",
                "description": "Execute an aggregation pipeline on a MongoDB collection.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "pipeline": ["type": "string", "description": "JSON array representing aggregation stages (e.g. [ { \"$match\": { ... } }, { \"$group\": { ... } } ])"]
                    ],
                    "required": ["database", "collection", "pipeline"]
                ]
            ],
            [
                "name": "mongodb_explain",
                "description": "Explain the query execution plan for a find query.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "filter": ["type": "string", "description": "JSON filter query (default {})"]
                    ],
                    "required": ["database", "collection"]
                ]
            ],
            [
                "name": "mongodb_list_indexes",
                "description": "List all indexes configured on a collection.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"]
                    ],
                    "required": ["database", "collection"]
                ]
            ],
            [
                "name": "mongodb_server_status",
                "description": "Retrieve MongoDB server version and runtime status metrics.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"]
                    ]
                ]
            ],
            [
                "name": "mongodb_db_stats",
                "description": "Retrieve database statistics including data size, storage size, and index counts.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"]
                    ],
                    "required": ["database"]
                ]
            ],
            [
                "name": "mongodb_insert_document",
                "description": "Insert a document into a collection (blocked if Read-Only mode is enabled in Settings).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "document": ["type": "string", "description": "JSON string of the document to insert"]
                    ],
                    "required": ["database", "collection", "document"]
                ]
            ],
            [
                "name": "mongodb_update_documents",
                "description": "Update documents in a collection matching a filter (blocked if Read-Only mode is enabled).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "filter": ["type": "string", "description": "JSON filter query"],
                        "update": ["type": "string", "description": "JSON update specification (e.g. {\"$set\": {\"status\": \"done\"}})"]
                    ],
                    "required": ["database", "collection", "filter", "update"]
                ]
            ],
            [
                "name": "mongodb_delete_document",
                "description": "Delete a document from a collection matching a filter (blocked if Read-Only mode is enabled).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": ["type": "string", "description": "Connection profile name or ID (optional)"],
                        "database": ["type": "string", "description": "Database name"],
                        "collection": ["type": "string", "description": "Collection name"],
                        "filter": ["type": "string", "description": "JSON filter query to match document for deletion"]
                    ],
                    "required": ["database", "collection", "filter"]
                ]
            ]
        ]
    }
}
