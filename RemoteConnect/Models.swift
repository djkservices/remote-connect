import Foundation

// MARK: - Server Types

enum ServerType: String, Codable, CaseIterable {
    case ftp = "FTP"
    case smb = "SMB"
    case rdp = "RDP"

    var icon: String {
        switch self {
        case .ftp: return "arrow.up.arrow.down.circle"
        case .smb: return "folder.badge.person.crop"
        case .rdp: return "desktopcomputer"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ftp: return 21
        case .smb: return 445
        case .rdp: return 3389
        }
    }
}

// MARK: - Server Model

struct Server: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    var username: String
    var serverType: ServerType
    var shareName: String = ""  // For SMB
    var domain: String = ""     // For SMB/RDP
    var defaultPath: String = "/" // For FTP
    var autoConnect: Bool = false
    var lastConnected: Date?

    init(name: String, host: String, port: Int? = nil, username: String, serverType: ServerType) {
        self.name = name
        self.host = host
        self.port = port ?? serverType.defaultPort
        self.username = username
        self.serverType = serverType
    }

    var displayHost: String {
        port == serverType.defaultPort ? host : "\(host):\(port)"
    }

    var serverKey: String {
        "\(serverType.rawValue):\(host):\(port)"
    }
}

// MARK: - Remote File

struct RemoteFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date
    let isHidden: Bool

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "txt", "rtf": return "doc.plaintext.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff": return "photo.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc.fill"
        }
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

// MARK: - Transfer Item

struct TransferItem: Identifiable {
    let id = UUID()
    let sourcePath: String
    let destinationPath: String
    let fileName: String
    let isUpload: Bool
    let serverID: UUID
    let totalBytes: Int64
    var transferredBytes: Int64 = 0
    var status: TransferStatus = .pending
    var error: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    enum TransferStatus: String {
        case pending = "Pending"
        case inProgress = "Transferring"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }
}
