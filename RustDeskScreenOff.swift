import AppKit
import CoreGraphics
import Foundation

// MARK: - Screen Control

class ScreenController {
    private var isBlack = false

    func setBlack() {
        guard !isBlack else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &displays, &count)
        for i in 0..<Int(count) {
            CGSetDisplayTransferByFormula(displays[i],
                0, 0, 1,
                0, 0, 1,
                0, 0, 1)
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

// MARK: - Log Monitor

class LogMonitor {
    var onConnectionOpened: (() -> Void)?
    var onConnectionClosed: (() -> Void)?

    private var tailProcess: Process?
    private let queue = DispatchQueue(label: "log-monitor", qos: .background)

    func start() {
        queue.async { [weak self] in
            self?.runTail()
        }
    }

    func stop() {
        tailProcess?.terminate()
        tailProcess = nil
    }

    private func runTail() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let log1 = "\(home)/Library/Logs/RustDesk/RustDesk_rCURRENT.log"
        let log2 = "\(home)/Library/Logs/RustDesk/server/RustDesk_rCURRENT.log"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-n", "0", "-F", log1, log2]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        tailProcess = process

        do {
            try process.run()
        } catch {
            NSLog("Failed to start tail: \(error)")
            return
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while process.isRunning {
            let data = handle.availableData
            if data.isEmpty {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            buffer.append(data)

            while let range = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    if line.contains("Connection opened from") {
                        DispatchQueue.main.async { self.onConnectionOpened?() }
                    } else if line.contains("Connection closed") {
                        DispatchQueue.main.async { self.onConnectionClosed?() }
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var autoLaunchMenuItem: NSMenuItem!

    private let screenCtl = ScreenController()
    private let logMonitor = LogMonitor()
    private var safetyTimer: DispatchSourceTimer?
    private var debounceTime: Date = .distantPast

    private let launchAgentLabel = "com.rustdesk.screen-off"
    private var launchAgentPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist"
    }
    private var appPath: String {
        Bundle.main.bundlePath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupLogMonitor()
        installAutoLaunch()
        updateStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logMonitor.stop()
        screenCtl.restore()
        stopSafetyTimer()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "RustDesk Screen Off")

        statusMenu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Monitoring", action: #selector(noop), keyEquivalent: "")
        statusMenuItem.target = self
        statusMenu.addItem(statusMenuItem)

        autoLaunchMenuItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        autoLaunchMenuItem.state = .on
        autoLaunchMenuItem.isEnabled = false
        statusMenu.addItem(autoLaunchMenuItem)

        statusMenu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "RustDesk remote auto screen-off", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        statusMenu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    // MARK: - Log Monitor

    private func setupLogMonitor() {
        logMonitor.onConnectionOpened = { [weak self] in
            self?.handleConnectionOpened()
        }
        logMonitor.onConnectionClosed = { [weak self] in
            self?.handleConnectionClosed()
        }
        logMonitor.start()
    }

    // MARK: - Connection Handling

    private func handleConnectionOpened() {
        guard canAct() else { return }

        NSLog("RustDesk connection detected — setting screen to black")
        screenCtl.setBlack()
        startSafetyTimer()
        updateStatus()
    }

    private func handleConnectionClosed() {
        guard screenCtl.isScreenBlack else { return }
        guard canAct() else { return }

        NSLog("RustDesk disconnected — restoring screen + locking")
        stopSafetyTimer()
        screenCtl.restore()
        screenCtl.lockScreen()
        updateStatus()
    }

    private func canAct() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(debounceTime) >= 3 else { return false }
        debounceTime = now
        return true
    }

    // MARK: - Safety Timer

    private func startSafetyTimer() {
        stopSafetyTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 300, repeating: 300)
        timer.setEventHandler { [weak self] in
            self?.checkSafety()
        }
        timer.resume()
        safetyTimer = timer
    }

    private func stopSafetyTimer() {
        safetyTimer?.cancel()
        safetyTimer = nil
    }

    private func checkSafety() {
        guard screenCtl.isScreenBlack else {
            stopSafetyTimer()
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "rustdesk.*--cm"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            NSLog("[TIMER] No active RustDesk connection, restoring screen")
            screenCtl.restore()
            screenCtl.lockScreen()
            stopSafetyTimer()
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

    @objc private func noop() {}

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Auto Launch

    private func isAutoLaunchEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    private func installAutoLaunch() {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
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
