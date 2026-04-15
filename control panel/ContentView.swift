import SwiftUI
import AppKit
import SystemConfiguration
import Darwin
import Combine

enum SidebarDestination: Hashable, Identifiable {
    case generalAbout
    case performance
    case storage
    case displays
    case sound
    case battery
    case privacySecurity
    case networkDashboard
    case deviceScanner
    case adapterConfig
    case networkQuality
    case ping
    case traceroute
    case dnsLookup
    case portCheck
    case httpInspector
    case wifi
    case printers
    case developerTools
    case backupRecovery
    case system

    var id: String { title }

    var title: String {
        switch self {
        case .generalAbout: "General"
        case .performance: "Performance"
        case .storage: "Storage"
        case .displays: "Displays"
        case .sound: "Sound"
        case .battery: "Battery & Power"
        case .privacySecurity: "Privacy & Security"
        case .networkDashboard: "Network"
        case .deviceScanner: "Device Scanner"
        case .adapterConfig: "IP & DNS"
        case .networkQuality: "Network Quality"
        case .ping: "Ping"
        case .traceroute: "Path Diagnostics"
        case .dnsLookup: "DNS"
        case .portCheck: "Port Check"
        case .httpInspector: "HTTP Inspector"
        case .wifi: "Wi-Fi"
        case .printers: "Printers"
        case .developerTools: "Developer Tools"
        case .backupRecovery: "Backup & Recovery"
        case .system: "System"
        }
    }

    var icon: String {
        switch self {
        case .generalAbout: "macwindow"
        case .performance: "waveform.path.ecg"
        case .storage: "internaldrive"
        case .displays: "display.2"
        case .sound: "speaker.wave.2"
        case .battery: "battery.100"
        case .privacySecurity: "lock.shield"
        case .networkDashboard: "network"
        case .deviceScanner: "dot.radiowaves.up.forward"
        case .adapterConfig: "slider.horizontal.3"
        case .networkQuality: "speedometer"
        case .ping: "dot.radiowaves.left.and.right"
        case .traceroute: "arrow.triangle.branch"
        case .dnsLookup: "globe"
        case .portCheck: "firewall"
        case .httpInspector: "network.badge.shield.half.filled"
        case .wifi: "wifi"
        case .printers: "printer"
        case .developerTools: "hammer"
        case .backupRecovery: "externaldrive.badge.timemachine"
        case .system: "gearshape.2"
        }
    }

    var section: String {
        switch self {
        case .generalAbout, .performance, .storage, .displays, .sound, .battery, .privacySecurity, .system:
            "Core System"
        case .networkDashboard, .deviceScanner, .adapterConfig, .networkQuality, .ping, .traceroute, .dnsLookup, .portCheck, .httpInspector, .wifi:
            "Network"
        case .printers:
            "Devices"
        case .developerTools, .backupRecovery:
            "Advanced"
        }
    }

    var summary: String {
        switch self {
        case .generalAbout: "About this Mac, version, model, serial, uptime."
        case .performance: "CPU, memory, disk, and top processes."
        case .storage: "Storage usage and folder breakdown."
        case .displays: "Displays, GPUs, and current display summary."
        case .sound: "Audio devices and output/input summary."
        case .battery: "Battery health, capacity, and power status."
        case .privacySecurity: "FileVault, Gatekeeper, firewall, and permissions links."
        case .networkDashboard: "Adapters, gateway, DNS, and internet status."
        case .deviceScanner: "Scan local devices by ARP and ping sweep."
        case .adapterConfig: "Set DHCP, static IP, subnet, router, and DNS."
        case .networkQuality: "Throughput and responsiveness."
        case .ping: "Latency and packet loss."
        case .traceroute: "Route, resolver, and throughput diagnostics."
        case .dnsLookup: "A, AAAA, MX, NS, TXT, and more."
        case .portCheck: "Test TCP reachability for one or more ports."
        case .httpInspector: "Fetch headers, status, and body preview."
        case .wifi: "Current radio state and scan results."
        case .printers: "Queues, test print, and raw TCP."
        case .developerTools: "Hosts file, proxies, Terminal, and Console."
        case .backupRecovery: "Time Machine status and destinations."
        case .system: "Machine and runtime information."
        }
    }
}

private let navigationItems: [SidebarDestination] = [
    .generalAbout,
    .performance,
    .storage,
    .displays,
    .sound,
    .battery,
    .privacySecurity,
    .networkDashboard,
    .deviceScanner,
    .adapterConfig,
    .networkQuality,
    .ping,
    .traceroute,
    .dnsLookup,
    .portCheck,
    .httpInspector,
    .wifi,
    .printers,
    .developerTools,
    .backupRecovery,
    .system
]

enum SidebarCategory: String, CaseIterable, Identifiable {
    case coreSystem = "Mac"
    case network = "Network"
    case devices = "Devices"
    case advanced = "Utilities"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .coreSystem: "macwindow"
        case .network: "network"
        case .devices: "printer"
        case .advanced: "hammer"
        }
    }

    var summary: String {
        switch self {
        case .coreSystem: "Mac information, performance, storage, displays, and privacy."
        case .network: "Connection status, Wi-Fi, DNS, diagnostics, and IP tools."
        case .devices: "Printers and device-specific controls."
        case .advanced: "Backup, developer, and maintenance tools."
        }
    }

    var featuredDestinations: [SidebarDestination] {
        switch self {
        case .coreSystem:
            [.generalAbout, .performance, .privacySecurity]
        case .network:
            [.networkDashboard, .adapterConfig, .wifi]
        case .devices:
            [.printers]
        case .advanced:
            [.backupRecovery, .developerTools]
        }
    }

    var secondaryDestinations: [SidebarDestination] {
        destinations.filter { !featuredDestinations.contains($0) }
    }

    var destinations: [SidebarDestination] {
        switch self {
        case .coreSystem:
            [.generalAbout, .performance, .storage, .displays, .sound, .battery, .privacySecurity, .system]
        case .network:
            [.networkDashboard, .deviceScanner, .adapterConfig, .networkQuality, .ping, .traceroute, .dnsLookup, .portCheck, .httpInspector, .wifi]
        case .devices:
            [.printers]
        case .advanced:
            [.developerTools, .backupRecovery]
        }
    }
}

struct NetworkInterface: Identifiable, Hashable {
    let name: String
    let address: String
    let family: String

    var id: String { "\(name)-\(family)-\(address)" }
}

struct HardwarePort: Identifiable, Hashable {
    let name: String
    let device: String
    let address: String

    var id: String { device }
}

struct NetworkDevice: Identifiable, Hashable {
    let ipAddress: String
    let macAddress: String
    let interface: String
    let hostname: String

    var id: String { "\(ipAddress)-\(macAddress)-\(interface)" }
}

struct NetworkServiceDetails: Identifiable, Hashable {
    let serviceName: String
    let configuration: String
    let ipAddress: String
    let subnetMask: String
    let router: String
    let macAddress: String
    let dnsServers: [String]

    var id: String { serviceName }
}

@MainActor
final class NetworkInfoProvider: ObservableObject {
    @Published var interfaces = [NetworkInterface]()
    @Published var dnsServers = [String]()
    @Published var hardwarePorts = [HardwarePort]()
    @Published var networkServices = [String]()
    @Published var publicIP = "Unavailable"
    @Published var publicIPDetail = "No response"
    @Published var defaultGateway = "Unavailable"
    @Published var primaryInterface = "Unavailable"
    @Published var benchmarkSummary = "Not run"
    @Published var isRefreshing = false
    @Published var isBenchmarking = false

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

        guard let networkQualityPath = ProcessRunner.findExecutable(["/usr/bin/networkQuality"]) else {
            benchmarkSummary = "networkQuality is unavailable"
            return
        }

        do {
            let output = try await ProcessRunner.runCapture(networkQualityPath, ["-v"])
            benchmarkSummary = parseBenchmark(from: output)
        } catch {
            benchmarkSummary = "Benchmark failed: \(error.localizedDescription)"
        }
    }

    private func loadInterfaces() async {
        var interfaces = [NetworkInterface]()
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else {
            return
        }

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
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            interfaces.append(NetworkInterface(name: name, address: address, family: kind))
        }

        await MainActor.run {
            self.interfaces = interfaces.sorted {
                if $0.name == $1.name {
                    return $0.address < $1.address
                }
                return $0.name < $1.name
            }
        }
    }

    private func loadDNS() async {
        var servers = [String]()

        if let store = SCDynamicStoreCreate(nil, "ControlPanelDNS" as CFString, nil, nil),
           let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let addresses = dict["ServerAddresses"] as? [String] {
            servers = addresses
        }

        if servers.isEmpty,
           let scutilPath = ProcessRunner.findExecutable(["/usr/sbin/scutil"]),
           let output = try? ProcessRunner.runCaptureSync(scutilPath, ["--dns"]) {
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("nameserver") {
                    let parts = trimmed.split(separator: ":")
                    if let value = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                        servers.append(value)
                    }
                }
            }
        }

        await MainActor.run {
            self.dnsServers = Array(Set(servers)).sorted()
        }
    }

    private func loadPublicIP() async {
        guard let curlPath = ProcessRunner.findExecutable(["/usr/bin/curl"]) else {
            await MainActor.run {
                self.publicIP = "Unavailable"
                self.publicIPDetail = "curl is unavailable"
            }
            return
        }

        let services = [
            "https://api.ipify.org?format=text",
            "https://ifconfig.me/ip",
            "https://icanhazip.com"
        ]

        for service in services {
            do {
                let output = try await ProcessRunner.runCapture(curlPath, ["-fsSL", "--max-time", "8", service])
                if let ip = validatedIPAddress(from: output) {
                    await MainActor.run {
                        self.publicIP = ip
                        self.publicIPDetail = service
                    }
                    return
                }
            } catch {
                continue
            }
        }

        await MainActor.run {
            self.publicIP = "Unavailable"
            self.publicIPDetail = "External lookup failed"
        }
    }

    private func loadDefaultRoute() async {
        guard let routePath = ProcessRunner.findExecutable(["/sbin/route"]) else {
            return
        }

        do {
            let output = try ProcessRunner.runCaptureSync(routePath, ["-n", "get", "default"])
            var gateway = "Unavailable"
            var interface = "Unavailable"

            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("gateway:") {
                    gateway = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                }
                if trimmed.hasPrefix("interface:") {
                    interface = trimmed.replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            await MainActor.run {
                self.defaultGateway = gateway
                self.primaryInterface = interface
            }
        } catch {
            await MainActor.run {
                self.defaultGateway = "Unavailable"
                self.primaryInterface = "Unavailable"
            }
        }
    }

    private func loadHardwarePorts() async {
        guard let commandPath = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]) else {
            return
        }

        do {
            let output = try ProcessRunner.runCaptureSync(commandPath, ["-listallhardwareports"])
            let blocks = output.components(separatedBy: "\n\n")
            let ports = blocks.compactMap { block -> HardwarePort? in
                var name = ""
                var device = ""
                var address = ""

                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Hardware Port:") {
                        name = trimmed.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("Device:") {
                        device = trimmed.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("Ethernet Address:") {
                        address = trimmed.replacingOccurrences(of: "Ethernet Address:", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }

                guard !name.isEmpty, !device.isEmpty else { return nil }
                return HardwarePort(name: name, device: device, address: address)
            }

            await MainActor.run {
                self.hardwarePorts = ports
            }
        } catch {
            await MainActor.run {
                self.hardwarePorts = []
            }
        }
    }

    private func loadNetworkServices() async {
        guard let commandPath = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]) else {
            return
        }

        do {
            let output = try ProcessRunner.runCaptureSync(commandPath, ["-listallnetworkservices"])
            let services = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }

            await MainActor.run {
                self.networkServices = services
            }
        } catch {
            await MainActor.run {
                self.networkServices = []
            }
        }
    }

    private func parseBenchmark(from output: String) -> String {
        let interesting = output
            .split(separator: "\n")
            .map(String.init)
            .filter {
                $0.contains("Uplink capacity:") ||
                $0.contains("Downlink capacity:") ||
                $0.contains("Responsiveness:") ||
                $0.contains("Interface:")
            }
        return interesting.isEmpty ? "Benchmark completed" : interesting.joined(separator: "\n")
    }

    private func validatedIPAddress(from value: String) -> String? {
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

@MainActor
final class NetworkDevicesProvider: ObservableObject {
    @Published var devices: [NetworkDevice] = []
    @Published var subnetPrefix = ""
    @Published var status = "Idle"
    @Published var isScanning = false

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        status = "Discovering current subnet..."

        let prefix = await currentSubnetPrefix()
        subnetPrefix = prefix ?? ""

        status = "Collecting known devices..."
        var discovered = parseARPDevices(from: await runCommandOutput("/usr/sbin/arp", ["-a"]))

        if let prefix {
            status = "Running ping sweep on \(prefix).0/24..."
            await pingSweep(prefix: prefix)
            let refreshed = parseARPDevices(from: await runCommandOutput("/usr/sbin/arp", ["-a"]))
            discovered = refreshed
        }

        devices = discovered.sorted { $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending }
        status = devices.isEmpty ? "No devices found." : "Found \(devices.count) device(s)"
    }

    private func currentSubnetPrefix() async -> String? {
        guard let routePath = ProcessRunner.findExecutable(["/sbin/route"]) else { return nil }
        guard let routeOutput = try? ProcessRunner.runCaptureSync(routePath, ["-n", "get", "default"]) else { return nil }

        let interface = routeOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("interface:") }?
            .replacingOccurrences(of: "interface:", with: "")
            .trimmingCharacters(in: .whitespaces)

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(first) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }
            guard let interface, String(cString: current.ifa_name) == interface else { continue }
            guard let addressPointer = current.ifa_addr, Int32(addressPointer.pointee.sa_family) == AF_INET else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addressPointer, socklen_t(addressPointer.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let ipAddress = String(cString: hostBuffer)
            let components = ipAddress.split(separator: ".")
            guard components.count == 4 else { return nil }
            return components.prefix(3).joined(separator: ".")
        }

        return nil
    }

    private func pingSweep(prefix: String) async {
        guard let pingPath = ProcessRunner.findExecutable(["/sbin/ping", "/usr/sbin/ping"]) else { return }

        await withTaskGroup(of: Void.self) { group in
            for host in 1...32 {
                let ip = "\(prefix).\(host)"
                group.addTask {
                    _ = try? await ProcessRunner.runCapture(pingPath, ["-n", "-c", "1", "-W", "100", ip])
                }
            }
        }
    }

    private func parseARPDevices(from output: String) -> [NetworkDevice] {
        output
            .split(separator: "\n")
            .compactMap { line -> NetworkDevice? in
                let value = String(line)
                guard let ipStart = value.firstIndex(of: "("),
                      let ipEnd = value.firstIndex(of: ")"),
                      let atRange = value.range(of: " at "),
                      let onRange = value.range(of: " on ") else {
                    return nil
                }

                let hostname = value[..<ipStart].trimmingCharacters(in: .whitespaces)
                let ip = String(value[value.index(after: ipStart)..<ipEnd])
                let mac = String(value[atRange.upperBound..<onRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let interface = value[onRange.upperBound...].split(separator: " ").first.map(String.init) ?? "unknown"
                guard ip.contains("."), mac != "(incomplete)" else { return nil }
                return NetworkDevice(ipAddress: ip, macAddress: mac, interface: interface, hostname: hostname.isEmpty ? "Unknown" : hostname)
            }
    }
}

@MainActor
final class NetworkConfigurationProvider: ObservableObject {
    @Published var services: [String] = []
    @Published var details: NetworkServiceDetails?
    @Published var selectedService = ""
    @Published var statusMessage = ""
    @Published var isBusy = false

    func refreshServices() async {
        guard let networksetupPath = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]) else { return }
        let output = (try? await ProcessRunner.runCapture(networksetupPath, ["-listallnetworkservices"])) ?? ""
        let parsed = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }

        services = parsed
        if selectedService.isEmpty || !parsed.contains(selectedService) {
            selectedService = parsed.first ?? ""
        }
        if !selectedService.isEmpty {
            await loadDetails(for: selectedService)
        }
    }

    func loadDetails(for service: String) async {
        guard !service.isEmpty else { return }
        guard let networksetupPath = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]) else { return }

        let infoOutput = (try? await ProcessRunner.runCapture(networksetupPath, ["-getinfo", service])) ?? ""
        let dnsOutput = (try? await ProcessRunner.runCapture(networksetupPath, ["-getdnsservers", service])) ?? ""

        let details = NetworkServiceDetails(
            serviceName: service,
            configuration: parseField("Configuration", in: infoOutput),
            ipAddress: parseField("IP address", in: infoOutput),
            subnetMask: parseField("Subnet mask", in: infoOutput),
            router: parseField("Router", in: infoOutput),
            macAddress: parseField("\(service) ID", in: infoOutput, fallbackPrefixes: ["Wi-Fi ID", "Ethernet Address"]),
            dnsServers: parseDNS(output: dnsOutput)
        )

        selectedService = service
        self.details = details
        statusMessage = "Loaded \(service)"
    }

    func applyDHCP() async {
        guard !selectedService.isEmpty else { return }
        await runConfigCommand(args: ["-setdhcp", selectedService], success: "Set \(selectedService) to DHCP")
        await loadDetails(for: selectedService)
    }

    func applyManual(ip: String, subnet: String, router: String) async {
        guard !selectedService.isEmpty else { return }
        await runConfigCommand(args: ["-setmanual", selectedService, ip, subnet, router], success: "Applied static IP to \(selectedService)")
        await loadDetails(for: selectedService)
    }

    func applyAutomaticDNS() async {
        guard !selectedService.isEmpty else { return }
        await runConfigCommand(args: ["-setdnsservers", selectedService, "Empty"], success: "Set DNS to automatic for \(selectedService)")
        await loadDetails(for: selectedService)
    }

    func applyManualDNS(_ servers: [String]) async {
        guard !selectedService.isEmpty else { return }
        await runConfigCommand(args: ["-setdnsservers", selectedService] + servers, success: "Updated DNS for \(selectedService)")
        await loadDetails(for: selectedService)
    }

    private func runConfigCommand(args: [String], success: String) async {
        guard let networksetupPath = ProcessRunner.findExecutable(["/usr/sbin/networksetup"]) else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let output = try await ProcessRunner.runCapture(networksetupPath, args)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            statusMessage = trimmed.isEmpty ? success : trimmed
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func parseField(_ label: String, in output: String, fallbackPrefixes: [String] = []) -> String {
        let allPrefixes = [label] + fallbackPrefixes
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in allPrefixes where trimmed.hasPrefix("\(prefix):") {
                return trimmed.replacingOccurrences(of: "\(prefix):", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return "Unavailable"
    }

    private func parseDNS(output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("aren't any DNS Servers") {
            return []
        }
        return trimmed.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

@MainActor
final class LiveSystemStatsProvider: ObservableObject {
    @Published var cpuUsage = "--"
    @Published var memoryUsage = "--"
    @Published var storageUsage = "--"
    @Published var gpuInfo = "Loading..."

    private var refreshTask: Task<Void, Never>?

    init() {
        start()
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatic()
            while !Task.isCancelled {
                await self.refreshDynamic()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func refreshStatic() async {
        guard let profilerPath = ProcessRunner.findExecutable(["/usr/sbin/system_profiler"]) else { return }
        if let output = try? await ProcessRunner.runCapture(profilerPath, ["SPDisplaysDataType", "-detailLevel", "mini"]) {
            let gpuLine = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("Chipset Model:") || $0.hasPrefix("Graphics:") }
            gpuInfo = gpuLine?.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces) ?? "Unavailable"
        }
    }

    private func refreshDynamic() async {
        if let topPath = ProcessRunner.findExecutable(["/usr/bin/top"]) {
            if let output = try? await ProcessRunner.runCapture(topPath, ["-l", "1", "-n", "0"]) {
                if let cpuLine = output.split(separator: "\n").map(String.init).first(where: { $0.contains("CPU usage:") }) {
                    cpuUsage = cpuLine.replacingOccurrences(of: "CPU usage:", with: "").trimmingCharacters(in: .whitespaces)
                }
                if let memoryLine = output.split(separator: "\n").map(String.init).first(where: { $0.contains("PhysMem:") }) {
                    memoryUsage = memoryLine.replacingOccurrences(of: "PhysMem:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let rootURL = URL(fileURLWithPath: "/")
        if let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
            let used = max(total - Int(available), 0)
            storageUsage = "\(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file)) used / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))"
        }
    }
}

@MainActor
final class MacOverviewProvider: ObservableObject {
    @Published var modelName = "Loading..."
    @Published var modelIdentifier = "Loading..."
    @Published var serialNumber = "Loading..."
    @Published var macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    @Published var uptime = ""
    @Published var appleIDStatus = "Unavailable via public API"

    func refresh() async {
        uptime = formattedUptime(ProcessInfo.processInfo.systemUptime)

        guard let profilerPath = ProcessRunner.findExecutable(["/usr/sbin/system_profiler"]) else { return }
        guard let output = try? await ProcessRunner.runCapture(profilerPath, ["SPHardwareDataType", "SPSoftwareDataType", "-detailLevel", "mini"]) else { return }

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Model Name:") {
                modelName = value(afterColonIn: trimmed)
            } else if trimmed.hasPrefix("Model Identifier:") {
                modelIdentifier = value(afterColonIn: trimmed)
            } else if trimmed.hasPrefix("Serial Number") {
                serialNumber = value(afterColonIn: trimmed)
            } else if trimmed.hasPrefix("System Version:") {
                macOSVersion = value(afterColonIn: trimmed)
            }
        }
    }
}

@MainActor
final class FolderSizeProvider: ObservableObject {
    @Published var folderSizes: [(String, String)] = []

    func refresh() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets = [
            ("Desktop", home.appendingPathComponent("Desktop")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Caches", home.appendingPathComponent("Library/Caches"))
        ]

        var results = [(String, String)]()
        for target in targets {
            let size = directorySize(at: target.1)
            results.append((target.0, ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }

        folderSizes = results
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
                total += size
            }
        }
        return total
    }
}

private func formattedUptime(_ uptime: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: uptime) ?? "Unavailable"
}

private func value(afterColonIn string: String) -> String {
    string.split(separator: ":", maxSplits: 1).dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
}

private func runCommandOutput(_ command: String, _ arguments: [String]) async -> String {
    guard ProcessRunner.findExecutable([command]) != nil else {
        return "Command unavailable: \(command)"
    }

    do {
        let output = try await ProcessRunner.runCapture(command, arguments)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No output." : trimmed
    } catch {
        return "Failed: \(error.localizedDescription)"
    }
}

private func openApplication(at path: String) {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init(), completionHandler: nil)
}

struct ContentView: View {
    @State private var activeDestination: SidebarDestination?

    var body: some View {
        NavigationSplitView {
            List(selection: $activeDestination) {
                ForEach(SidebarCategory.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(category.destinations) { destination in
                            Label(destination.title, systemImage: destination.icon)
                                .tag(destination)
                        }
                    }
                }
            }
            .navigationTitle("Control Panel")
            .listStyle(.sidebar)
        } detail: {
            Group {
                if let activeDestination {
                    destinationView(for: activeDestination)
                } else {
                    AppOverviewView(openDestination: { destination in
                        activeDestination = destination
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destinationView(for destination: SidebarDestination) -> some View {
        switch destination {
        case .generalAbout:
            GeneralAboutView(navigateBack: { activeDestination = nil })
        case .performance:
            PerformanceMonitorView(navigateBack: { activeDestination = nil })
        case .storage:
            StorageManagementView(navigateBack: { activeDestination = nil })
        case .displays:
            DisplaysGraphicsView(navigateBack: { activeDestination = nil })
        case .sound:
            SoundAudioView(navigateBack: { activeDestination = nil })
        case .battery:
            BatteryPowerView(navigateBack: { activeDestination = nil })
        case .privacySecurity:
            PrivacySecurityView(navigateBack: { activeDestination = nil })
        case .networkDashboard:
            NetworkDashboardView(navigateBack: { activeDestination = nil })
        case .deviceScanner:
            DeviceScannerView(navigateBack: { activeDestination = nil })
        case .adapterConfig:
            AdapterConfigurationView(navigateBack: { activeDestination = nil })
        case .networkQuality:
            NetworkQualityToolView(navigateBack: { activeDestination = nil })
        case .ping:
            PingToolView(navigateBack: { activeDestination = nil })
        case .traceroute:
            TracerouteToolView(navigateBack: { activeDestination = nil })
        case .dnsLookup:
            DNSLookupView(navigateBack: { activeDestination = nil })
        case .portCheck:
            PortCheckToolView(navigateBack: { activeDestination = nil })
        case .httpInspector:
            HTTPInspectorToolView(navigateBack: { activeDestination = nil })
        case .wifi:
            WiFiToolView(navigateBack: { activeDestination = nil })
        case .printers:
            PrinterToolView(navigateBack: { activeDestination = nil })
        case .developerTools:
            DeveloperToolsView(navigateBack: { activeDestination = nil })
        case .backupRecovery:
            BackupRecoveryView(navigateBack: { activeDestination = nil })
        case .system:
            SystemOverviewView(navigateBack: { activeDestination = nil })
        }
    }
}

struct AppOverviewView: View {
    let openDestination: (SidebarDestination) -> Void

    private let quickActions: [SidebarDestination] = [.generalAbout, .networkDashboard, .printers, .privacySecurity]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Control Panel",
                    subtitle: "A native utility hub for your Mac, with quick access to the tools you are most likely to use."
                ) {
                    Label("Choose a tool from the sidebar", systemImage: "sidebar.left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SectionCard("Quick Access") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(quickActions) { destination in
                            Button {
                                openDestination(destination)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(destination.title, systemImage: destination.icon)
                                        .font(.headline)
                                    Text(destination.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .padding(18)
                                .panelSurface()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionCard("Browse by Area") {
                    ForEach(SidebarCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(category.rawValue, systemImage: category.icon)
                                .font(.headline)
                            Text(category.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if category.id != SidebarCategory.allCases.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
    }
}

struct CategoryOverviewView: View {
    let category: SidebarCategory
    let openDestination: (SidebarDestination) -> Void

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: category.rawValue,
                    subtitle: category.summary
                ) {
                    Label("\(category.destinations.count) tools", systemImage: category.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SectionCard("Recommended") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(category.featuredDestinations.enumerated()), id: \.element) { _, destination in
                            Button {
                                openDestination(destination)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(destination.title, systemImage: destination.icon)
                                        .font(.headline)
                                    Text(destination.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text("Open")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                                .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                                .padding(18)
                                .panelSurface()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !category.secondaryDestinations.isEmpty {
                    SectionCard("More Tools") {
                        ForEach(category.secondaryDestinations) { destination in
                            Button {
                                openDestination(destination)
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: destination.icon)
                                        .foregroundStyle(.tint)
                                        .frame(width: 22, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(destination.title)
                                            .font(.headline)
                                        Text(destination.summary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            if destination.id != category.secondaryDestinations.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
    }
}

struct GeneralAboutView: View {
    let navigateBack: () -> Void
    @StateObject private var overview = MacOverviewProvider()
    @StateObject private var liveStats = LiveSystemStatsProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "General",
                    subtitle: "About this Mac, quick system links, and live hardware summary."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: { Task { await overview.refresh() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 16) {
                    StatCard(title: "CPU", value: liveStats.cpuUsage, detail: "Live processor usage")
                    StatCard(title: "Memory", value: liveStats.memoryUsage, detail: "Physical memory snapshot")
                    StatCard(title: "Storage", value: liveStats.storageUsage, detail: "Startup disk")
                    StatCard(title: "GPU", value: liveStats.gpuInfo, detail: "Graphics hardware")
                }

                SectionCard("About This Mac") {
                    KeyValueRow(title: "Model", value: overview.modelName)
                    KeyValueRow(title: "Identifier", value: overview.modelIdentifier)
                    KeyValueRow(title: "Serial", value: overview.serialNumber)
                    KeyValueRow(title: "macOS", value: overview.macOSVersion)
                    KeyValueRow(title: "Uptime", value: overview.uptime)
                    KeyValueRow(title: "Apple ID", value: overview.appleIDStatus)
                }

                SectionCard("Quick Links") {
                    HStack(spacing: 12) {
                        Button("System Settings") {
                            openApplication(at: "/System/Applications/System Settings.app")
                        }
                        Button("Terminal") {
                            openApplication(at: "/System/Applications/Utilities/Terminal.app")
                        }
                        Button("Activity Monitor") {
                            openApplication(at: "/System/Applications/Utilities/Activity Monitor.app")
                        }
                        Button("Console") {
                            openApplication(at: "/System/Applications/Utilities/Console.app")
                        }
                    }
                }

                SectionCard("About Control Panel") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                    KeyValueRow(title: "Version", value: "\(version) (\(build))")
                    KeyValueRow(title: "Runtime", value: "Native macOS · Hardened Runtime")
                    KeyValueRow(title: "Distribution", value: "Direct download · Notarized")
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task { await overview.refresh() }
    }
}

struct PerformanceMonitorView: View {
    let navigateBack: () -> Void
    @StateObject private var liveStats = LiveSystemStatsProvider()
    @State private var processes = "Loading..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Performance",
                    subtitle: "Live stats and top processes."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: { refreshProcesses() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 16) {
                    StatCard(title: "CPU", value: liveStats.cpuUsage, detail: "Current CPU usage")
                    StatCard(title: "Memory", value: liveStats.memoryUsage, detail: "Current memory usage")
                    StatCard(title: "Storage", value: liveStats.storageUsage, detail: "Disk usage")
                }

                SectionCard("Top Processes") {
                    Text(processes)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task { refreshProcesses() }
    }

    private func refreshProcesses() {
        Task {
            processes = await runCommandOutput("/bin/ps", ["-Aceo", "pid,comm,%cpu,%mem", "-r"])
        }
    }
}

struct StorageManagementView: View {
    let navigateBack: () -> Void
    @StateObject private var folders = FolderSizeProvider()
    @State private var diskSummary = "Loading..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Storage",
                    subtitle: "Disk usage and common folder sizes."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: {
                        Task {
                            await folders.refresh()
                            refreshDiskSummary()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                SectionCard("Disk Summary") {
                    Text(diskSummary)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard("Home Folder Breakdown") {
                    ForEach(folders.folderSizes, id: \.0) { row in
                        KeyValueRow(title: row.0, value: row.1)
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task {
            await folders.refresh()
            refreshDiskSummary()
        }
    }

    private func refreshDiskSummary() {
        let rootURL = URL(fileURLWithPath: "/")
        if let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
            let used = max(total - Int(available), 0)
            diskSummary = "Used: \(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .file))\nAvailable: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))\nTotal: \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))"
        }
    }
}

struct DisplaysGraphicsView: View {
    let navigateBack: () -> Void
    @State private var output = "Loading..."

    var body: some View {
        ToolShell(
            title: "Displays & Graphics",
            subtitle: "Connected displays and graphics summary.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            },
            output: output,
            isRunning: false
        )
        .task { refresh() }
    }

    private func refresh() {
        Task {
            output = await runCommandOutput("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-detailLevel", "mini"])
        }
    }
}

struct SoundAudioView: View {
    let navigateBack: () -> Void
    @State private var output = "Loading..."

    var body: some View {
        ToolShell(
            title: "Sound & Audio",
            subtitle: "Audio devices and current sound subsystem summary.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            },
            output: output,
            isRunning: false
        )
        .task { refresh() }
    }

    private func refresh() {
        Task {
            output = await runCommandOutput("/usr/sbin/system_profiler", ["SPAudioDataType", "-detailLevel", "mini"])
        }
    }
}

struct BatteryPowerView: View {
    let navigateBack: () -> Void
    @State private var batteryOutput = "Loading..."

    var body: some View {
        ToolShell(
            title: "Battery & Power",
            subtitle: "Battery health, charging state, and power details.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            },
            output: batteryOutput,
            isRunning: false
        )
        .task { refresh() }
    }

    private func refresh() {
        Task {
            let batt = await runCommandOutput("/usr/bin/pmset", ["-g", "batt"])
            let power = await runCommandOutput("/usr/sbin/system_profiler", ["SPPowerDataType", "-detailLevel", "mini"])
            batteryOutput = "Battery\n\(batt)\n\nPower Details\n\(power)"
        }
    }
}

struct PrivacySecurityView: View {
    let navigateBack: () -> Void
    @State private var status = "Loading..."

    var body: some View {
        ToolShell(
            title: "Privacy & Security",
            subtitle: "FileVault, Gatekeeper, firewall, and security quick access.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button("Open Settings") {
                    openApplication(at: "/System/Applications/System Settings.app")
                }
            },
            output: status,
            isRunning: false
        )
        .task { refresh() }
    }

    private func refresh() {
        Task {
            let fileVault = await runCommandOutput("/usr/bin/fdesetup", ["status"])
            let gatekeeper = await runCommandOutput("/usr/sbin/spctl", ["--status"])
            let firewall = await runCommandOutput("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.alf", "globalstate"])
            status = "FileVault\n\(fileVault)\n\nGatekeeper\n\(gatekeeper)\n\nFirewall\n\(firewall)"
        }
    }
}

struct DeveloperToolsView: View {
    let navigateBack: () -> Void
    @State private var hostsText = ""
    @State private var proxyOutput = "Loading..."
    @State private var saveMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Developer Tools",
                    subtitle: "Hosts file, proxy settings, and quick developer shortcuts."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: { loadData() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    Button(action: { saveHosts() }) {
                        Label("Save Hosts", systemImage: "square.and.arrow.down")
                    }
                    Button("Terminal") { openApplication(at: "/System/Applications/Utilities/Terminal.app") }
                    Button("Console") { openApplication(at: "/System/Applications/Utilities/Console.app") }
                }

                SectionCard("Hosts File") {
                    TextEditor(text: $hostsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                    if !saveMessage.isEmpty {
                        Text(saveMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard("Proxy Settings") {
                    Text(proxyOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task { loadData() }
    }

    private func loadData() {
        saveMessage = ""
        hostsText = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? "Unable to read /etc/hosts"
        Task {
            proxyOutput = await runCommandOutput("/usr/sbin/scutil", ["--proxy"])
        }
    }

    private func saveHosts() {
        do {
            try hostsText.write(toFile: "/etc/hosts", atomically: true, encoding: .utf8)
            saveMessage = "Saved /etc/hosts"
        } catch {
            saveMessage = "Failed to save /etc/hosts: \(error.localizedDescription)"
        }
    }
}

struct BackupRecoveryView: View {
    let navigateBack: () -> Void
    @State private var output = "Loading..."

    var body: some View {
        ToolShell(
            title: "Backup & Recovery",
            subtitle: "Time Machine status, destinations, and latest backup information.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            },
            output: output,
            isRunning: false
        )
        .task { refresh() }
    }

    private func refresh() {
        Task {
            let status = await runCommandOutput("/usr/bin/tmutil", ["status"])
            let destinations = await runCommandOutput("/usr/bin/tmutil", ["destinationinfo"])
            let latest = await runCommandOutput("/usr/bin/tmutil", ["latestbackup"])
            output = "Status\n\(status)\n\nDestinations\n\(destinations)\n\nLatest Backup\n\(latest)"
        }
    }
}

struct DeviceScannerView: View {
    let navigateBack: () -> Void
    @StateObject private var provider = NetworkDevicesProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Device Scanner",
                    subtitle: "Discover devices on the current LAN using ARP and a quick ping sweep."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: { Task { await provider.scan() } }) {
                        Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(provider.isScanning)
                }

                HStack(spacing: 16) {
                    StatCard(title: "Subnet", value: provider.subnetPrefix.isEmpty ? "Unknown" : "\(provider.subnetPrefix).0/24", detail: provider.status)
                    StatCard(title: "Devices", value: "\(provider.devices.count)", detail: "Entries from LAN discovery")
                }

                SectionCard("Devices") {
                    if provider.devices.isEmpty {
                        EmptyStateRow(message: provider.status)
                    } else {
                        ForEach(provider.devices) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                KeyValueRow(title: device.hostname, value: device.ipAddress)
                                Text("\(device.macAddress) · \(device.interface)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task { await provider.scan() }
    }
}

struct AdapterConfigurationView: View {
    let navigateBack: () -> Void
    @StateObject private var provider = NetworkConfigurationProvider()
    @State private var manualIP = ""
    @State private var subnetMask = "255.255.255.0"
    @State private var router = ""
    @State private var dnsServers = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "IP & DNS",
                    subtitle: "Use native macOS networksetup commands for DHCP, static IP, and DNS configuration."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Picker("Service", selection: $provider.selectedService) {
                        ForEach(provider.services, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    .frame(width: 180)
                    .onChange(of: provider.selectedService) { _, newValue in
                        Task { await provider.loadDetails(for: newValue) }
                    }

                    Button(action: { Task { await provider.refreshServices() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh network info")
                }

                if let details = provider.details {
                    HStack(spacing: 16) {
                        StatCard(title: "Service", value: details.serviceName, detail: details.configuration)
                        StatCard(title: "IP", value: details.ipAddress, detail: details.subnetMask)
                        StatCard(title: "Router", value: details.router, detail: details.macAddress)
                        StatCard(title: "DNS", value: details.dnsServers.first ?? "Automatic", detail: details.dnsServers.isEmpty ? "System resolver" : "\(details.dnsServers.count) server(s)")
                    }

                    SectionCard("Current Configuration") {
                        KeyValueRow(title: "Service", value: details.serviceName)
                        KeyValueRow(title: "Configuration", value: details.configuration)
                        KeyValueRow(title: "IPv4", value: details.ipAddress)
                        KeyValueRow(title: "Subnet", value: details.subnetMask)
                        KeyValueRow(title: "Router", value: details.router)
                        KeyValueRow(title: "MAC", value: details.macAddress)
                        KeyValueRow(title: "DNS", value: details.dnsServers.isEmpty ? "Automatic" : details.dnsServers.joined(separator: ", "))
                    }
                }

                SectionCard("Static IP") {
                    HStack(spacing: 10) {
                        TextField("IP Address", text: $manualIP)
                            .textFieldStyle(.roundedBorder)
                        TextField("Subnet Mask", text: $subnetMask)
                            .textFieldStyle(.roundedBorder)
                        TextField("Router", text: $router)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 10) {
                        Button("Apply Static IP") {
                            Task { await provider.applyManual(ip: manualIP, subnet: subnetMask, router: router) }
                        }
                        .disabled(provider.selectedService.isEmpty || manualIP.isEmpty || subnetMask.isEmpty || router.isEmpty || provider.isBusy)

                        Button("Use DHCP") {
                            Task { await provider.applyDHCP() }
                        }
                        .disabled(provider.selectedService.isEmpty || provider.isBusy)
                    }
                }

                SectionCard("DNS") {
                    TextField("DNS Servers (comma separated)", text: $dnsServers)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button("Apply DNS") {
                            let servers = dnsServers
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            Task { await provider.applyManualDNS(servers) }
                        }
                        .disabled(provider.selectedService.isEmpty || provider.isBusy)

                        Button("Automatic DNS") {
                            Task { await provider.applyAutomaticDNS() }
                        }
                        .disabled(provider.selectedService.isEmpty || provider.isBusy)
                    }
                }

                if !provider.statusMessage.isEmpty {
                    SectionCard("Status") {
                        Text(provider.statusMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task {
            await provider.refreshServices()
            if let details = provider.details {
                manualIP = details.ipAddress == "Unavailable" ? "" : details.ipAddress
                subnetMask = details.subnetMask == "Unavailable" ? "255.255.255.0" : details.subnetMask
                router = details.router == "Unavailable" ? "" : details.router
                dnsServers = details.dnsServers.joined(separator: ", ")
            }
        }
        .onChange(of: provider.details) { _, details in
            guard let details else { return }
            manualIP = details.ipAddress == "Unavailable" ? "" : details.ipAddress
            subnetMask = details.subnetMask == "Unavailable" ? "255.255.255.0" : details.subnetMask
            router = details.router == "Unavailable" ? "" : details.router
            dnsServers = details.dnsServers.joined(separator: ", ")
        }
    }
}

struct NetworkDashboardView: View {
    let navigateBack: () -> Void
    @StateObject private var provider = NetworkInfoProvider()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Network",
                    subtitle: "Internet status, adapters, DNS, and route information."
                ) {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Button(action: { Task { await provider.refresh() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(provider.isRefreshing)
                    .help("Refresh network info")

                    Button {
                        var lines: [String] = []
                        lines.append("Public IP: \(provider.publicIP)")
                        if !provider.interfaces.isEmpty {
                            lines.append("Interfaces:")
                            for i in provider.interfaces { lines.append("  • \(i.name) \(i.family) \(i.address)") }
                        }
                        if !provider.dnsServers.isEmpty {
                            lines.append("DNS Servers:")
                            for d in provider.dnsServers { lines.append("  • \(d)") }
                        }
                        let text = lines.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .help("Copy a full snapshot to the clipboard")
                }

                HStack(spacing: 16) {
                    StatCard(title: "Public IP", value: provider.publicIP, detail: "External address")
                    StatCard(title: "Gateway", value: provider.defaultGateway, detail: provider.primaryInterface)
                    StatCard(title: "DNS", value: provider.dnsServers.first ?? "Unavailable", detail: "\(provider.dnsServers.count) server(s)")
                    StatCard(title: "Benchmark", value: provider.benchmarkSummary.components(separatedBy: "\n").first ?? "Not run", detail: provider.isBenchmarking ? "Running..." : "Use Network Quality for full details")
                }
                if provider.publicIP == "Unavailable" || provider.publicIP == "Error" {
                    Text("Tip: Check firewall/proxy or sandbox settings; curl fallback is used if URLSession is blocked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SectionCard("Interfaces") {
                    if provider.interfaces.isEmpty {
                        EmptyStateRow(message: "No interfaces found.")
                    } else {
                        ForEach(provider.interfaces) { interface in
                            KeyValueRow(
                                title: "\(interface.name) · \(interface.family)",
                                value: interface.address
                            )
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    SectionCard("Hardware Ports") {
                        if provider.hardwarePorts.isEmpty {
                            EmptyStateRow(message: "No hardware ports returned.")
                        } else {
                            ForEach(provider.hardwarePorts) { port in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(port.name)
                                    Text("\(port.device) · \(port.address)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    SectionCard("Network Services") {
                        if provider.networkServices.isEmpty {
                            EmptyStateRow(message: "No services returned.")
                        } else {
                            ForEach(provider.networkServices, id: \.self) { service in
                                Text(service)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        var lines: [String] = []
                        lines.append("Public IP: \(provider.publicIP)")
                        if !provider.interfaces.isEmpty {
                            lines.append("Interfaces:")
                            for i in provider.interfaces { lines.append("  • \(i.name) \(i.family) \(i.address)") }
                        }
                        if !provider.dnsServers.isEmpty {
                            lines.append("DNS Servers:")
                            for d in provider.dnsServers { lines.append("  • \(d)") }
                        }
                        let text = lines.joined(separator: "\n")
                        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("NetworkReport-\(Int(Date().timeIntervalSince1970)).txt")
                        try? text.data(using: .utf8)?.write(to: url)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Save Report", systemImage: "square.and.arrow.down")
                    }
                    .help("Export a text report to a file")
                    Spacer()
                }
                .padding(.top, 4)

                SectionCard("Benchmark") {
                    Text(provider.benchmarkSummary)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .task { await provider.refresh() }
        .background(AppBackground())
    }
}

struct SystemOverviewView: View {
    let navigateBack: () -> Void
    private let details: [(String, String)] = [
        ("Computer", Host.current().localizedName ?? "Unknown"),
        ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
        ("Architecture", ProcessInfo.processInfo.machineHardwareName),
        ("Processor Count", "\(ProcessInfo.processInfo.processorCount)"),
        ("Physical Memory", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(title: "System", subtitle: "Machine and operating system information.") {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                SectionCard("Overview") {
                    ForEach(details, id: \.0) { row in
                        KeyValueRow(title: row.0, value: row.1)
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
    }
}

struct NetworkQualityToolView: View {
    let navigateBack: () -> Void
    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        ToolShell(
            title: "Network Quality",
            subtitle: "Measure uplink, downlink, and responsiveness using Apple’s networkQuality tool.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                Button(action: { runBenchmark() }) {
                    Label("Run Benchmark", systemImage: "speedometer")
                }
                .disabled(isRunning)
            },
            output: output,
            isRunning: isRunning
        )
        .task {
            if output.isEmpty {
                runBenchmark()
            }
        }
    }

    private func runBenchmark() {
        guard let commandPath = ProcessRunner.findExecutable(["/usr/bin/networkQuality"]) else {
            output = "`networkQuality` is unavailable on this Mac."
            return
        }

        isRunning = true
        output = "Running benchmark..."

        Task {
            do {
                let result = try await ProcessRunner.runCapture(commandPath, ["-v"])
                await MainActor.run {
                    output = result
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    output = "Benchmark failed.\n\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
}

struct PortCheckToolView: View {
    let navigateBack: () -> Void
    @State private var host = "apple.com"
    @State private var ports = "80,443,8080"
    @State private var timeout = "3"
    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        ToolShell(
            title: "Port Check",
            subtitle: "Test TCP reachability for one or more ports on a remote host.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(startCheck)

                TextField("Ports", text: $ports)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                TextField("Timeout", text: $timeout)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Button(action: { startCheck() }) {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(isRunning || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            },
            output: output,
            isRunning: isRunning
        )
    }

    private func startCheck() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPorts = ports
            .split(separator: ",")
            .compactMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let timeoutSeconds = max(Int(timeout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 3, 1)

        guard !trimmedHost.isEmpty else {
            output = "Enter a host."
            return
        }

        guard !parsedPorts.isEmpty else {
            output = "Enter one or more ports separated by commas."
            return
        }

        isRunning = true
        output = "Checking \(trimmedHost)..."

        Task {
            let results = await withTaskGroup(of: String.self, returning: [String].self) { group in
                for port in parsedPorts {
                    group.addTask {
                        await checkPortWithNetcat(host: trimmedHost, port: port, timeoutSeconds: timeoutSeconds)
                    }
                }

                var lines = [String]()
                for await line in group {
                    lines.append(line)
                }
                return lines.sorted()
            }

            await MainActor.run {
                output = results.joined(separator: "\n")
                isRunning = false
            }
        }
    }

    private func checkPortWithNetcat(host: String, port: UInt16, timeoutSeconds: Int) async -> String {
        guard let commandPath = ProcessRunner.findExecutable(["/usr/bin/nc"]) else {
            return "Port \(port): `nc` is unavailable"
        }

        do {
            let result = try await ProcessRunner.runCapture(commandPath, ["-G", String(timeoutSeconds), "-zv", host, String(port)])
            return "Port \(port): \(result.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            return "Port \(port): Failed (\(error.localizedDescription))"
        }
    }
}

struct HTTPInspectorToolView: View {
    let navigateBack: () -> Void
    @State private var urlString = "https://apple.com"
    @State private var method = "GET"
    @State private var output = ""
    @State private var isLoading = false

    private let methods = ["GET", "HEAD"]

    var body: some View {
        ToolShell(
            title: "HTTP Inspector",
            subtitle: "Fetch status, headers, and a body preview for an HTTP endpoint.",
            controls: {
                Button(action: { navigateBack() }) {
                    Label("Back", systemImage: "chevron.left")
                }
                TextField("URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onSubmit(runRequest)

                Picker("Method", selection: $method) {
                    ForEach(methods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .pickerStyle(.menu)

                Button(action: { runRequest() }) {
                    Label("Send", systemImage: "paperplane")
                }
                .disabled(isLoading || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            },
            output: output,
            isRunning: isLoading
        )
    }

    private func runRequest() {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL) else {
            output = "Enter a valid URL."
            return
        }

        isLoading = true
        output = "Loading..."

        Task {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    await MainActor.run {
                        output = "No HTTP response."
                        isLoading = false
                    }
                    return
                }

                let headers = http.allHeaderFields
                    .map { "\($0.key): \($0.value)" }
                    .sorted()
                    .joined(separator: "\n")

                let bodyPreview: String
                if method == "HEAD" {
                    bodyPreview = "(no body for HEAD request)"
                } else {
                    let body = String(decoding: data.prefix(1200), as: UTF8.self)
                    bodyPreview = body.isEmpty ? "(empty body)" : body
                }

                await MainActor.run {
                    output = """
                    Status: \(http.statusCode)
                    URL: \(trimmedURL)

                    Headers
                    \(headers)

                    Body Preview
                    \(bodyPreview)
                    """
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    output = "Request failed.\n\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

struct ToolShell<Controls: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let controls: Controls
    let output: String
    let isRunning: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(title: title, subtitle: subtitle) {
                    controls
                }

                SectionCard("Output") {
                    if isRunning {
                        StatusBanner(message: "Running…", tone: .neutral)
                    }

                    ScrollView {
                        Text(output.isEmpty ? "No output yet." : output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 300)
                }
            }
            .padding(24)
        }
        .background(AppBackground())
    }
}

struct HeaderBlock<Controls: View>: View {
    let title: String
    let subtitle: String
    let controls: Controls

    init(title: String, subtitle: String, @ViewBuilder controls: () -> Controls) {
        self.title = title
        self.subtitle = subtitle
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .vertical) {
                HStack(spacing: 10) {
                    controls
                }

                VStack(alignment: .leading, spacing: 10) {
                    controls
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .panelSurface()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panelSurface()
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .panelSurface()
    }
}

struct KeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct EmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBanner: View {
    enum Tone {
        case neutral
        case success
        case warning
    }

    let message: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch tone {
        case .neutral:
            return AnyShapeStyle(.quaternary.opacity(0.35))
        case .success:
            return AnyShapeStyle(Color.green.opacity(0.12))
        case .warning:
            return AnyShapeStyle(Color.orange.opacity(0.14))
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .controlBackgroundColor).opacity(0.75)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
            .ignoresSafeArea()
    }
}

extension View {
    func panelSurface() -> some View {
        modifier(PanelSurfaceModifier())
    }
}

struct PanelSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            }
            .applyLiquidGlass()
    }
}

extension View {
    @ViewBuilder
    func applyLiquidGlass() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        } else {
            self
        }
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

#Preview {
    ContentView()
}
