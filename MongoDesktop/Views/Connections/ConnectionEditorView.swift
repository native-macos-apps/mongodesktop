import SwiftUI
import AppKit

// MARK: - EditorMode

enum EditorMode: Identifiable {
    case create
    case edit(UUID)
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let id): return "edit-\(id.uuidString)"
        }
    }
}

// MARK: - ConnectionDraft

struct ConnectionDraft {
    var name: String = ""
    var host: String = "localhost"
    var port: String = "27017"
    var useSRV: Bool = false
    var useSSL: Bool = false
    var username: String = ""
    var password: String = ""
    var database: String = ""
    var authDatabase: String = ""
    var useSSHTunnel: Bool = false
    var sshHost: String = ""
    var sshPort: String = "22"
    var sshUser: String = ""
    var sshAuthMode: SSHTunnelConfig.SSHAuthMode = .password
    var sshPassword: String = ""
    var sshPrivateKeyPath: String = ""
    var sshPrivateKeyPassphrase: String = ""

    init() {}

    init(from connection: ConnectionProfile) {
        name = connection.name
        host = connection.host
        port = String(connection.port)
        username = connection.username
        password = connection.password
        database = connection.database
        authDatabase = connection.authDatabase
        useSRV = connection.useSRV
        useSSL = connection.useSSL
        useSSHTunnel = connection.useSSHTunnel
        let ssh = connection.sshTunnel
        sshHost = ssh.sshHost
        sshPort = String(ssh.sshPort)
        sshUser = ssh.sshUser
        sshAuthMode = ssh.authMode
        sshPassword = ssh.password
        sshPrivateKeyPath = ssh.privateKeyPath
        sshPrivateKeyPassphrase = ssh.privateKeyPassphrase
    }

    init(fromURI uri: String) {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("mongodb+srv://") { useSRV = true }
        if trimmed.contains("ssl=true") || trimmed.contains("tls=true") { useSSL = true }
        var httpURI = trimmed
        if httpURI.hasPrefix("mongodb+srv://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb+srv://".count)
        } else if httpURI.hasPrefix("mongodb://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb://".count)
        }
        guard let components = URLComponents(string: httpURI) else { return }
        if let user = components.user, !user.isEmpty { username = user }
        if let pass = components.password, !pass.isEmpty { password = pass }
        if let h = components.host, !h.isEmpty { host = h }
        if let p = components.port { port = String(p) } else if useSRV { port = "" }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty { database = path }
        if let queryItems = components.queryItems {
            for item in queryItems {
                if item.name == "authSource", let val = item.value, !val.isEmpty { authDatabase = val }
            }
        }
        name = host
    }

    func build(id: UUID = UUID()) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: name.isEmpty ? host : name,
            host: host.isEmpty ? "localhost" : host,
            port: Int(port) ?? 27017,
            username: username,
            password: password,
            database: database,
            authDatabase: authDatabase,
            useSRV: useSRV,
            useSSL: useSSL,
            useSSHTunnel: useSSHTunnel,
            sshTunnel: SSHTunnelConfig(
                sshHost: sshHost,
                sshPort: Int(sshPort) ?? 22,
                sshUser: sshUser,
                authMode: sshAuthMode,
                password: sshPassword,
                privateKeyPath: sshPrivateKeyPath,
                privateKeyPassphrase: sshPrivateKeyPassphrase
            )
        )
    }
}

// MARK: - ConnectionEditorView

struct ConnectionEditorView: View {
    let mode: EditorMode
    @Binding var draft: ConnectionDraft
    let onSave: (EditorMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isTestingConnection = false
    @State private var showTestDebug = false
    @State private var testDebugText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    generalSection
                    sectionDivider
                    authSection
                    sectionDivider
                    sshSection
                }
                .padding(.vertical, 4)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 480, height: 540)
        .background(.regularMaterial)
        .sheet(isPresented: $showTestDebug) {
            DebugTextSheet(text: testDebugText)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.38, saturation: 0.65, brightness: 0.68),
                                 Color(hue: 0.5, saturation: 0.6, brightness: 0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .green.opacity(0.3), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(mode.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Text("Configure your MongoDB connection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Connection name
            field("Name") {
                TextField("e.g. Production DB", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            // Host + Port inline
            HStack(spacing: 10) {
                field("Host") {
                    TextField("localhost", text: $draft.host)
                        .textFieldStyle(.roundedBorder)
                }
                field("Port") {
                    TextField("27017", text: $draft.port)
                        .textFieldStyle(.roundedBorder)
                        .disabled(draft.useSRV)
                        .opacity(draft.useSRV ? 0.4 : 1)
                }
                .frame(width: 80)
            }

            // Toggles
            HStack(spacing: 20) {
                Toggle("Use SRV", isOn: $draft.useSRV)
                    .onChange(of: draft.useSRV) { _, v in draft.port = v ? "" : "27017" }
                Toggle("TLS / SSL", isOn: $draft.useSSL)
            }
            .font(.callout)
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Auth Section

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Authentication", icon: "key.fill")

            HStack(spacing: 10) {
                field("Username") {
                    TextField("Optional", text: $draft.username)
                        .textFieldStyle(.roundedBorder)
                }
                field("Password") {
                    SecureField("Optional", text: $draft.password)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                field("Default Database") {
                    TextField("Optional", text: $draft.database)
                        .textFieldStyle(.roundedBorder)
                }
                field("Auth Database") {
                    TextField("admin", text: $draft.authDatabase)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - SSH Section

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with toggle
            HStack {
                sectionHeader("SSH Tunnel", icon: "lock.shield.fill")
                Spacer()
                Toggle("", isOn: $draft.useSSHTunnel.animation(.easeInOut(duration: 0.2)))
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, draft.useSSHTunnel ? 12 : 14)

            if draft.useSSHTunnel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        field("SSH Host") {
                            TextField("ssh.example.com", text: $draft.sshHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        field("Port") {
                            TextField("22", text: $draft.sshPort)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(width: 70)
                    }

                    field("SSH Username") {
                        TextField("e.g. ubuntu", text: $draft.sshUser)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Auth mode pills
                    HStack(spacing: 0) {
                        ForEach(SSHTunnelConfig.SSHAuthMode.allCases, id: \.self) { m in
                            let active = draft.sshAuthMode == m
                            Button { withAnimation(.easeInOut(duration: 0.15)) { draft.sshAuthMode = m } } label: {
                                Text(m.rawValue)
                                    .font(.system(.caption, design: .rounded, weight: active ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(active ? Color.accentColor : .clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(active ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

                    if draft.sshAuthMode == .password {
                        field("SSH Password") {
                            SecureField("Enter SSH password", text: $draft.sshPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        field("Private Key Path") {
                            HStack(spacing: 6) {
                                TextField("~/.ssh/id_rsa", text: $draft.sshPrivateKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: browsePrivateKey) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Browse…")
                            }
                        }
                        field("Passphrase") {
                            SecureField("Optional", text: $draft.sshPrivateKeyPassphrase)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: runTestConnection) {
                HStack(spacing: 5) {
                    if isTestingConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isTestingConnection ? "Testing…" : "Test Connection")
                        .font(.callout)
                }
            }
            .buttonStyle(.bordered)
            .disabled(draft.host.isEmpty || isTestingConnection)

            Button(action: { onSave(mode); dismiss() }) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Save")
                        .font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(draft.host.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Reusable bits

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 18)
            .opacity(0.4)
    }

    // MARK: - Actions

    private func browsePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = "Select Private Key"
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.sshPrivateKeyPath = url.path
        }
    }

    private func runTestConnection() {
        isTestingConnection = true
        testDebugText = ""
        let profile = draft.build()

        Task {
            var log = "[Test Connection: \(profile.name)]\n"
            log += "────────────────────────────────────────\n"
            log += "Step 1: Validate Configuration\n"
            log += "  • Host: \(profile.host):\(profile.port)\n"
            log += "  • SSL/TLS: \(profile.useSSL ? "Enabled" : "Disabled")\n"
            log += "  • SSH Tunnel: \(profile.useSSHTunnel ? "Enabled" : "Disabled")\n"

            if profile.host.contains("mongodb.net") && !profile.useSSL {
                log += "  ! WARNING: MongoDB Atlas requires SSL/TLS. Please enable it.\n"
            }

            var testURI: String
            var fallbackTestURI: String?
            var forwardMap: [String: Int]?
            var fallbackForwardMap: [String: Int]?
            var tunnelStarted = false

            do {
                // ── STEP 1: SSH Key Validation (if applicable) ────────────────
                if profile.useSSHTunnel && profile.sshTunnel.authMode == .privateKey {
                    log += "\nStep 2: Check SSH Private Key Access\n"
                    do {
                        try await SSHTunnelService.shared.validateKeyAccess(config: profile.sshTunnel)
                        log += "  ✓ Key is accessible\n"
                    } catch {
                        log += "  ✗ Key access failed: \(error.localizedDescription)\n"
                        throw error
                    }
                } else if profile.useSSHTunnel {
                    log += "\nStep 2: Skip Key Check (using Password Auth)\n"
                }

                // ── STEP 2: SSH local forwarding setup ───────────────────────
                if profile.useSSHTunnel {
                    _ = SSHTunnelDebugLog.shared.drain()
                    log += "\nStep 3: Establish SSH Local Forwards\n"
                    let ssh = profile.sshTunnel
                    log += "  • Connecting to \(ssh.sshUser)@\(ssh.sshHost):\(ssh.sshPort)...\n"

                    do {
                        let targets: [SSHForwardTarget]
                        let extraOptions: [String: String]
                        let directConnection: Bool

                        if profile.useSRV {
                            log += "  • Resolving SRV/TXT for \(profile.host)...\n"
                            let (records, txt) = await DNSDebugService.resolveSRVAndTXT(host: profile.host)
                            guard !records.isEmpty else {
                                throw SSHTunnelError.configInvalid("No SRV records found for \(profile.host)")
                            }
                            targets = records.map {
                                SSHForwardTarget(host: $0.target, port: Int($0.port))
                            }
                            extraOptions = txt.items
                            directConnection = false
                            for target in targets {
                                log += "    - \(target.host):\(target.port)\n"
                            }
                        } else {
                            targets = [SSHForwardTarget(host: profile.host, port: profile.port)]
                            extraOptions = [:]
                            directConnection = true
                        }

                        let forwards = try await SSHTunnelService.shared.startLocalForwarding(config: ssh, targets: targets)
                        tunnelStarted = true
                        let endpoints = forwards.map { "\($0.remoteHost):\($0.remotePort)" }
                        forwardMap = Dictionary(
                            uniqueKeysWithValues: forwards.map {
                                ("\($0.remoteHost.lowercased()):\($0.remotePort)", $0.localPort)
                            }
                        )
                        testURI = profile.localForwardConnectionString(
                            endpoints: endpoints,
                            extraOptions: extraOptions,
                            directConnection: directConnection
                        )
                        if profile.useSRV, let firstForward = forwards.first {
                            let firstEndpoint = "\(firstForward.remoteHost):\(firstForward.remotePort)"
                            fallbackTestURI = profile.localForwardConnectionString(
                                endpoints: [firstEndpoint],
                                extraOptions: extraOptions,
                                directConnection: true
                            )
                            fallbackForwardMap = [
                                "\(firstForward.remoteHost.lowercased()):\(firstForward.remotePort)": firstForward.localPort
                            ]
                        } else {
                            fallbackTestURI = nil
                            fallbackForwardMap = nil
                        }
                        log += "  ✓ SSH forwards established\n"
                        for forward in forwards {
                            log += "    - \(forward.localHost):\(forward.localPort) → \(forward.remoteHost):\(forward.remotePort)\n"
                        }
                    } catch {
                        log += "  ✗ SSH forwarding failed: \(error.localizedDescription)\n"
                        throw error
                    }
                } else {
                    testURI = profile.connectionString
                    fallbackTestURI = nil
                    forwardMap = nil
                    fallbackForwardMap = nil
                    log += "\nStep 2: No SSH Tunnel required\n"
                }

                // ── STEP 3: MongoDB ping ──────────────────────────────────────
                log += "\nStep 4: Test MongoDB Connection\n"
                log += "  • URI: \(testURI.replacingOccurrences(of: profile.password, with: "****").replacingOccurrences(of: profile.sshTunnel.password, with: "****"))\n"
                log += "  • Pinging MongoDB...\n"

                do {
                    do {
                        try await MongoService.shared.testConnection(uri: testURI, tunnelForwardMap: forwardMap)
                    } catch {
                        guard let fallbackTestURI else { throw error }
                        log += "  ! Seed-list connection failed, retrying direct local forward...\n"
                        log += "  • Fallback URI: \(fallbackTestURI.replacingOccurrences(of: profile.password, with: "****").replacingOccurrences(of: profile.sshTunnel.password, with: "****"))\n"
                        try await MongoService.shared.testConnection(uri: fallbackTestURI, tunnelForwardMap: fallbackForwardMap)
                    }
                    log += "  ✓ MongoDB ping succeeded!\n"
                } catch {
                    log += "  ✗ MongoDB connection failed: \(error.localizedDescription)\n"
                    let sshTrace = SSHTunnelDebugLog.shared.drain()
                    if !sshTrace.isEmpty {
                        log += "\nSSH Forward Trace\n"
                        for line in sshTrace {
                            log += "  \(line)\n"
                        }
                    }
                    if error.localizedDescription.contains("connection closed") {
                        log += "  ! HINT: This often means the server expects SSL/TLS but it is disabled, or the target host/port is not accessible through the tunnel.\n"
                    }
                    throw error
                }

                // ── SUCCESS Cleanup ──────────────────────────────────────────
                if tunnelStarted {
                    await SSHTunnelService.shared.stopTunnel()
                    log += "\nStep 5: Cleanup\n  • SSH Tunnel closed\n"
                }

                log += "\n────────────────────────────────────────\n"
                log += "RESULT: CONNECTION SUCCESSFUL ✓"

                await MainActor.run {
                    testDebugText    = log
                    showTestDebug    = true
                    isTestingConnection = false
                }

            } catch {
                // ── FAILURE Cleanup ──────────────────────────────────────────
                if tunnelStarted {
                    await SSHTunnelService.shared.stopTunnel()
                    log += "\nStep 5: Cleanup\n  • SSH Tunnel closed after error\n"
                }

                log += "\n────────────────────────────────────────\n"
                log += "RESULT: CONNECTION FAILED ✗"

                await MainActor.run {
                    testDebugText    = log
                    showTestDebug    = true
                    isTestingConnection = false
                }
            }
        }
    }
}

// MARK: - EditorMode helpers

private extension EditorMode {
    var title: String {
        switch self {
        case .create: return "New Connection"
        case .edit:   return "Edit Connection"
        }
    }
}



// MARK: - DebugTextSheet

private struct DebugTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Debug Log", systemImage: "terminal.fill").font(.headline)
                Spacer()
                if didCopy {
                    Text("Copied!").font(.caption).foregroundStyle(.secondary).transition(.opacity)
                }
                Button(action: copyText) { Label("Copy", systemImage: "doc.on.doc") }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 4)
            ScrollView {
                Text(text.isEmpty ? "No data available." : text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 280)
        }
        .padding(20)
        .frame(width: 580, height: 420)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { didCopy = false } }
    }
}
