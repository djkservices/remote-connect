import Foundation
import AppKit
import Combine

class ServerManager: ObservableObject {
    @Published var servers: [Server] = []
    @Published var connectedServerID: UUID?
    @Published var currentPath: String = ""
    @Published var files: [RemoteFile] = []
    @Published var isConnecting = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var transferQueue: [TransferItem] = []
    @Published var navigationHistory: [String] = []
    @Published var historyIndex: Int = -1
    @Published var sortBy: SortOption = .name
    @Published var sortAscending = true
    @Published var showHiddenFiles = false

    // RDP active sessions
    @Published var activeRDPSessions: Set<String> = []
    private var rdpProcesses: [String: Process] = [:]

    // SMB mount point
    private var smbMountPoint: URL?

    private var fileManager = FileManager.default
    private let keychain = KeychainManager.shared

    enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case date = "Date"
        case type = "Type"
    }

    var connectedServer: Server? {
        servers.first { $0.id == connectedServerID }
    }

    var isConnected: Bool {
        connectedServerID != nil
    }

    var sortedFiles: [RemoteFile] {
        var result = files

        if !showHiddenFiles {
            result = result.filter { !$0.isHidden }
        }

        result.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }

            let comparison: Bool
            switch sortBy {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size:
                comparison = a.size < b.size
            case .date:
                comparison = a.modificationDate < b.modificationDate
            case .type:
                let extA = (a.name as NSString).pathExtension
                let extB = (b.name as NSString).pathExtension
                comparison = extA.localizedCaseInsensitiveCompare(extB) == .orderedAscending
            }

            return sortAscending ? comparison : !comparison
        }

        return result
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }
    var canGoUp: Bool { !currentPath.isEmpty && currentPath != "/" }

    init() {
        loadServers()
    }

    // MARK: - Storage

    private var configDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("RemoteConnect")
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder
    }

    private var serversFileURL: URL {
        configDir.appendingPathComponent("servers.json")
    }

    func loadServers() {
        guard let data = try? Data(contentsOf: serversFileURL),
              let decoded = try? JSONDecoder().decode([Server].self, from: data) else {
            return
        }
        servers = decoded
    }

    func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        try? data.write(to: serversFileURL)
    }

    // MARK: - Server Management

    func addServer(_ server: Server, password: String) {
        var newServer = server
        newServer.id = UUID()
        servers.append(newServer)
        saveServers()
        keychain.savePassword(password, for: newServer)
    }

    func updateServer(_ server: Server, password: String?) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
            if let password = password, !password.isEmpty {
                keychain.savePassword(password, for: server)
            }
        }
    }

    func deleteServer(_ server: Server) {
        if connectedServerID == server.id {
            disconnect()
        }
        if server.serverType == .rdp {
            disconnectRDP(server)
        }
        servers.removeAll { $0.id == server.id }
        keychain.deletePassword(for: server)
        saveServers()
    }

    // MARK: - Connection

    func connect(to server: Server) {
        guard let password = keychain.getPassword(for: server) else {
            errorMessage = "No password found for this server"
            return
        }

        switch server.serverType {
        case .ftp:
            connectFTP(server: server, password: password)
        case .smb:
            connectSMB(server: server, password: password)
        case .rdp:
            connectRDP(server: server, password: password)
        }
    }

    func disconnect() {
        guard let server = connectedServer else {
            connectedServerID = nil
            return
        }

        switch server.serverType {
        case .smb:
            disconnectSMB()
        case .ftp, .rdp:
            break
        }

        connectedServerID = nil
        files = []
        currentPath = ""
        navigationHistory = []
        historyIndex = -1
    }

    // MARK: - FTP Connection

    private func connectFTP(server: Server, password: String) {
        isConnecting = true
        errorMessage = nil
        statusMessage = "Connecting to FTP..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let testCmd = "curl -s --connect-timeout 10 --max-time 15 -u '\(server.username):\(password)' 'ftp://\(server.host):\(server.port)/' > /dev/null 2>&1 && echo 'OK' || echo 'FAIL'"

            let result = self?.runShellCommand(testCmd) ?? "FAIL"

            DispatchQueue.main.async {
                self?.isConnecting = false

                if result.contains("OK") {
                    self?.connectedServerID = server.id
                    self?.currentPath = server.defaultPath.isEmpty ? "/" : server.defaultPath
                    self?.navigationHistory = [self?.currentPath ?? "/"]
                    self?.historyIndex = 0
                    self?.statusMessage = "Connected to \(server.name)"

                    if var s = self?.servers.first(where: { $0.id == server.id }) {
                        s.lastConnected = Date()
                        self?.updateServer(s, password: nil)
                    }

                    self?.loadFiles()
                } else {
                    self?.errorMessage = "FTP connection failed. Check credentials."
                }
            }
        }
    }

    // MARK: - SMB Connection

    private func connectSMB(server: Server, password: String) {
        isConnecting = true
        errorMessage = nil
        statusMessage = "Connecting to SMB..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performSMBConnect(server: server, password: password)
        }
    }

    private func performSMBConnect(server: Server, password: String) {
        let volumesPath = "/Volumes/\(server.name.replacingOccurrences(of: " ", with: "_"))_\(server.shareName)"
        let mountURL = URL(fileURLWithPath: volumesPath)

        // Unmount if exists
        if fileManager.fileExists(atPath: volumesPath) {
            let unmount = Process()
            unmount.launchPath = "/usr/sbin/diskutil"
            unmount.arguments = ["unmount", volumesPath]
            try? unmount.run()
            unmount.waitUntilExit()
        }

        // Build SMB URL
        var smbURLString = "smb://"
        if !server.domain.isEmpty {
            smbURLString += "\(server.domain);"
        }

        let encodedUsername = server.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? server.username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password

        smbURLString += "\(encodedUsername):\(encodedPassword)@\(server.host)"
        if server.port != 445 {
            smbURLString += ":\(server.port)"
        }
        smbURLString += "/\(server.shareName)"

        // Mount
        let mount = Process()
        mount.launchPath = "/sbin/mount_smbfs"
        mount.arguments = [smbURLString, volumesPath]

        try? fileManager.createDirectory(atPath: volumesPath, withIntermediateDirectories: true, attributes: nil)

        let pipe = Pipe()
        mount.standardError = pipe

        do {
            try mount.run()
            mount.waitUntilExit()

            if mount.terminationStatus == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.smbMountPoint = mountURL
                    self?.connectedServerID = server.id
                    self?.isConnecting = false
                    self?.currentPath = ""
                    self?.navigationHistory = [""]
                    self?.historyIndex = 0
                    self?.statusMessage = "Connected to \(server.name)"

                    if var s = self?.servers.first(where: { $0.id == server.id }) {
                        s.lastConnected = Date()
                        self?.updateServer(s, password: nil)
                    }

                    self?.loadFiles()
                }
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"

                DispatchQueue.main.async { [weak self] in
                    self?.isConnecting = false
                    self?.errorMessage = "SMB connection failed: \(errorString)"
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.isConnecting = false
                self?.errorMessage = "SMB connection failed: \(error.localizedDescription)"
            }
        }
    }

    private func disconnectSMB() {
        guard let mount = smbMountPoint else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let unmount = Process()
            unmount.launchPath = "/usr/sbin/diskutil"
            unmount.arguments = ["unmount", mount.path]
            try? unmount.run()
            unmount.waitUntilExit()

            DispatchQueue.main.async {
                self?.smbMountPoint = nil
            }
        }
    }

    // MARK: - RDP Connection

    private func connectRDP(server: Server, password: String) {
        if activeRDPSessions.contains(server.serverKey) {
            errorMessage = "Already connected to \(server.host)"
            return
        }

        guard isFreerdpInstalled else {
            errorMessage = "FreeRDP not found. Install with: brew install freerdp"
            return
        }

        if var s = servers.first(where: { $0.id == server.id }) {
            s.lastConnected = Date()
            updateServer(s, password: nil)
        }

        launchFreeRDP(server: server, password: password)
    }

    private var freerdpPath: String {
        let paths = ["/opt/homebrew/bin/sdl-freerdp", "/usr/local/bin/sdl-freerdp"]
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return "/opt/homebrew/bin/sdl-freerdp"
    }

    private var isFreerdpInstalled: Bool {
        fileManager.fileExists(atPath: freerdpPath)
    }

    private func launchFreeRDP(server: Server, password: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: freerdpPath)

        var args: [String] = []
        args.append("/v:\(server.host)")
        if server.port != 3389 {
            args.append("/port:\(server.port)")
        }
        args.append("/u:\(server.username)")
        args.append("/p:\(password)")

        if !server.domain.isEmpty {
            args.append("/d:\(server.domain)")
        }

        args.append("/cert:ignore")
        args.append("-wallpaper")
        args.append("-themes")
        args.append("/t:\(server.name)")

        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        let serverKey = server.serverKey

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.rdpProcesses.removeValue(forKey: serverKey)
                self?.activeRDPSessions.remove(serverKey)
            }
        }

        do {
            try process.run()
            activeRDPSessions.insert(serverKey)
            rdpProcesses[serverKey] = process
            statusMessage = "RDP session started for \(server.name)"
        } catch {
            errorMessage = "Failed to launch RDP: \(error.localizedDescription)"
        }
    }

    func disconnectRDP(_ server: Server) {
        let serverKey = server.serverKey
        if let process = rdpProcesses[serverKey] {
            process.terminate()
            rdpProcesses.removeValue(forKey: serverKey)
            activeRDPSessions.remove(serverKey)
        }
    }

    func isRDPActive(for server: Server) -> Bool {
        activeRDPSessions.contains(server.serverKey)
    }

    // MARK: - File Operations

    func loadFiles() {
        guard let server = connectedServer else { return }

        switch server.serverType {
        case .ftp:
            loadFTPFiles(server: server)
        case .smb:
            loadSMBFiles()
        case .rdp:
            break // RDP doesn't have file browsing in this implementation
        }
    }

    private func loadFTPFiles(server: Server) {
        guard let password = keychain.getPassword(for: server) else { return }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let path = self.currentPath.hasPrefix("/") ? self.currentPath : "/\(self.currentPath)"
            let cmd = "curl -s --connect-timeout 10 --max-time 30 -u '\(server.username):\(password)' 'ftp://\(server.host):\(server.port)\(path)/'"

            let output = self.runShellCommand(cmd)
            let parsedFiles = self.parseFTPDirectoryListing(output, basePath: path)

            DispatchQueue.main.async {
                self.isLoading = false
                self.files = parsedFiles
            }
        }
    }

    private func loadSMBFiles() {
        guard let mount = smbMountPoint else { return }

        isLoading = true
        let fullPath = mount.appendingPathComponent(currentPath)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let contents = try self.fileManager.contentsOfDirectory(
                    at: fullPath,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey],
                    options: []
                )

                let remoteFiles = contents.compactMap { url -> RemoteFile? in
                    guard let resources = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]) else {
                        return nil
                    }

                    return RemoteFile(
                        name: url.lastPathComponent,
                        path: url.path,
                        isDirectory: resources.isDirectory ?? false,
                        size: Int64(resources.fileSize ?? 0),
                        modificationDate: resources.contentModificationDate ?? Date(),
                        isHidden: resources.isHidden ?? false
                    )
                }

                DispatchQueue.main.async {
                    self.files = remoteFiles
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load files: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func parseFTPDirectoryListing(_ output: String, basePath: String) -> [RemoteFile] {
        var items: [RemoteFile] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.count > 10 {
                let isDir = trimmed.hasPrefix("d")
                let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)

                if components.count >= 9 {
                    let name = components[8...].joined(separator: " ")
                    guard name != "." && name != ".." else { continue }

                    let size = Int64(components[4]) ?? 0
                    let path = "\(basePath)/\(name)".replacingOccurrences(of: "//", with: "/")

                    items.append(RemoteFile(
                        name: String(name),
                        path: path,
                        isDirectory: isDir,
                        size: size,
                        modificationDate: Date(),
                        isHidden: name.hasPrefix(".")
                    ))
                }
            } else {
                guard trimmed != "." && trimmed != ".." else { continue }
                let isDir = trimmed.hasSuffix("/") || !trimmed.contains(".")
                let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let path = "\(basePath)/\(name)".replacingOccurrences(of: "//", with: "/")

                items.append(RemoteFile(
                    name: name,
                    path: path,
                    isDirectory: isDir,
                    size: 0,
                    modificationDate: Date(),
                    isHidden: name.hasPrefix(".")
                ))
            }
        }

        return items.sorted { (a, b) in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    // MARK: - Navigation

    func navigateTo(_ path: String) {
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }

        currentPath = path
        navigationHistory.append(path)
        historyIndex = navigationHistory.count - 1
        loadFiles()
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentPath = navigationHistory[historyIndex]
        loadFiles()
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentPath = navigationHistory[historyIndex]
        loadFiles()
    }

    func goUp() {
        guard canGoUp else { return }
        let parentPath = (currentPath as NSString).deletingLastPathComponent
        navigateTo(parentPath)
    }

    func openItem(_ file: RemoteFile) {
        if file.isDirectory {
            let newPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            navigateTo(newPath)
        } else if connectedServer?.serverType == .smb {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        }
    }

    // MARK: - Transfers

    func downloadFile(_ file: RemoteFile) {
        guard let server = connectedServer else { return }

        switch server.serverType {
        case .ftp:
            downloadFTPFile(file, server: server)
        case .smb:
            // SMB files are already local after mounting
            NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
        case .rdp:
            break
        }
    }

    private func downloadFTPFile(_ file: RemoteFile, server: Server) {
        guard let password = keychain.getPassword(for: server) else { return }

        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(file.name)

        var item = TransferItem(
            sourcePath: file.path,
            destinationPath: tempURL.path,
            fileName: file.name,
            isUpload: false,
            serverID: server.id,
            totalBytes: file.size
        )

        transferQueue.append(item)
        let itemID = item.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let idx = self.transferQueue.firstIndex(where: { $0.id == itemID }) {
                DispatchQueue.main.async {
                    self.transferQueue[idx].status = .inProgress
                }
            }

            try? self.fileManager.removeItem(at: tempURL)

            let cmd = "curl -s --connect-timeout 10 --max-time 120 -u '\(server.username):\(password)' 'ftp://\(server.host):\(server.port)\(file.path)' -o '\(tempURL.path)'"

            _ = self.runShellCommand(cmd)

            DispatchQueue.main.async {
                if let idx = self.transferQueue.firstIndex(where: { $0.id == itemID }) {
                    if self.fileManager.fileExists(atPath: tempURL.path) {
                        self.transferQueue[idx].status = .completed
                        self.transferQueue[idx].transferredBytes = file.size
                        NSWorkspace.shared.open(tempURL)
                    } else {
                        self.transferQueue[idx].status = .failed
                        self.transferQueue[idx].error = "Download failed"
                    }
                }
            }
        }
    }

    func uploadFile(from localURL: URL) {
        guard let server = connectedServer, server.serverType == .ftp else { return }
        guard let password = keychain.getPassword(for: server) else { return }

        let size = (try? fileManager.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        let remotePath = "\(currentPath)/\(localURL.lastPathComponent)".replacingOccurrences(of: "//", with: "/")

        var item = TransferItem(
            sourcePath: localURL.path,
            destinationPath: remotePath,
            fileName: localURL.lastPathComponent,
            isUpload: true,
            serverID: server.id,
            totalBytes: size
        )

        transferQueue.append(item)
        let itemID = item.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let idx = self.transferQueue.firstIndex(where: { $0.id == itemID }) {
                DispatchQueue.main.async {
                    self.transferQueue[idx].status = .inProgress
                }
            }

            let cmd = "curl -s --connect-timeout 10 --max-time 300 -u '\(server.username):\(password)' -T '\(localURL.path)' 'ftp://\(server.host):\(server.port)\(remotePath)'"

            let result = self.runShellCommand(cmd)

            DispatchQueue.main.async {
                if let idx = self.transferQueue.firstIndex(where: { $0.id == itemID }) {
                    if result.isEmpty || !result.lowercased().contains("error") {
                        self.transferQueue[idx].status = .completed
                        self.transferQueue[idx].transferredBytes = size
                        self.loadFiles()
                    } else {
                        self.transferQueue[idx].status = .failed
                        self.transferQueue[idx].error = "Upload failed"
                    }
                }
            }
        }
    }

    func clearCompletedTransfers() {
        transferQueue.removeAll { $0.status == .completed || $0.status == .cancelled || $0.status == .failed }
    }

    // MARK: - Utilities

    func copyPath(_ file: RemoteFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path, forType: .string)
        statusMessage = "Path copied"
    }

    private func runShellCommand(_ command: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
