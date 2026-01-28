# RemoteConnect

A unified macOS menu bar app for managing remote server connections - FTP, SMB, and RDP in one place.

## Features

### Servers Tab
- **Multi-Protocol Support**: FTP, SMB (Windows shares), and RDP
- **Server Management**: Add, edit, delete server configurations
- **Quick Connect**: One-click connection to saved servers
- **Connection Status**: Visual indicators for active connections
- **Filter by Type**: Filter server list by protocol type
- **Auto-Connect**: Mark servers for automatic connection (future feature)

### Files Tab (FTP/SMB)
- **File Browsing**: Navigate remote directories
- **Navigation**: Back, forward, up, refresh
- **Hidden Files**: Toggle visibility of hidden files
- **Download**: Download files from FTP servers
- **Path Copy**: Copy file paths to clipboard
- **Sorting**: Sort by name, size, date, or type

### Transfers Tab
- **Transfer Queue**: View active and completed transfers
- **Progress Tracking**: Monitor upload/download progress
- **Status Indicators**: Pending, in-progress, completed, failed
- **Clear Completed**: Remove finished transfers from queue

### Protocol Details

#### FTP
- Standard FTP connection via curl
- Directory listing and navigation
- File download with progress
- Upload support

#### SMB (Windows Shares)
- Native macOS mounting via Finder
- Full file system access after mounting
- Domain authentication support
- Opens files with default applications
- Automatic volume detection

#### RDP (Remote Desktop)
- Launches FreeRDP for remote desktop
- Requires `sdl-freerdp` (install: `brew install freerdp`)
- Domain authentication support
- Multiple concurrent sessions

## Requirements

- macOS 13.0 or later
- Swift 5.9+
- For RDP: FreeRDP (`brew install freerdp`)

## Building

1. Open `RemoteConnect.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (Cmd+R)

## Usage

1. RemoteConnect appears as a server icon in the menu bar
2. Click to open the popover
3. Add servers using the + button
4. Click Connect to establish connection
5. For FTP/SMB: Use Files tab to browse and transfer
6. For RDP: Click Connect to launch remote desktop session
7. Monitor transfers in the Transfers tab

## Security

- Passwords stored securely in macOS Keychain
- Credentials never stored in plain text
- SMB URLs with credentials are never logged

## Tech Stack

- SwiftUI for UI
- Security framework for Keychain storage
- Foundation for network operations
- Process for shell commands (curl, mount_smbfs, freerdp)
- AppKit for menu bar integration
