import Foundation
import SystemConfiguration
import Darwin
import Observation

/// Gathers the Network dashboard's data: interfaces, DNS, public IP, default
/// route, hardware ports, and services.
@MainActor
@Observable
final class NetworkInfoProvider {
    var interfaces: [NetworkInterface] = []
    var dnsServers: [String] = []
    var hardwarePorts: [HardwarePort] = []
    var networkServices: [String] = []
    var publicIP = "Unavailable"
    var publicIPDetail = "No response"
    var defaultGateway = "Unavailable"
    var primaryInterface = "Unavailable"
    var benchmarkSummary = "Not run"
    var isRefreshing = false
    var isBenchmarking = false

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadInterfaces() }
            group.addTask { await self.loadDNS() }
            group.addTask { await self.loadPublicIP() }
            group.addTask { await self.loadDefaultRoute() }
            group.addTask { await self.loadHardwarePorts() }
            group.addTask { await self.loadNetworkServices() }
        }
    }

    func runBenchmark() async {
        isBenchmarking = true
        defer { isBenchmarking = false }

        guard let path = ProcessRunner.findExecutable(["/usr/bin/networkQuality"]) else {
            benchmarkSummary = "networkQuality is unavailable on this Mac."
            return
        }

        do {
            let output = try await ProcessRunner.runCapture(path, ["-v"])
            benchmarkSummary = Self.parseBenchmark(from: output)
        } catch {
            benchmarkSummary = "Benchmark failed: \(error.localizedDescription)"
        }
    }

    /// A plain-text snapshot for the clipboard or a saved report.
    var report: String {
        var lines = [
            "Control Panel — network report",
            "Generated: \(Date.now.formatted(date: .abbreviated, time: .standard))",
            "",
            "Public IP:       \(publicIP)  (\(publicIPDetail))",
            "Default gateway: \(defaultGateway)",
            "Primary iface:   \(primaryInterface)"
        ]

        if !interfaces.isEmpty {
            lines.append("")
            lines.append("Interfaces")
            for interface in interfaces {
                lines.append("  \(interface.name)  \(interface.family)  \(interface.address)")
            }
        }

        if !dnsServers.isEmpty {
            lines.append("")
            lines.append("DNS servers")
            for server in dnsServers {
                lines.append("  \(server)")
            }
        }

        if !hardwarePorts.isEmpty {
            lines.append("")
            lines.append("Hardware ports")
            for port in hardwarePorts {
                lines.append("  \(port.name)  \(port.device)  \(port.address)")
            }
        }

        if benchmarkSummary != "Not run" {
            lines.append("")
            lines.append("Benchmark")
            lines.append(benchmarkSummary)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Loading

    private func loadInterfaces() async {
        var collected: [NetworkInterface] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return }
        defer { freeifaddrs(first) }

        var seen = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }

            guard let addressPointer = current.ifa_addr else { continue }
            let family = Int32(addressPointer.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            let name = String(cString: current.ifa_name)
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let address = String(cString: hostBuffer)
            let kind = family == AF_INET ? "IPv4" : "IPv6"
            let key = "\(name)-\(kind)-\(address)"
            guard seen.insert(key).inserted else { continue }

            collected.append(NetworkInterface(name: name, address: address, family: kind))
        }

        interfaces = collected.sorted {
            $0.name == $1.name ? $0.address < $1.address : $0.name < $1.name
        }
    }

    private func loadDNS() async {
        var servers: [String] = []

        if let store = SCDynamicStoreCreate(nil, "ControlPanelDNS" as CFString, nil, nil),
           let dictionary = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let addresses = dictionary["ServerAddresses"] as? [String] {
            servers = addresses
        }

        if servers.isEmpty,
           let scutil = ProcessRunner.findExecutable(["/usr/sbin/scutil"]),
           let output = try? await ProcessRunner.runCapture(scutil, ["--dns"]) {
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("nameserver") else { continue }
                let value = valueAfterColon(in: trimmed)
                if !value.isEmpty {
                    servers.append(value)
                }
            }
        }

        dnsServers = Array(Set(servers)).sorted()
    }

    private func loadPublicIP() async {
        // URLSession first; fall back to curl when something in the network
        // path blocks the app's own requests.
        for service in Self.publicIPServices {
            guard let url = URL(string: service) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8

            if let (data, _) = try? await URLSession.shared.data(for: request),
               let candidate = Self.validatedIPAddress(String(decoding: data, as: UTF8.self)) {
                publicIP = candidate
                publicIPDetail = url.host() ?? service
                return
            }
        }

        if let curl = ProcessRunner.findExecutable(["/usr/bin/curl"]) {
            for service in Self.publicIPServices {
                guard let output = try? await ProcessRunner.runCapture(
                    curl, ["-fsSL", "--max-time", "8", service]
                ), let candidate = Self.validatedIPAddress(output) else { continue }
                publicIP = candidate
                publicIPDetail = "via curl · \(URL(string: service)?.host() ?? service)"
                return
            }
        }

        publicIP = "Unavailable"
        publicIPDetail = "External lookup failed"
    }

    private func loadDefaultRoute() async {
        guard let route = ProcessRunner.findExecutable(["/sbin/route"]),
              let output = try? await ProcessRunner.runCapture(route, ["-n", "get", "default"]) else {
            defaultGateway = "Unavailable"
            primaryInterface = "Unavailable"
            return
        }

        var gateway = "Unavailable"
        var interface = "Unavailable"

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                gateway = valueAfterColon(in: trimmed)
            } else if trimmed.hasPrefix("interface:") {
                interface = valueAfterColon(in: trimmed)
            }
        }

        defaultGateway = gateway
        primaryInterface = interface
    }

    private func loadHardwarePorts() async {
        guard let networksetup = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]),
              let output = try? await ProcessRunner.runCapture(networksetup, ["-listallhardwareports"]) else {
            hardwarePorts = []
            return
        }

        hardwarePorts = output
            .components(separatedBy: "\n\n")
            .compactMap { block in
                var name = ""
                var device = ""
                var address = ""

                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Hardware Port:") {
                        name = valueAfterColon(in: trimmed)
                    } else if trimmed.hasPrefix("Device:") {
                        device = valueAfterColon(in: trimmed)
                    } else if trimmed.hasPrefix("Ethernet Address:") {
                        address = valueAfterColon(in: trimmed)
                    }
                }

                guard !name.isEmpty, !device.isEmpty else { return nil }
                return HardwarePort(name: name, device: device, address: address)
            }
    }

    private func loadNetworkServices() async {
        guard let networksetup = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]),
              let output = try? await ProcessRunner.runCapture(networksetup, ["-listallnetworkservices"]) else {
            networkServices = []
            return
        }

        networkServices = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
    }

    // MARK: Parsing

    private static let publicIPServices = [
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com"
    ]

    private static func parseBenchmark(from output: String) -> String {
        let interesting = output
            .split(separator: "\n")
            .map(String.init)
            .filter {
                $0.contains("Uplink capacity:")
                    || $0.contains("Downlink capacity:")
                    || $0.contains("Responsiveness:")
                    || $0.contains("Interface:")
            }
        return interesting.isEmpty ? "Benchmark completed." : interesting.joined(separator: "\n")
    }

    private static func validatedIPAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var ipv4 = in_addr()
        if trimmed.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return trimmed
        }

        var ipv6 = in6_addr()
        if trimmed.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            return trimmed
        }

        return nil
    }
}
