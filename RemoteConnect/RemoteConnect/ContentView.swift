import SwiftUI

struct ContentView: View {
    weak var appDelegate: AppDelegate?
    @ObservedObject var serverManager: ServerManager
    @State private var isPinned = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Servers").tag(0)
                Text("Files").tag(1)
                Text("Transfers").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Content
            switch selectedTab {
            case 0:
                ServersView(serverManager: serverManager)
            case 1:
                FileBrowserView(serverManager: serverManager)
            case 2:
                TransferQueueView(serverManager: serverManager)
            default:
                EmptyView()
            }
        }
        .frame(width: 450, height: 600)
    }

    // MARK: - Header

    var headerView: some View {
        HStack {
            Image(systemName: "externaldrive.connected.to.line.below")
                .foregroundColor(.blue)
            Text("RemoteConnect")
                .font(.headline)

            if serverManager.isConnected, let server = serverManager.connectedServer {
                Text("(\(server.name))")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            // Pin button
            Button(action: {
                isPinned.toggle()
                appDelegate?.togglePin()
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin" : "Pin")
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Servers View

struct ServersView: View {
    @ObservedObject var serverManager: ServerManager
    @State private var showAddServer = false
    @State private var serverToEdit: Server?
    @State private var filterType: ServerType?

    var filteredServers: [Server] {
        if let type = filterType {
            return serverManager.servers.filter { $0.serverType == type }
        }
        return serverManager.servers
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Text("Filter:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $filterType) {
                    Text("All").tag(Optional<ServerType>.none)
                    ForEach(ServerType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(Optional(type))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                Button(action: { showAddServer = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if filteredServers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No servers configured")
                        .foregroundColor(.secondary)
                    Button("Add Server") {
                        showAddServer = true
                    }
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredServers) { server in
                        ServerRowView(server: server, serverManager: serverManager, onEdit: {
                            serverToEdit = server
                        })
                    }
                }
                .listStyle(.plain)
            }

            // Status
            if let status = serverManager.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            if let error = serverManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showAddServer) {
            ServerEditView(serverManager: serverManager, isPresented: $showAddServer)
        }
        .sheet(item: $serverToEdit) { server in
            ServerEditView(serverManager: serverManager, server: server, isPresented: Binding(
                get: { serverToEdit != nil },
                set: { if !$0 { serverToEdit = nil } }
            ))
        }
    }
}

// MARK: - Server Row View

struct ServerRowView: View {
    let server: Server
    @ObservedObject var serverManager: ServerManager
    var onEdit: () -> Void
    @State private var isHovered = false

    var isConnected: Bool {
        serverManager.connectedServerID == server.id
    }

    var isRDPActive: Bool {
        server.serverType == .rdp && serverManager.isRDPActive(for: server)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Server type icon
            Image(systemName: server.serverType.icon)
                .font(.title2)
                .foregroundColor(isConnected || isRDPActive ? .green : .secondary)
                .frame(width: 30)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(server.name)
                        .font(.headline)
                    Text(server.serverType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                Text(server.displayHost)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let lastConnected = server.lastConnected {
                    Text("Last: \(formatDate(lastConnected))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        serverManager.deleteServer(server)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Connect/Disconnect button
            if isConnected {
                Button("Disconnect") {
                    serverManager.disconnect()
                }
                .font(.caption)
                .foregroundColor(.red)
            } else if isRDPActive {
                Button("Active") {
                    serverManager.disconnectRDP(server)
                }
                .font(.caption)
                .foregroundColor(.orange)
            } else {
                Button("Connect") {
                    serverManager.connect(to: server)
                }
                .font(.caption)
                .disabled(serverManager.isConnecting)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Server Edit View

struct ServerEditView: View {
    @ObservedObject var serverManager: ServerManager
    var server: Server?
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var host = ""
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverType: ServerType = .ftp
    @State private var shareName = ""
    @State private var domain = ""
    @State private var defaultPath = "/"

    var isEditing: Bool { server != nil }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Server" : "Add Server")
                .font(.headline)

            Form {
                Picker("Type", selection: $serverType) {
                    ForEach(ServerType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .onChange(of: serverType) {
                    port = String(serverType.defaultPort)
                }

                TextField("Name", text: $name)
                TextField("Host", text: $host)
                TextField("Port", text: $port)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)

                if serverType == .smb {
                    TextField("Share Name", text: $shareName)
                    TextField("Domain (optional)", text: $domain)
                }

                if serverType == .rdp {
                    TextField("Domain (optional)", text: $domain)
                }

                if serverType == .ftp {
                    TextField("Default Path", text: $defaultPath)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    saveServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || host.isEmpty || username.isEmpty || (password.isEmpty && !isEditing))
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            if let server = server {
                name = server.name
                host = server.host
                port = String(server.port)
                username = server.username
                serverType = server.serverType
                shareName = server.shareName
                domain = server.domain
                defaultPath = server.defaultPath
            } else {
                port = String(serverType.defaultPort)
            }
        }
    }

    private func saveServer() {
        var newServer = Server(
            name: name,
            host: host,
            port: Int(port) ?? serverType.defaultPort,
            username: username,
            serverType: serverType
        )
        newServer.shareName = shareName
        newServer.domain = domain
        newServer.defaultPath = defaultPath

        if let existing = server {
            newServer.id = existing.id
            newServer.lastConnected = existing.lastConnected
            serverManager.updateServer(newServer, password: password.isEmpty ? nil : password)
        } else {
            serverManager.addServer(newServer, password: password)
        }

        isPresented = false
    }
}

// MARK: - File Browser View

struct FileBrowserView: View {
    @ObservedObject var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 0) {
            if serverManager.connectedServer == nil || serverManager.connectedServer?.serverType == .rdp {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(serverManager.connectedServer?.serverType == .rdp ? "RDP doesn't support file browsing" : "Not connected")
                        .foregroundColor(.secondary)
                    Text("Connect to an FTP or SMB server to browse files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Navigation bar
                HStack(spacing: 8) {
                    Button(action: { serverManager.goBack() }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(!serverManager.canGoBack)

                    Button(action: { serverManager.goForward() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(!serverManager.canGoForward)

                    Button(action: { serverManager.goUp() }) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(!serverManager.canGoUp)

                    Button(action: { serverManager.loadFiles() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)

                    Text(serverManager.currentPath.isEmpty ? "/" : serverManager.currentPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Toggle("Hidden", isOn: $serverManager.showHiddenFiles)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // File list
                if serverManager.isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if serverManager.sortedFiles.isEmpty {
                    Spacer()
                    Text("Empty folder")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(serverManager.sortedFiles) { file in
                        FileRowView(file: file, serverManager: serverManager)
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: RemoteFile
    @ObservedObject var serverManager: ServerManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title3)
                .foregroundColor(file.isDirectory ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(file.formattedSize)
                    Text(file.formattedDate)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            if isHovered && !file.isDirectory {
                Button(action: {
                    serverManager.downloadFile(file)
                }) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)

                Button(action: {
                    serverManager.copyPath(file)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            serverManager.openItem(file)
        }
    }
}

// MARK: - Transfer Queue View

struct TransferQueueView: View {
    @ObservedObject var serverManager: ServerManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transfer Queue")
                    .font(.headline)
                Spacer()
                if !serverManager.transferQueue.isEmpty {
                    Button("Clear Completed") {
                        serverManager.clearCompletedTransfers()
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if serverManager.transferQueue.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No active transfers")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List(serverManager.transferQueue) { item in
                    TransferRowView(item: item)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Transfer Row View

struct TransferRowView: View {
    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: item.isUpload ? "arrow.up.circle" : "arrow.down.circle")
                    .foregroundColor(item.isUpload ? .green : .blue)

                Text(item.fileName)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text(item.status.rawValue)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            if item.status == .inProgress {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
            }

            if let error = item.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }

    var statusColor: Color {
        switch item.status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
