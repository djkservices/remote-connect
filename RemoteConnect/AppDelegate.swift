import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var serverManager = ServerManager()
    var isPinned: Bool = false {
        didSet {
            updatePopoverBehavior()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "RemoteConnect")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 450, height: 600)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(
            rootView: ContentView(appDelegate: self, serverManager: serverManager)
        )
    }

    func updatePopoverBehavior() {
        popover?.behavior = isPinned ? .applicationDefined : .transient
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func togglePin() {
        isPinned.toggle()
    }

    func updateIcon() {
        if let button = statusItem?.button {
            let iconName: String
            if serverManager.isConnected {
                iconName = "externaldrive.fill.badge.checkmark"
            } else {
                iconName = "externaldrive.connected.to.line.below"
            }
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "RemoteConnect")
        }
    }
}
