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
    let ipMenuItem               = NSMenuItem(title: "External IP: Loading...", action: #selector(copyIP), keyEquivalent: "")
    let proxyStatusMenuItem      = NSMenuItem(title: "Proxy: Checking...", action: nil, keyEquivalent: "")
    let proxyDetailMenuItem      = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let refreshMenuItem          = NSMenuItem(title: "⟳  Refresh", action: #selector(manualRefresh), keyEquivalent: "r")
    lazy var autoRefreshMenuItem = NSMenuItem(title: "Auto-refresh: ON", action: #selector(toggleAutoRefresh), keyEquivalent: "")
    let lastUpdatedMenuItem      = NSMenuItem(title: "Last updated: —", action: nil, keyEquivalent: "")
    lazy var launchAtLoginMenuItem   = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    lazy var proxyServersMenuItem    = NSMenuItem(title: "Proxy Servers", action: nil, keyEquivalent: "")
    lazy var pacEnabledMenuItem      = NSMenuItem(title: "Enable Auto Proxy", action: #selector(togglePAC), keyEquivalent: "")
    lazy var pacURLMenuItem          = NSMenuItem(title: "Set PAC URL...", action: #selector(setPACURL), keyEquivalent: "")
    lazy var pacCurrentURLMenuItem   = NSMenuItem(title: "PAC URL: —", action: nil, keyEquivalent: "")

    // UserDefaults keys
    let kPACURL = "pac_url"

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

        // Proxy servers (dynamic submenu, rebuilt on each refresh)
        let placeholderMenu = NSMenu()
        let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        placeholderMenu.addItem(loadingItem)
        proxyServersMenuItem.submenu = placeholderMenu
        menu.addItem(proxyServersMenuItem)

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

        // Proxy Configuration submenu
        menu.addItem(buildProxyConfigMenu())

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
        let githubItem = NSMenuItem(title: "GitHub: baldwinsung", action: #selector(openGitHub), keyEquivalent: "")
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

    func buildProxyConfigMenu() -> NSMenuItem {
        let proxyMenu = NSMenu()

        // Enable/disable toggle — reflect current state
        pacEnabledMenuItem.target = self
        pacEnabledMenuItem.state = isPACEnabled() ? .on : .off
        proxyMenu.addItem(pacEnabledMenuItem)

        proxyMenu.addItem(NSMenuItem.separator())

        // Current PAC URL (read-only display)
        pacCurrentURLMenuItem.isEnabled = false
        updatePACURLMenuItem()
        proxyMenu.addItem(pacCurrentURLMenuItem)

        // Set PAC URL
        pacURLMenuItem.target = self
        proxyMenu.addItem(pacURLMenuItem)

        let proxyConfigItem = NSMenuItem(title: "Proxy Configuration", action: nil, keyEquivalent: "")
        proxyConfigItem.submenu = proxyMenu
        return proxyConfigItem
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

        updateProxyServersMenu(result.proxyServers)

        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        lastUpdatedMenuItem.title = "Last updated: \(formatter.string(from: Date()))"
    }

    func updateProxyServersMenu(_ servers: [ProxyServerInfo]) {
        let submenu = NSMenu()

        guard !servers.isEmpty else {
            let item = NSMenuItem(title: "No proxy servers configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            proxyServersMenuItem.title = "Proxy Servers (0 active)"
            proxyServersMenuItem.submenu = submenu
            return
        }

        let enabledCount = servers.filter { $0.isEnabled }.count

        for server in servers {
            let stateIcon = server.isEnabled ? "🟢" : "⚪"

            // Line 1: type, service, configured host:port (or URL for PAC)
            let displayHost: String
            if server.type == "PAC" {
                let url = server.configuredHost
                displayHost = url.count > 45 ? String(url.prefix(42)) + "..." : url
            } else {
                let portSuffix = server.port.isEmpty ? "" : ":\(server.port)"
                displayHost = "\(server.configuredHost)\(portSuffix)"
            }

            let mainItem = NSMenuItem(
                title: "\(stateIcon) \(server.type) [\(server.networkService)]: \(displayHost)",
                action: nil, keyEquivalent: ""
            )
            mainItem.isEnabled = false
            submenu.addItem(mainItem)

            // Line 2 (indented): resolved IP and TTL
            var details: [String] = []
            if let ip = server.resolvedIP {
                details.append("IP: \(ip)")
            }
            if let ttl = server.ttl {
                details.append("TTL: \(ttl)s")
            }
            if let ping = server.ping {
                details.append("ping: \(ping)ms")
            }
            if !details.isEmpty {
                let detailItem = NSMenuItem(title: details.joined(separator: "  |  "), action: nil, keyEquivalent: "")
                detailItem.isEnabled = false
                detailItem.indentationLevel = 1
                submenu.addItem(detailItem)
            }

            submenu.addItem(NSMenuItem.separator())
        }

        // Remove trailing separator
        if submenu.items.last?.isSeparatorItem == true {
            submenu.removeItem(at: submenu.items.count - 1)
        }

        proxyServersMenuItem.title = "Proxy Servers (\(enabledCount) active)"
        proxyServersMenuItem.submenu = submenu
    }

    // MARK: - PAC Proxy Configuration

    /// Returns true if auto proxy (PAC) is enabled on any network service
    func isPACEnabled() -> Bool {
        let services = getNetworkServices()
        for svc in services {
            let out = shell("/usr/sbin/networksetup -getautoproxyurl \"\(svc)\"")
            if out.range(of: "Enabled: Yes", options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }

    @objc func togglePAC() {
        let enable = pacEnabledMenuItem.state == .off

        // Require a PAC URL to be set before enabling
        if enable {
            let savedURL = UserDefaults.standard.string(forKey: kPACURL) ?? ""
            if savedURL.isEmpty {
                showAlert("No PAC URL Set", message: "Please set a PAC URL first using \"Set PAC URL...\"")
                return
            }
            applyPACToAllServices(url: savedURL, enabled: true)
        } else {
            applyPACToAllServices(url: nil, enabled: false)
        }

        pacEnabledMenuItem.state = enable ? .on : .off
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.restartApp() }
    }

    @objc func setPACURL() {
        let alert = NSAlert()
        alert.messageText     = "Set PAC URL"
        alert.informativeText = "Enter the URL of your proxy auto-config file:"
        alert.addButton(withTitle: "Save & Enable")
        alert.addButton(withTitle: "Save Only")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        input.placeholderString = "https://example.com/proxy.pac"
        input.stringValue = UserDefaults.standard.string(forKey: kPACURL) ?? ""
        alert.accessoryView = input

        // Focus the text field
        alert.window.initialFirstResponder = input

        let response = alert.runModal()

        let url = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch response {
        case .alertFirstButtonReturn:  // Save & Enable
            guard !url.isEmpty else {
                showAlert("Invalid URL", message: "Please enter a valid PAC URL.")
                return
            }
            UserDefaults.standard.set(url, forKey: kPACURL)
            updatePACURLMenuItem()
            applyPACToAllServices(url: url, enabled: true)
            pacEnabledMenuItem.state = .on
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.restartApp() }

        case .alertSecondButtonReturn: // Save Only
            guard !url.isEmpty else { return }
            UserDefaults.standard.set(url, forKey: kPACURL)
            updatePACURLMenuItem()

        default: // Cancel
            break
        }
    }

    /// Apply (or disable) the PAC URL across all network services
    func applyPACToAllServices(url: String?, enabled: Bool) {
        let services = getNetworkServices()
        for svc in services {
            if enabled, let url = url {
                shell("/usr/sbin/networksetup -setautoproxyurl \"\(svc)\" \"\(url)\"")
                shell("/usr/sbin/networksetup -setautoproxystate \"\(svc)\" on")
            } else {
                shell("/usr/sbin/networksetup -setautoproxystate \"\(svc)\" off")
            }
        }
    }

    func getNetworkServices() -> [String] {
        let output = shell("/usr/sbin/networksetup -listallnetworkservices")
        return output
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    func updatePACURLMenuItem() {
        let url = UserDefaults.standard.string(forKey: kPACURL) ?? ""
        if url.isEmpty {
            pacCurrentURLMenuItem.title = "PAC URL: not set"
        } else {
            // Truncate long URLs for display
            let display = url.count > 50 ? String(url.prefix(47)) + "..." : url
            pacCurrentURLMenuItem.title = "PAC URL: \(display)"
            pacCurrentURLMenuItem.toolTip = url
        }
    }

    // MARK: - Launch at Login

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let result = shell("osascript -e 'tell application \"System Events\" to get the name of every login item' 2>/dev/null")
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
                showAlert("Open at Login", message: "Could not update Login Items:\n\(error.localizedDescription)")
            }
        } else {
            let appPath = Bundle.main.bundlePath
            let action  = enable ? "make login item at end with properties {path:\"\(appPath)\", hidden:false}"
                                 : "delete (every login item whose name is \"SimpleProxyMenuBar\")"
            shell("osascript -e 'tell application \"System Events\" to \(action)' 2>/dev/null")
            launchAtLoginMenuItem.state = enable ? .on : .off
        }
    }

    // MARK: - Help

    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/baldwinsung") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\""]
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        try? task.run()
        // Do NOT call waitUntilExit — detach so it survives after terminate
        NSApp.terminate(nil)
    }

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
