import AppKit
import CoreGraphics
import Foundation

// MARK: - Screen Control

class ScreenController {
    private var isBlack = false
    private var mirroredDisplays: [CGDirectDisplayID] = []

    func enableMirroring() {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &displays, &count)

        let main = CGMainDisplayID()
        guard count > 1 else { return }

        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)

        var mirrored: [CGDirectDisplayID] = []
        for i in 0..<Int(count) {
            let d = displays[i]
            if d != main && CGDisplayMirrorsDisplay(d) == kCGNullDirectDisplay {
                CGConfigureDisplayMirrorOfDisplay(config, d, main)
                mirrored.append(d)
            }
        }

        if mirrored.isEmpty {
            CGCancelDisplayConfiguration(config)
            return
        }

        let err = CGCompleteDisplayConfiguration(config, .forSession)
        if err == .success {
            mirroredDisplays = mirrored
            NSLog("Mirroring enabled for \(mirrored.count) display(s)")
        }
    }

    func disableMirroring() {
        guard !mirroredDisplays.isEmpty else { return }

        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        for d in mirroredDisplays {
            CGConfigureDisplayMirrorOfDisplay(config, d, kCGNullDirectDisplay)
        }
        let err = CGCompleteDisplayConfiguration(config, .forSession)
        if err == .success {
            NSLog("Mirroring disabled, restored \(mirroredDisplays.count) display(s)")
            mirroredDisplays = []
        }
    }

    func setBlack() {
        guard !isBlack else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &displays, &count)
        for i in 0..<Int(count) {
            CGSetDisplayTransferByFormula(displays[i], 0, 0, 1, 0, 0, 1, 0, 0, 1)
        }
        isBlack = true
    }

    func restore() {
        guard isBlack else { return }
        CGDisplayRestoreColorSyncSettings()
        isBlack = false
    }

    func lockScreen() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "ScreenSaverEngine"]
        try? task.run()
    }

    var isScreenBlack: Bool { isBlack }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!

    private let screenCtl = ScreenController()
    private var pollTimer: DispatchSourceTimer?

    private let launchAgentLabel = "com.rustdesk.screen-off"
    private var launchAgentPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        installAutoLaunch()
        pollConnectionState()
        startPollTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPollTimer()
        screenCtl.restore()
        screenCtl.disableMirroring()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "RustDesk Screen Off")

        statusMenu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Monitoring", action: nil, keyEquivalent: "")
        statusMenu.addItem(statusMenuItem)

        let autoLaunchItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        autoLaunchItem.state = .on
        autoLaunchItem.isEnabled = false
        statusMenu.addItem(autoLaunchItem)

        statusMenu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "RustDesk remote auto screen-off", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        statusMenu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    // MARK: - Connection Detection (1s process poll)

    private func startPollTimer() {
        stopPollTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.pollConnectionState()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPollTimer() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func isRustDeskConnected() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fi", "rustdesk.*--cm"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    private func pollConnectionState() {
        let connected = isRustDeskConnected()

        if connected && !screenCtl.isScreenBlack {
            NSLog("[POLL] RustDesk connection active — activating screen off")
            screenCtl.enableMirroring()
            screenCtl.setBlack()
            updateStatus()
        } else if !connected && screenCtl.isScreenBlack {
            NSLog("[POLL] No active RustDesk connection — restoring screen")
            screenCtl.restore()
            screenCtl.disableMirroring()
            screenCtl.lockScreen()
            updateStatus()
        }
    }

    // MARK: - UI Updates

    private func updateStatus() {
        if screenCtl.isScreenBlack {
            statusMenuItem.title = "Remote Connected · Screen Off"
            statusItem.button?.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: nil)
            statusItem.button?.title = " Screen Off"
        } else {
            statusMenuItem.title = "Monitoring"
            statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
            statusItem.button?.title = ""
        }
    }

    // MARK: - Actions

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Auto Launch

    private func installAutoLaunch() {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: launchAgentPath))
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
