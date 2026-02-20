// SimpleProxyMenuBar
// Created with assistance from Claude (https://claude.ai) by Anthropic.
// MIT License — see LICENSE file for details.

import Foundation

struct ProxyResult {
    var externalIP: String?
    var hostname: String?
    var isProxyActive: Bool
    var proxyDetail: String?
}

class ProxyChecker {
    var lastExternalIP: String?

    func check(completion: @escaping (ProxyResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let proxyInfo = self.getNetworkSetupProxyInfo()
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
                proxyDetail: proxyInfo.detail
            ))
        }
    }

    // MARK: - Proxy Detection via networksetup

    private struct SystemProxyInfo {
        var isActive: Bool
        var detail: String?
    }

    /// Mirrors this shell logic:
    ///   services=$(networksetup -listallnetworkservices | tail -n +2)
    ///   while IFS= read -r svc; do
    ///       networksetup -getautoproxyurl "$svc"
    ///       networksetup -getwebproxy "$svc"
    ///       networksetup -getsecurewebproxy "$svc"
    ///       networksetup -getsocksfirewallproxy "$svc"
    ///   done <<< "$services"
    private func getNetworkSetupProxyInfo() -> SystemProxyInfo {
        // Get all network services (skip the first header line)
        let servicesOutput = shell("/usr/sbin/networksetup -listallnetworkservices")
        let services = servicesOutput
            .components(separatedBy: "\n")
            .dropFirst()                          // drop "An asterisk (*) denotes..." header
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }

        for svc in services {
            // PAC / Auto proxy URL
            let pac = shell("/usr/sbin/networksetup -getautoproxyurl \"\(svc)\"")
            if isEnabled(pac), let url = extractValue(pac, key: "URL") {
                return SystemProxyInfo(isActive: true, detail: "PAC [\(svc)]: \(url)")
            }

            // HTTP proxy
            let http = shell("/usr/sbin/networksetup -getwebproxy \"\(svc)\"")
            if isEnabled(http), let server = extractValue(http, key: "Server"), !server.isEmpty {
                let port = extractValue(http, key: "Port") ?? ""
                return SystemProxyInfo(isActive: true, detail: "HTTP [\(svc)]: \(server):\(port)")
            }

            // HTTPS proxy
            let https = shell("/usr/sbin/networksetup -getsecurewebproxy \"\(svc)\"")
            if isEnabled(https), let server = extractValue(https, key: "Server"), !server.isEmpty {
                let port = extractValue(https, key: "Port") ?? ""
                return SystemProxyInfo(isActive: true, detail: "HTTPS [\(svc)]: \(server):\(port)")
            }

            // SOCKS proxy
            let socks = shell("/usr/sbin/networksetup -getsocksfirewallproxy \"\(svc)\"")
            if isEnabled(socks), let server = extractValue(socks, key: "Server"), !server.isEmpty {
                let port = extractValue(socks, key: "Port") ?? ""
                return SystemProxyInfo(isActive: true, detail: "SOCKS [\(svc)]: \(server):\(port)")
            }
        }

        return SystemProxyInfo(isActive: false, detail: nil)
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
