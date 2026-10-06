import Foundation
import Network

// MARK: - MCPServerStatus

enum MCPServerStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case error(String)
}

// MARK: - MCPServer

final class MCPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mongodesktop.mcp.server", qos: .userInitiated)
    private var listener: NWListener?
    private var activeSSESessions: [String: NWConnection] = [:]
    private let sessionsLock = NSLock()
    private var keepAliveTimer: DispatchSourceTimer?
    private var isTransitioning = false

    private(set) var port: Int
    private(set) var status: MCPServerStatus = .stopped {
        didSet {
            onStatusChange?(status)
        }
    }

    var onStatusChange: ((MCPServerStatus) -> Void)?
    var onClientCountChange: ((Int) -> Void)?

    init(port: Int = 27123) {
        self.port = port
    }

    func start(port: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.port = port
            self.startInternal(targetPort: port, retryCount: 0)
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.stopInternal(completion: completion)
        }
    }

    // MARK: - Internal Lifecycle

    private func startInternal(targetPort: Int, retryCount: Int) {
        // If already running on the target port, do nothing
        if case .running(let currentPort) = status, currentPort == targetPort, listener != nil {
            return
        }

        // If there is an existing listener, stop it cleanly first and wait for cancellation
        if listener != nil {
            stopInternal { [weak self] in
                self?.startInternal(targetPort: targetPort, retryCount: retryCount)
            }
            return
        }

        status = .starting

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(targetPort)) else {
            status = .error("Invalid port: \(targetPort)")
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: nwPort)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                self.queue.async {
                    switch newState {
                    case .ready:
                        self.status = .running(port: targetPort)
                        self.startKeepAlive()

                    case .failed(let error):
                        let isAddrInUse: Bool = {
                            if case .posix(let code) = error, code == .EADDRINUSE { return true }
                            let desc = error.localizedDescription
                            return desc.contains("48") || desc.contains("Address already in use")
                        }()

                        if isAddrInUse && retryCount < 4 {
                            // Kernel port release delay (TIME_WAIT): retry after short backoff
                            self.stopInternal {
                                self.queue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                                    self?.startInternal(targetPort: targetPort, retryCount: retryCount + 1)
                                }
                            }
                        } else {
                            self.status = .error(error.localizedDescription)
                            self.stopInternal()
                        }

                    case .cancelled:
                        self.status = .stopped

                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
        } catch {
            status = .error("Failed to bind port \(targetPort): \(error.localizedDescription)")
        }
    }

    private func stopInternal(completion: (() -> Void)? = nil) {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil

        sessionsLock.lock()
        for (_, conn) in activeSSESessions {
            conn.cancel()
        }
        activeSSESessions.removeAll()
        sessionsLock.unlock()

        notifyClientCount()

        guard let currentListener = self.listener else {
            self.status = .stopped
            completion?()
            return
        }

        self.listener = nil
        currentListener.newConnectionHandler = nil

        currentListener.stateUpdateHandler = { [weak self] state in
            if state == .cancelled {
                self?.queue.async {
                    self?.status = .stopped
                    completion?()
                }
            }
        }
        currentListener.cancel()
    }

    private func startKeepAlive() {
        keepAliveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.sendKeepAliveToAll()
        }
        timer.resume()
        keepAliveTimer = timer
    }

    private func sendKeepAliveToAll() {
        sessionsLock.lock()
        let sessions = activeSSESessions
        sessionsLock.unlock()

        let pingData = ": keepalive\r\n\r\n".data(using: .utf8)!
        for (id, conn) in sessions {
            conn.send(content: pingData, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.removeSession(id: id)
                }
            })
        }
    }

    private func removeSession(id: String) {
        sessionsLock.lock()
        if let conn = activeSSESessions.removeValue(forKey: id) {
            conn.cancel()
        }
        sessionsLock.unlock()
        notifyClientCount()
    }

    private func notifyClientCount() {
        sessionsLock.lock()
        let count = activeSSESessions.count
        sessionsLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChange?(count)
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection, accumulatedData: Data())
    }

    private func readHTTPRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                connection.cancel()
                return
            }

            var buffer = accumulatedData
            if let content {
                buffer.append(content)
            }

            // Check if we have complete HTTP headers
            guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.readHTTPRequest(connection: connection, accumulatedData: buffer)
                }
                return
            }

            let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
            let bodyData = buffer.subdata(in: headerEndRange.upperBound..<buffer.count)

            guard let headerString = String(data: headerData, encoding: .utf8) else {
                self.sendHTTPResponse(connection: connection, status: 400, body: "Bad Request", closeAfter: true)
                return
            }

            let lines = headerString.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                self.sendHTTPResponse(connection: connection, status: 400, body: "Bad Request", closeAfter: true)
                return
            }

            let requestParts = requestLine.split(separator: " ")
            guard requestParts.count >= 2 else {
                self.sendHTTPResponse(connection: connection, status: 400, body: "Bad Request", closeAfter: true)
                return
            }

            let method = String(requestParts[0]).uppercased()
            let rawPath = String(requestParts[1])

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let colon = line.firstIndex(of: ":") {
                    let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }

            let contentLength = Int(headers["content-length"] ?? "") ?? 0

            // If body is not completely received yet, keep reading
            if bodyData.count < contentLength {
                if isComplete {
                    self.sendHTTPResponse(connection: connection, status: 400, body: "Incomplete Body", closeAfter: true)
                } else {
                    self.readHTTPRequest(connection: connection, accumulatedData: buffer)
                }
                return
            }

            let finalBody = String(data: bodyData.subdata(in: 0..<contentLength), encoding: .utf8) ?? ""
            self.routeRequest(method: method, path: rawPath, headers: headers, body: finalBody, connection: connection)
        }
    }

    // MARK: - Routing

    private func routeRequest(
        method: String,
        path: String,
        headers: [String: String],
        body: String,
        connection: NWConnection
    ) {
        let (pathname, queryString) = parsePath(path)

        // 1. CORS Preflight
        if method == "OPTIONS" {
            sendCORSResponse(connection: connection)
            return
        }

        // 2. Health Check
        if (method == "GET" && (pathname == "/health" || pathname == "/")) {
            let json = "{\"status\":\"ok\",\"server\":\"MongoDesktop MCP Server\",\"version\":\"1.0.0\"}\n"
            sendHTTPResponse(connection: connection, status: 200, contentType: "application/json", body: json, closeAfter: true)
            return
        }

        // 3. SSE Stream Connection: GET /sse
        if method == "GET" && pathname == "/sse" {
            handleSSEConnection(connection: connection)
            return
        }

        // 4. MCP Message over SSE: POST /message?sessionId=...
        if method == "POST" && pathname == "/message" {
            let queryParams = parseQuery(queryString)
            guard let sessionId = queryParams["sessionId"], !sessionId.isEmpty else {
                sendHTTPResponse(connection: connection, status: 400, body: "Missing sessionId parameter", closeAfter: true)
                return
            }

            // Acknowledge the HTTP POST immediately (202 Accepted)
            sendHTTPResponse(connection: connection, status: 202, body: "", closeAfter: true)

            // Dispatch message asynchronously and push response via SSE
            Task { [weak self] in
                guard let self else { return }
                if let responseJSON = await MCPProtocolHandler.shared.handle(rawMessage: body) {
                    self.sendSSEEvent(sessionId: sessionId, event: "message", data: responseJSON)
                }
            }
            return
        }

        // 5. Direct Streamable HTTP / JSON-RPC: POST /mcp or POST /rpc
        if method == "POST" && (pathname == "/mcp" || pathname == "/rpc") {
            Task { [weak self] in
                guard let self else { return }
                let responseJSON = await MCPProtocolHandler.shared.handle(rawMessage: body) ?? "{}"
                self.sendHTTPResponse(connection: connection, status: 200, contentType: "application/json", body: responseJSON, closeAfter: true)
            }
            return
        }

        // 404 Not Found
        sendHTTPResponse(connection: connection, status: 404, body: "Not Found", closeAfter: true)
    }

    // MARK: - SSE Handshake & Event Dispatch

    private func handleSSEConnection(connection: NWConnection) {
        let sessionId = UUID().uuidString

        let sseHeaders = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "\r\n"
        ].joined(separator: "\r\n")

        guard let headerData = sseHeaders.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            self.sessionsLock.lock()
            self.activeSSESessions[sessionId] = connection
            self.sessionsLock.unlock()

            self.notifyClientCount()

            // Send initial endpoint event as required by MCP spec
            let endpointEvent = "event: endpoint\r\ndata: /message?sessionId=\(sessionId)\r\n\r\n"
            if let data = endpointEvent.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in })
            }

            // Monitor connection termination
            self.monitorSSEClient(connection: connection, sessionId: sessionId)
        })
    }

    private func monitorSSEClient(connection: NWConnection, sessionId: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.removeSession(id: sessionId)
            } else {
                self.monitorSSEClient(connection: connection, sessionId: sessionId)
            }
        }
    }

    func sendSSEEvent(sessionId: String, event: String, data: String) {
        sessionsLock.lock()
        let connection = activeSSESessions[sessionId]
        sessionsLock.unlock()

        guard let connection else { return }

        // Sanitize multi-line data into SSE format
        let lines = data.components(separatedBy: "\n")
        let formattedData = lines.map { "data: \($0)" }.joined(separator: "\r\n")
        let message = "event: \(event)\r\n\(formattedData)\r\n\r\n"

        if let msgData = message.data(using: .utf8) {
            connection.send(content: msgData, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.removeSession(id: sessionId)
                }
            })
        }
    }

    // MARK: - HTTP Helpers

    private func sendCORSResponse(connection: NWConnection) {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization, Accept",
            "Content-Length: 0",
            "\r\n"
        ].joined(separator: "\r\n")

        if let data = headers.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func sendHTTPResponse(
        connection: NWConnection,
        status: Int,
        contentType: String = "text/plain; charset=utf-8",
        body: String,
        closeAfter: Bool
    ) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let statusText = status == 200 ? "OK" : (status == 202 ? "Accepted" : (status == 404 ? "Not Found" : "Error"))
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: \(closeAfter ? "close" : "keep-alive")",
            "\r\n"
        ].joined(separator: "\r\n")

        var fullData = headers.data(using: .utf8) ?? Data()
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            if closeAfter {
                connection.cancel()
            }
        })
    }

    private func parsePath(_ path: String) -> (pathname: String, query: String) {
        if let queryIndex = path.firstIndex(of: "?") {
            let pathname = String(path[..<queryIndex])
            let query = String(path[path.index(after: queryIndex)...])
            return (pathname, query)
        }
        return (path, "")
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[key] = value
            }
        }
        return result
    }
}
