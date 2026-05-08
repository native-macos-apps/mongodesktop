import Foundation
import NIOCore
import NIOPosix
@preconcurrency import NIOSSH
import CryptoKit

// MARK: - SSHTunnelError

enum SSHTunnelError: LocalizedError {
    case configInvalid(String)
    case connectionFailed(String)
    case authenticationFailed(String)
    case timeout(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .configInvalid(let m):      return "SSH config invalid: \(m)"
        case .connectionFailed(let m):    return "SSH connection failed: \(m)"
        case .authenticationFailed(let m): return "SSH authentication failed: \(m)"
        case .timeout(let m):            return "SSH timed out: \(m)"
        case .launchFailed(let m):       return "Failed to launch SOCKS5: \(m)"
        }
    }
}

// MARK: - SSHTunnelService

actor SSHTunnelService {
    static let shared = SSHTunnelService()
    private init() {}

    private var group: MultiThreadedEventLoopGroup?
    private var sshChannel: Channel?
    private var socksServerChannel: Channel?

    // MARK: - Public API

    func validateKeyAccess(config: SSHTunnelConfig) throws {
        guard config.authMode == .privateKey else { return }
        let rawPath = config.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return }

        let expandedPath = resolvePath(rawPath)
        if !FileManager.default.fileExists(atPath: expandedPath) {
            throw SSHTunnelError.configInvalid("Private key file not found: \(expandedPath)")
        }
    }

    func startSOCKS5Proxy(config: SSHTunnelConfig) async throws -> Int {
        await stopTunnel()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        do {
            // 1. Connect and Authenticate SSH
            let sshChannel = try await connectSSH(config: config, on: group)
            self.sshChannel = sshChannel

            // 2. Start local SOCKS5 server that bridges to SSH
            let localPort = try await startSocks5Server(sshChannel: sshChannel, on: group)
            return localPort
        } catch {
            await stopTunnel()
            throw error
        }
    }

    func stopTunnel() async {
        try? await socksServerChannel?.close()
        socksServerChannel = nil
        try? await sshChannel?.close()
        sshChannel = nil
        try? await group?.shutdownGracefully()
        group = nil
    }

    // MARK: - Internal Logic

    private func connectSSH(config: SSHTunnelConfig, on group: EventLoopGroup) async throws -> Channel {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                Self.configureSSHClientPipeline(on: channel, config: config)
            }

        do {
            let channel = try await bootstrap.connect(host: config.sshHost, port: config.sshPort).get()
            // Wait for auth success event
            try await channel.pipeline.handler(type: SSHAuthEventTracker.self).get().authenticated.futureResult.get()
            return channel
        } catch {
            throw SSHTunnelError.connectionFailed(error.localizedDescription)
        }
    }

    @preconcurrency
    private static func configureSSHClientPipeline(on channel: Channel, config: SSHTunnelConfig) -> EventLoopFuture<Void> {
        let clientConfig = SSHClientConfiguration(
            userAuthDelegate: SSHAuthenticator(config: config),
            serverAuthDelegate: SSHAcceptAllServerDelegate()
        )

        return addSSHClientHandlerPreconcurrency(
            role: .client(clientConfig),
            allocator: channel.allocator,
            to: channel.pipeline
        ).flatMap {
            channel.pipeline.addHandler(SSHAuthEventTracker(eventLoop: channel.eventLoop))
        }
    }

    @preconcurrency
    private static func addSSHClientHandlerPreconcurrency(
        role: SSHConnectionRole,
        allocator: ByteBufferAllocator,
        to pipeline: ChannelPipeline
    ) -> EventLoopFuture<Void> {
        do {
            let handler = NIOSSHHandler(
                role: role,
                allocator: allocator,
                inboundChildChannelInitializer: nil
            )
            try pipeline.syncOperations.addHandler(handler)
            return pipeline.eventLoop.makeSucceededFuture(())
        } catch {
            return pipeline.eventLoop.makeFailedFuture(error)
        }
    }

    private func startSocks5Server(sshChannel: Channel, on group: EventLoopGroup) async throws -> Int {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(SOCKS5Handler(sshChannel: sshChannel))
            }

        let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        self.socksServerChannel = serverChannel
        
        return serverChannel.localAddress?.port ?? 0
    }

    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst(1)
        }
        return path
    }

    /// Helper to load private keys from PEM/OpenSSH format
    fileprivate static func loadPrivateKey(from pemString: String) throws -> NIOSSHPrivateKey {
        let lines = pemString.components(separatedBy: .newlines)
        let base64Content = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }.joined()
        guard let data = Data(base64Encoded: base64Content) else {
            throw SSHTunnelError.configInvalid("Invalid private key format (Base64 decode failed)")
        }

        if pemString.contains("BEGIN OPENSSH PRIVATE KEY") {
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeContiguousBytes(data)
            return try parseOpenSSHPrivateKey(buffer: &buffer)
        } else if pemString.contains("BEGIN EC PRIVATE KEY") || pemString.contains("BEGIN PRIVATE KEY") {
            // Try different representations
            if let key = try? P256.Signing.PrivateKey(derRepresentation: data) {
                return NIOSSHPrivateKey(p256Key: key)
            }
            if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
                return NIOSSHPrivateKey(ed25519Key: key)
            }
        }
        
        throw SSHTunnelError.configInvalid("Unsupported or encrypted private key format. Please use an unencrypted Ed25519 or P256 key.")
    }

    private static func parseOpenSSHPrivateKey(buffer: inout ByteBuffer) throws -> NIOSSHPrivateKey {
        func readNext() -> ByteBuffer? {
            guard let len = buffer.readInteger(as: UInt32.self) else { return nil }
            return buffer.readSlice(length: Int(len))
        }

        // Magic header "openssh-key-v1\0"
        guard let header = buffer.readBytes(length: 15),
              header == Array("openssh-key-v1\0".utf8) else {
            throw SSHTunnelError.configInvalid("Invalid OpenSSH key header")
        }

        // Cipher name, KDF name, KDF options, Number of keys
        _ = readNext() // cipher (none)
        _ = readNext() // kdf (none)
        _ = readNext() // kdfopts
        guard let numKeys = buffer.readInteger(as: UInt32.self), numKeys >= 1 else {
            throw SSHTunnelError.configInvalid("Could not read key count")
        }
        
        // Public key (skip)
        _ = readNext()
        
        // Private key block
        guard var privBlock = readNext() else { throw SSHTunnelError.configInvalid("Could not read private key block") }
        
        // The block contains: check1, check2, keytype, pubkey, privkey, comment, padding
        func readBlockNext() -> ByteBuffer? {
            guard let len = privBlock.readInteger(as: UInt32.self) else { return nil }
            return privBlock.readSlice(length: Int(len))
        }

        _ = privBlock.readInteger(as: UInt32.self) // skip check1
        _ = privBlock.readInteger(as: UInt32.self) // skip check2
        
        guard let typeData = readBlockNext(),
              let type = typeData.getString(at: 0, length: typeData.readableBytes) else {
            throw SSHTunnelError.configInvalid("Could not read key type")
        }
        
        if type == "ssh-ed25519" {
            _ = readBlockNext() // skip pubkey
            guard let privKeyData = readBlockNext(),
                  let seed = privKeyData.getBytes(at: 0, length: 32) else {
                throw SSHTunnelError.configInvalid("Could not read Ed25519 key")
            }
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return NIOSSHPrivateKey(ed25519Key: key)
        } else if type == "ecdsa-sha2-nistp256" {
            _ = readBlockNext() // curve name
            _ = readBlockNext() // pubkey
            guard let privKeyData = readBlockNext(),
                  let rawKey = privKeyData.getBytes(at: 0, length: privKeyData.readableBytes) else {
                throw SSHTunnelError.configInvalid("Could not read P256 key")
            }
            let key = try P256.Signing.PrivateKey(rawRepresentation: rawKey)
            return NIOSSHPrivateKey(p256Key: key)
        }
        throw SSHTunnelError.configInvalid("Unsupported native key type: \(type)")
    }
}

// MARK: - SSH Handlers

private final class SSHAcceptAllServerDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

private final class SSHAuthEventTracker: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let authenticated: EventLoopPromise<Void>

    init(eventLoop: EventLoop) {
        self.authenticated = eventLoop.makePromise(of: Void.self)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            authenticated.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        authenticated.fail(error)
        context.close(promise: nil)
    }
}

private struct SSHAuthenticator: NIOSSHClientUserAuthenticationDelegate {
    let config: SSHTunnelConfig

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch config.authMode {
        case .password:
            if availableMethods.contains(.password) {
                let offer = NIOSSHUserAuthenticationOffer(
                    username: config.sshUser,
                    serviceName: "ssh-connection",
                    offer: .password(.init(password: config.password))
                )
                nextChallengePromise.succeed(offer)
            } else {
                nextChallengePromise.fail(SSHTunnelError.authenticationFailed("Server does not support password authentication"))
            }
        case .privateKey:
            if availableMethods.contains(.publicKey) {
                let path = config.privateKeyPath.hasPrefix("~/") ? FileManager.default.homeDirectoryForCurrentUser.path + config.privateKeyPath.dropFirst(1) : config.privateKeyPath
                
                do {
                    let pemString = try String(contentsOfFile: path, encoding: .utf8)
                    let privateKey = try SSHTunnelService.loadPrivateKey(from: pemString)
                    
                    let offer = NIOSSHUserAuthenticationOffer(
                        username: config.sshUser,
                        serviceName: "ssh-connection",
                        offer: .privateKey(.init(privateKey: privateKey))
                    )
                    nextChallengePromise.succeed(offer)
                } catch {
                    nextChallengePromise.fail(error)
                }
            } else {
                nextChallengePromise.fail(SSHTunnelError.authenticationFailed("Server does not support public key authentication"))
            }
        }
    }
}

// MARK: - SOCKS5 Handler

private final class SOCKS5Handler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    enum State { case handshake, request, connecting, connected }
    private var state: State = .handshake
    private let sshChannel: Channel
    private var remoteChannel: Channel?
    private var pendingData: ByteBuffer?

    init(sshChannel: Channel) { self.sshChannel = sshChannel }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)

        switch state {
        case .handshake:
            var buffer = buffer
            guard buffer.readInteger(as: UInt8.self) == 0x05 else {
                context.close(promise: nil)
                return
            }
            // Skip methods
            let _ = buffer.readInteger(as: UInt8.self)
            
            var response = context.channel.allocator.buffer(capacity: 2)
            response.writeBytes([0x05, 0x00])
            context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)
            state = .request

        case .request:
            var buffer = buffer
            guard buffer.readInteger(as: UInt8.self) == 0x05 else { return } // ver
            let cmd = buffer.readInteger(as: UInt8.self)
            _ = buffer.readInteger(as: UInt8.self) // rsv
            let atyp = buffer.readInteger(as: UInt8.self)

            guard cmd == 0x01 else { // Connect only
                context.close(promise: nil)
                return
            }

            var host = ""
            if atyp == 0x01 { // IPv4
                guard let b1 = buffer.readInteger(as: UInt8.self),
                      let b2 = buffer.readInteger(as: UInt8.self),
                      let b3 = buffer.readInteger(as: UInt8.self),
                      let b4 = buffer.readInteger(as: UInt8.self) else { return }
                host = "\(b1).\(b2).\(b3).\(b4)"
            } else if atyp == 0x03 { // Domain
                guard let len = buffer.readInteger(as: UInt8.self),
                      let d = buffer.readString(length: Int(len)) else { return }
                host = d
            } else {
                context.close(promise: nil)
                return
            }
            
            guard let port = buffer.readInteger(as: UInt16.self) else { return }
            
            if buffer.readableBytes > 0 {
                self.pendingData = buffer
            }

            state = .connecting
            let promise = sshChannel.eventLoop.makePromise(of: Channel.self)
            let localChannel = context.channel
            let originatorAddress = context.localAddress!
            
            sshChannel.pipeline.handler(type: NIOSSHHandler.self).whenSuccess { handler in
                print("[SOCKS5] Requesting directTCPIP to \(host):\(port)")
                handler.createChannel(promise, channelType: .directTCPIP(.init(targetHost: host, targetPort: Int(port), originatorAddress: originatorAddress))) { channel, _ in
                    print("[SOCKS5] directTCPIP channel created successfully")
                    self.remoteChannel = channel
                    return channel.pipeline.addHandler(SSHToLocalBridge(localChannel: localChannel))
                }
            }
            
            promise.futureResult.whenSuccess { channel in
                localChannel.eventLoop.execute {
                    print("[SOCKS5] directTCPIP channel active, sending success to client")
                    self.state = .connected
                    var res = localChannel.allocator.buffer(capacity: 10)
                    res.writeBytes([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                    localChannel.writeAndFlush(res, promise: nil)
                    
                    // Forward any pending data
                    if let pending = self.pendingData {
                        print("[SOCKS5] Forwarding \(pending.readableBytes) bytes of pending data to SSH")
                        let sshData = SSHChannelData(type: .channel, data: .byteBuffer(pending))
                        channel.writeAndFlush(sshData, promise: nil)
                        self.pendingData = nil
                    }
                }
            }
            
            promise.futureResult.whenFailure { error in
                localChannel.eventLoop.execute {
                    print("[SOCKS5] directTCPIP channel failed: \(error)")
                    var res = localChannel.allocator.buffer(capacity: 10)
                    res.writeBytes([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                    localChannel.writeAndFlush(res, promise: nil)
                    localChannel.close(promise: nil)
                }
            }
            
        case .connecting:
            // Buffer data while connecting
            var buffer = buffer
            if pendingData == nil {
                pendingData = buffer
            } else {
                pendingData!.writeBuffer(&buffer)
            }
            
        case .connected:
            // Log payload
            print("[SOCKS5] Forwarding \(buffer.readableBytes) bytes to SSH")
            let sshData = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
            remoteChannel?.writeAndFlush(sshData, promise: nil)
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        print("[SOCKS5] Local channel inactive")
        remoteChannel?.close(promise: nil)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SOCKS5] Error: \(error)")
        context.close(promise: nil)
    }
}

private final class SSHToLocalBridge: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    private let localChannel: Channel

    init(localChannel: Channel) { self.localChannel = localChannel }

    func channelActive(context: ChannelHandlerContext) {
        context.read()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = self.unwrapInboundIn(data)
        if case .byteBuffer(let buffer) = sshData.data {
            print("[SSHBridge] Received \(buffer.readableBytes) bytes from SSH")
            localChannel.writeAndFlush(buffer, promise: nil)
        }
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.read()
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        print("[SSHBridge] SSH channel inactive")
        localChannel.close(promise: nil)
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[SSHBridge] Error: \(error)")
        localChannel.close(promise: nil)
    }
}
