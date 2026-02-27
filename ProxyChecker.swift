// SimpleProxyMenuBar
// Created with assistance from Claude (https://claude.ai) by Anthropic.
// MIT License — see LICENSE file for details.

import Foundation

struct ProxyServerInfo {
    var type: String           // "HTTP", "HTTPS", "SOCKS", "PAC"
    var networkService: String
    var configuredHost: String // hostname (or full URL for PAC)
    var port: String           // empty for PAC
    var resolvedIP: String?
    var ttl: Int?
    var ping: Int?         // round-trip time in ms, nil if unreachable
    var isEnabled: Bool
}

struct ProxyResult {
    var externalIP: String?
    var hostname: String?
    var isProxyActive: Bool
    var proxyDetail: String?
    var proxyServers: [ProxyServerInfo]
}

class ProxyChecker {
    var lastExternalIP: String?

    func check(completion: @escaping (ProxyResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (proxyInfo, proxyServers) = self.getProxyInfo()
            let ip = self.fetchExternalIP()
            self.lastExternalIP = ip

            var hostname: String?
            if let ip = ip {
                hostname = self.reverseDNS(ip: ip)
            }

            completion(ProxyResult(
                externalIP: ip,
                hostname: hostname,
                isProxyActive: proxyInfo.isActive,
                proxyDetail: proxyInfo.detail,
                proxyServers: proxyServers
            ))
        }
    }

    // MARK: - Proxy Detection via networksetup

    private struct SystemProxyInfo {
        var isActive: Bool
        var detail: String?
    }

    /// Queries all network services for every proxy type, collects configured servers,
    /// resolves each hostname to an IP with DNS TTL, and returns the first active proxy
    /// for legacy status display alongside the full server list.
    private func getProxyInfo() -> (SystemProxyInfo, [ProxyServerInfo]) {
        let servicesOutput = shell("/usr/sbin/networksetup -listallnetworkservices")
        let services = servicesOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }

        var firstActive = SystemProxyInfo(isActive: false, detail: nil)
        var servers: [ProxyServerInfo] = []

        for svc in services {
            // PAC / Auto proxy URL — fetch the file and extract proxy servers from it
            let pac = shell("/usr/sbin/networksetup -getautoproxyurl \"\(svc)\"")
            if let url = extractValue(pac, key: "URL"), !url.isEmpty, url != "(null)" {
                let enabled = isEnabled(pac)
                if enabled && !firstActive.isActive {
                    firstActive = SystemProxyInfo(isActive: true, detail: "PAC [\(svc)]: \(url)")
                }
                let pacProxies = fetchAndParsePAC(url: url)
                if pacProxies.isEmpty {
                    // PAC unreachable or no PROXY directives — fall back to showing the PAC server
                    let host = extractHostFromURL(url)
                    let (ip, ttl) = host.map { resolveWithTTL($0) } ?? (nil, nil)
                    let pingMs = pingHost(ip ?? host ?? url)
                    servers.append(ProxyServerInfo(type: "PAC", networkService: svc,
                        configuredHost: url, port: "", resolvedIP: ip, ttl: ttl, ping: pingMs, isEnabled: enabled))
                } else {
                    for proxy in pacProxies {
                        let (ip, ttl) = resolveWithTTL(proxy.host)
                        let pingMs = pingHost(ip ?? proxy.host)
                        servers.append(ProxyServerInfo(type: proxy.type, networkService: svc,
                            configuredHost: proxy.host, port: proxy.port,
                            resolvedIP: ip, ttl: ttl, ping: pingMs, isEnabled: enabled))
                    }
                }
            }

            // HTTP proxy
            let http = shell("/usr/sbin/networksetup -getwebproxy \"\(svc)\"")
            if let server = extractValue(http, key: "Server"), !server.isEmpty {
                let port = extractValue(http, key: "Port") ?? ""
                let enabled = isEnabled(http)
                if enabled && !firstActive.isActive {
                    firstActive = SystemProxyInfo(isActive: true, detail: "HTTP [\(svc)]: \(server):\(port)")
                }
                let (ip, ttl) = resolveWithTTL(server)
                let pingMs = pingHost(ip ?? server)
                servers.append(ProxyServerInfo(type: "HTTP", networkService: svc,
                    configuredHost: server, port: port, resolvedIP: ip, ttl: ttl, ping: pingMs, isEnabled: enabled))
            }

            // HTTPS proxy
            let https = shell("/usr/sbin/networksetup -getsecurewebproxy \"\(svc)\"")
            if let server = extractValue(https, key: "Server"), !server.isEmpty {
                let port = extractValue(https, key: "Port") ?? ""
                let enabled = isEnabled(https)
                if enabled && !firstActive.isActive {
                    firstActive = SystemProxyInfo(isActive: true, detail: "HTTPS [\(svc)]: \(server):\(port)")
                }
                let (ip, ttl) = resolveWithTTL(server)
                let pingMs = pingHost(ip ?? server)
                servers.append(ProxyServerInfo(type: "HTTPS", networkService: svc,
                    configuredHost: server, port: port, resolvedIP: ip, ttl: ttl, ping: pingMs, isEnabled: enabled))
            }

            // SOCKS proxy
            let socks = shell("/usr/sbin/networksetup -getsocksfirewallproxy \"\(svc)\"")
            if let server = extractValue(socks, key: "Server"), !server.isEmpty {
                let port = extractValue(socks, key: "Port") ?? ""
                let enabled = isEnabled(socks)
                if enabled && !firstActive.isActive {
                    firstActive = SystemProxyInfo(isActive: true, detail: "SOCKS [\(svc)]: \(server):\(port)")
                }
                let (ip, ttl) = resolveWithTTL(server)
                let pingMs = pingHost(ip ?? server)
                servers.append(ProxyServerInfo(type: "SOCKS", networkService: svc,
                    configuredHost: server, port: port, resolvedIP: ip, ttl: ttl, ping: pingMs, isEnabled: enabled))
            }
        }

        // Deduplicate by type + host + port across all network services
        var seen = Set<String>()
        let unique = servers.filter { s in
            seen.insert("\(s.type)|\(s.configuredHost.lowercased())|\(s.port)").inserted
        }

        return (firstActive, unique)
    }

    /// Extracts the host component from a URL string.
    private func extractHostFromURL(_ urlString: String) -> String? {
        return URL(string: urlString)?.host
    }

    /// Fetches a PAC file via curl and extracts unique proxy directives via regex.
    /// Handles `PROXY host:port`, `SOCKS host:port`, `SOCKS5 host:port`, `HTTPS host:port`.
    /// Uses --noproxy to avoid a circular dependency on the proxy being configured.
    private func fetchAndParsePAC(url: String) -> [(type: String, host: String, port: String)] {
        // Escape single quotes in the URL for safe shell embedding
        let safeURL = url.replacingOccurrences(of: "'", with: "'\\''")
        let content = shell("curl -sfL --max-time 6 --noproxy '*' '\(safeURL)' 2>/dev/null")
        guard !content.isEmpty else { return [] }

        // Match: PROXY|SOCKS|SOCKS5|HTTPS followed by host:port
        let pattern = #"(?i)\b(PROXY|SOCKS5?|HTTPS)\s+([a-zA-Z0-9][a-zA-Z0-9.\-]*):(\d{1,5})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var results: [(type: String, host: String, port: String)] = []
        for match in matches {
            let type_ = ns.substring(with: match.range(at: 1)).uppercased()
            let host  = ns.substring(with: match.range(at: 2))
            let port  = ns.substring(with: match.range(at: 3))
            let key   = "\(type_)|\(host.lowercased())|\(port)"
            if seen.insert(key).inserted {
                results.append((type: type_, host: host, port: port))
            }
        }
        return results
    }

    /// Resolves a hostname to an IP and DNS TTL.
    /// Uses dscacheutil (macOS mDNSResponder) as the primary source — it respects
    /// VPN/split-horizon DNS and reports the actual cached TTL.
    /// Falls back to dig for hosts not yet in the system cache.
    /// Returns (hostname, nil) immediately if the input is already an IPv4 address.
    private func resolveWithTTL(_ hostname: String) -> (ip: String?, ttl: Int?) {
        let ipv4Pattern = "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$"
        if hostname.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return (hostname, nil)
        }
        let safeHost = hostname.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !safeHost.isEmpty else { return (nil, nil) }

        // Primary: dscacheutil queries mDNSResponder — same resolver the OS uses
        let cache = shell("dscacheutil -q host -a name \(safeHost) 2>/dev/null")
        if !cache.isEmpty {
            var ip: String?
            var ttl: Int?
            for line in cache.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("ip_address: ") {
                    ip = String(t.dropFirst("ip_address: ".count))
                } else if t.hasPrefix("ttl: ") {
                    ttl = Int(t.dropFirst("ttl: ".count))
                }
            }
            if let ip = ip { return (ip, ttl) }
        }

        // Fallback: dig (direct DNS query, bypasses system cache)
        let dig = shell("dig +noall +answer \(safeHost) A 2>/dev/null")
        for line in dig.components(separatedBy: "\n") {
            let parts = line.split(omittingEmptySubsequences: true) { $0.isWhitespace }.map(String.init)
            if parts.count >= 5 && parts[3] == "A" {
                return (parts[4], Int(parts[1]))
            }
        }
        return (nil, nil)
    }

    /// Pings a host once and returns the round-trip time in ms, or nil if unreachable.
    private func pingHost(_ host: String) -> Int? {
        let safeHost = host.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !safeHost.isEmpty else { return nil }
        let output = shell("ping -c 1 -t 1 \(safeHost) 2>/dev/null")
        for line in output.components(separatedBy: "\n") {
            if let timeRange = line.range(of: "time=", options: .caseInsensitive) {
                let after = String(line[timeRange.upperBound...])
                let numStr = String(after.prefix(while: { $0.isNumber || $0 == "." }))
                if let ms = Double(numStr) { return Int(ms.rounded()) }
            }
        }
        return nil
    }

    /// Returns true if the networksetup output contains "Enabled: Yes"
    private func isEnabled(_ output: String) -> Bool {
        return output.range(of: "Enabled: Yes", options: .caseInsensitive) != nil
    }

    /// Extracts a value from lines like "Server: 127.0.0.1" or "URL: http://..."
    private func extractValue(_ output: String, key: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefix = "\(key): "
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Shell Helper

    @discardableResult
    private func shell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - External IP Fetch

    private func fetchExternalIP() -> String? {
        guard let url = URL(string: "https://myip.baldwinsung.com") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("ProxyMenuBar/1.0", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result = json["ip"] as? String
            }
            if result == nil {
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let text = text, !text.isEmpty { result = text }
            }
        }.resume()

        semaphore.wait()
        return result?.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Reverse DNS

    private func reverseDNS(ip: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var res: UnsafeMutablePointer<addrinfo>?

        guard getaddrinfo(ip, nil, &hints, &res) == 0, let info = res else { return nil }
        defer { freeaddrinfo(res) }

        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let ret = getnameinfo(
            info.pointee.ai_addr,
            info.pointee.ai_addrlen,
            &hostBuffer, socklen_t(NI_MAXHOST),
            nil, 0,
            NI_NAMEREQD
        )
        guard ret == 0 else { return nil }
        return String(cString: hostBuffer)
    }
}
