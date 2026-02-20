// SimpleProxyMenuBar
// Created with assistance from Claude (https://claude.ai) by Anthropic.
// MIT License — see LICENSE file for details.

import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var proxyChecker: ProxyChecker!
    var refreshTimer: Timer?
    var autoRefreshEnabled = true

    // Menu items
    let ipMenuItem          = NSMenuItem(title: "External IP: Loading...", action: #selector(copyIP), keyEquivalent: "")
    let proxyStatusMenuItem = NSMenuItem(title: "Proxy: Checking...", action: nil, keyEquivalent: "")
    let proxyDetailMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let refreshMenuItem     = NSMenuItem(title: "⟳  Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
    lazy var autoRefreshMenuItem = NSMenuItem(title: "Auto-refresh: ON", action: #selector(toggleAutoRefresh), keyEquivalent: "")
    let lastUpdatedMenuItem = NSMenuItem(title: "Last updated: —", action: nil, keyEquivalent: "")
    lazy var launchAtLoginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🔍 ..."
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        proxyChecker = ProxyChecker()

        buildMenu()
        startAutoRefresh()
        refresh()
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()

        // IP
        ipMenuItem.target = self
        ipMenuItem.toolTip = "Click to copy IP"
        menu.addItem(ipMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Proxy status
        proxyStatusMenuItem.isEnabled = false
        menu.addItem(proxyStatusMenuItem)

        proxyDetailMenuItem.isEnabled = false
        proxyDetailMenuItem.indentationLevel = 1
        menu.addItem(proxyDetailMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Last updated
        lastUpdatedMenuItem.isEnabled = false
        menu.addItem(lastUpdatedMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh
        refreshMenuItem.target = self
        menu.addItem(refreshMenuItem)

        autoRefreshMenuItem.target = self
        menu.addItem(autoRefreshMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences submenu
        let prefsMenu = NSMenu()
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        prefsMenu.addItem(launchAtLoginMenuItem)

        let prefsItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefsItem.submenu = prefsMenu
        menu.addItem(prefsItem)

        // Help submenu
        let helpMenu = NSMenu()
        let githubItem = NSMenuItem(title: "GitHub: baldwinsung/SimpleProxyMenuBar", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        helpMenu.addItem(githubItem)

        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Refresh

    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    @objc func refresh() {
        DispatchQueue.main.async {
            self.statusItem.button?.title = "🔄"
            self.ipMenuItem.title = "📡 External IP: Refreshing..."
        }
        proxyChecker.check { [weak self] result in
            DispatchQueue.main.async {
                self?.updateUI(with: result)
            }
        }
    }

    @objc func manualRefresh() { refresh() }

    @objc func toggleAutoRefresh() {
        autoRefreshEnabled.toggle()
        if autoRefreshEnabled {
            startAutoRefresh()
            autoRefreshMenuItem.title = "Auto-refresh: ON"
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            autoRefreshMenuItem.title = "Auto-refresh: OFF"
        }
    }

    // MARK: - Copy IP

    @objc func copyIP() {
        guard let ip = proxyChecker.lastExternalIP, !ip.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)

        let original = statusItem.button?.title
        statusItem.button?.title = "✅ Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.statusItem.button?.title = original ?? ip
        }
    }

    // MARK: - Update UI

    func updateUI(with result: ProxyResult) {
        let ip   = result.externalIP ?? "Unavailable"
        let icon = result.isProxyActive ? "🛡️" : "🌐"
        statusItem.button?.title = "\(icon) \(ip)"

        ipMenuItem.title = "📡 External IP: \(ip)"
        if let hostname = result.hostname, hostname != ip {
            ipMenuItem.toolTip = hostname
        }

        if result.isProxyActive {
            proxyStatusMenuItem.title = "🟢 Proxy Active"
            proxyDetailMenuItem.title = result.proxyDetail ?? ""
            proxyDetailMenuItem.isHidden = false
        } else {
            proxyStatusMenuItem.title = "⚪ No Proxy Configured"
            proxyDetailMenuItem.isHidden = true
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        lastUpdatedMenuItem.title = "Last updated: \(formatter.string(from: Date()))"
    }

    // MARK: - Launch at Login

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback: check Login Items via osascript
            let result = shell("""
                osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null
            """)
            return result.contains("SimpleProxyMenuBar")
        }
    }

    @objc func toggleLaunchAtLogin() {
        let enable = launchAtLoginMenuItem.state == .off
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginMenuItem.state = enable ? .on : .off
            } catch {
                showAlert("Launch at Login", message: "Could not update Login Items:\n\(error.localizedDescription)")
            }
        } else {
            // Fallback for macOS 12
            let appPath = Bundle.main.bundlePath
            let action  = enable ? "make login item at end with properties {path:\"\(appPath)\", hidden:false}"
                                 : "delete (every login item whose name is \"SimpleProxyMenuBar\")"
            shell("osascript -e 'tell application \"System Events\" to \(action)' 2>/dev/null")
            launchAtLoginMenuItem.state = enable ? .on : .off
        }
    }

    // MARK: - Help

    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/baldwinsung/SimpleProxyMenuBar") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func shell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments  = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.runModal()
    }
}
