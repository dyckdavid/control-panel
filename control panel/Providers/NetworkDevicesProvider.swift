import Foundation
import Darwin
import Network
import Observation

/// Finds the devices on this Mac's local network.
///
/// macOS 27 hides the ARP table's hardware addresses from unprivileged
/// processes: `arp -an` run as the user returns nothing at all, while the same
/// command as root lists every neighbour. So there are two modes.
///
/// **Default, no password.** Liveness comes from a concurrent ICMP ping plus a
/// TCP probe of a few common ports, where a refused connection counts as
/// alive. Bonjour adverts add anything that answers neither. Names come from
/// Bonjour and reverse DNS. No hardware addresses.
///
/// **Hardware addresses, one admin prompt per scan.** Every address gets a
/// one-byte UDP datagram from a single socket, which forces the kernel to ARP
/// for it — and every device on the LAN answers ARP whatever its firewall.
/// The ARP table is then read as root, giving each device's MAC and, from the
/// IEEE registry, its vendor. This is also the most complete liveness check.
@MainActor
@Observable
final class NetworkDevicesProvider {
    private(set) var devices: [NetworkDevice] = []
    private(set) var subnet: LocalSubnet?
    private(set) var status = "Idle"
    private(set) var isScanning = false
    private(set) var progress: Double = 0
    /// True when the network was bigger than the sweep limit, so only the
    /// block around this Mac was probed.
    private(set) var wasTruncated = false
    /// Whether the last scan read hardware addresses.
    private(set) var lastScanHadHardwareAddresses = false

    /// Read the ARP table as root for MACs and vendors. Off by default because
    /// it asks for an administrator password every scan.
    var includeHardwareAddresses = false

    /// Largest number of addresses probed in one scan (a /22). A /16 office
    /// network would otherwise mean 65 000 ARP requests.
    private static let maxHosts = 1022

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        defer {
            isScanning = false
            progress = 1
        }

        // The vendor table is only useful with hardware addresses. It downloads
        // in the background the first time; the scan never waits on it.
        if includeHardwareAddresses {
            Task { await MACVendorDatabase.shared.prepare() }
        }

        status = "Finding this Mac's network…"
        guard let subnet = Self.currentSubnet() else {
            status = "This Mac has no IPv4 network connection."
            devices = []
            return
        }
        self.subnet = subnet

        let targets = Self.targets(in: subnet)
        wasTruncated = subnet.hostCount > Self.maxHosts

        // Bonjour browsing takes a few seconds, so it runs alongside probing.
        async let bonjour = BonjourDirectory.collect(for: .seconds(4))

        var found: [NetworkDevice] = []
        lastScanHadHardwareAddresses = false

        if includeHardwareAddresses {
            status = "Probing \(targets.count) addresses on \(subnet.cidr)…"
            await Self.primeARP(targets)
            progress = 0.3
            try? await Task.sleep(for: .milliseconds(1200))
            // Second pass for anyone slow to answer the first time.
            await Self.primeARP(targets)
            try? await Task.sleep(for: .milliseconds(1500))
            progress = 0.5

            status = "Reading hardware addresses (administrator password)…"
            do {
                let arp = try await AdminCommand.run(
                    [["/usr/sbin/arp", "-an"]],
                    prompt: "Control Panel wants to read the hardware addresses of devices on your network. This is read-only."
                )
                found = Self.parseARP(arp, subnet: subnet)
                lastScanHadHardwareAddresses = true
            } catch {
                // Cancelled or failed: fall back to the unprivileged sweep so
                // the scan still produces a result.
                status = "Hardware addresses skipped. Scanning without them…"
            }
        }

        if !lastScanHadHardwareAddresses {
            status = "Probing \(targets.count) addresses on \(subnet.cidr)…"
            let alive = await LivenessProbe.sweep(targets) { [weak self] fraction in
                self?.progress = 0.05 + fraction * 0.55
            }
            found = alive.map { NetworkDevice(ipAddress: LocalSubnet.format($0), mac: nil, interface: subnet.interface) }
        }
        progress = 0.6

        // This Mac never appears in its own ARP table.
        if !found.contains(where: { $0.ipAddress == subnet.addressText }) {
            found.append(NetworkDevice(ipAddress: subnet.addressText, mac: nil, interface: subnet.interface))
        }

        let gateway = await Self.defaultGateway()
        for index in found.indices {
            found[index].isThisMac = found[index].ipAddress == subnet.addressText
            found[index].isGateway = found[index].ipAddress == gateway
            if found[index].isThisMac {
                found[index].name = Host.current().localizedName
            }
        }

        status = "Naming devices…"
        progress = 0.75
        let directory = await bonjour

        // A device that advertises on Bonjour is alive even if it ignored
        // every probe.
        let known = Set(found.map(\.ipAddress))
        for ip in directory.keys where !known.contains(ip) {
            guard let numeric = LocalSubnet.parse(ip), subnet.contains(numeric) else { continue }
            found.append(NetworkDevice(ipAddress: ip, mac: nil, interface: subnet.interface))
        }

        for index in found.indices {
            guard let identity = directory[found[index].ipAddress] else { continue }
            if !found[index].isThisMac || found[index].name == nil {
                found[index].name = identity.name
                found[index].nameSource = .bonjour
            }
            found[index].model = identity.model
            found[index].services = identity.services.sorted()
        }

        let unnamed = found.filter { !$0.hasName }.map(\.ipAddress)
        let reverse = await Self.reverseLookup(unnamed, timeout: .seconds(3))
        for index in found.indices where !found[index].hasName {
            if let name = reverse[found[index].ipAddress] {
                found[index].name = name
                found[index].nameSource = .reverseDNS
            }
        }

        await applyVendors(to: &found)

        devices = found.sorted { (LocalSubnet.parse($0.ipAddress) ?? 0) < (LocalSubnet.parse($1.ipAddress) ?? 0) }

        let named = devices.filter(\.hasName).count
        status = "Found \(devices.count) device\(devices.count == 1 ? "" : "s") on \(subnet.cidr), \(named) named."
    }

    /// Fills vendors once the OUI table is available. Also called after a scan
    /// that finished before the first download did.
    func refreshVendors() async {
        guard lastScanHadHardwareAddresses else { return }
        await MACVendorDatabase.shared.prepare()
        var updated = devices
        await applyVendors(to: &updated)
        devices = updated
    }

    private func applyVendors(to devices: inout [NetworkDevice]) async {
        for index in devices.indices {
            guard let mac = devices[index].mac, !mac.isLocallyAdministered else { continue }
            devices[index].vendor = await MACVendorDatabase.shared.vendor(for: mac)
        }
    }

    var report: String {
        var lines = [
            "Control Panel — device scan",
            "Network: \(subnet?.cidr ?? "unknown")",
            "Generated: \(Date.now.formatted(date: .abbreviated, time: .standard))",
            "",
            ["IP", "MAC", "Vendor", "Name", "Model"].joined(separator: "\t")
        ]
        for device in devices {
            lines.append([
                device.ipAddress,
                device.macText,
                device.vendorText ?? "",
                device.name ?? "",
                device.model ?? ""
            ].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Subnet

    /// Reads the address and netmask of the interface carrying the default
    /// route, rather than assuming a /24.
    nonisolated static func currentSubnet() -> LocalSubnet? {
        guard let interfaceName = defaultRouteInterface() else { return nil }

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(first) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }

            guard String(cString: current.ifa_name) == interfaceName,
                  let address = current.ifa_addr,
                  let netmask = current.ifa_netmask,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }

            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            return LocalSubnet(interface: interfaceName, address: ip, netmask: mask)
        }
        return nil
    }

    nonisolated private static func defaultRouteInterface() -> String? {
        guard let output = try? ProcessRunner.runCaptureSync("/sbin/route", ["-n", "get", "default"]) else { return nil }
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("interface:") }
            .map { valueAfterColon(in: $0) }
    }

    private static func defaultGateway() async -> String? {
        let output = await runCommandOutput("/sbin/route", ["-n", "get", "default"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("gateway:") }
            .map { valueAfterColon(in: $0) }
    }

    /// Every host address in the subnet, or the /22 around this Mac when the
    /// subnet is larger than that.
    nonisolated static func targets(in subnet: LocalSubnet) -> [UInt32] {
        var scope = subnet
        if subnet.hostCount > maxHosts {
            scope = LocalSubnet(interface: subnet.interface, address: subnet.address, netmask: 0xFFFF_FC00)
        }
        guard scope.hostCount > 0 else { return [] }
        return ((scope.network + 1)..<scope.broadcast).filter { $0 != subnet.address }
    }

    // MARK: ARP priming

    /// Sends one byte to UDP port 9 (discard) on every target from a single
    /// non-blocking socket. Off the main actor because it is a tight loop.
    nonisolated private static func primeARP(_ targets: [UInt32]) async {
        await Task.detached(priority: .userInitiated) {
            let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }

            let flags = fcntl(descriptor, F_GETFL, 0)
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

            var byte: UInt8 = 0
            for (offset, target) in targets.enumerated() {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(9).bigEndian
                address.sin_addr = in_addr(s_addr: target.bigEndian)

                _ = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, &byte, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                // A short pause every 64 sends keeps the kernel's queue of
                // unresolved ARP requests from overflowing on big subnets.
                if offset % 64 == 63 {
                    usleep(4_000)
                }
            }
        }.value
    }

    // MARK: ARP table

    /// Parses `arp -an` lines such as
    /// `? (192.168.0.1) at 0:11:32:aa:bb:cc on en0 ifscope [ethernet]`.
    nonisolated static func parseARP(_ output: String, subnet: LocalSubnet) -> [NetworkDevice] {
        var seen = Set<String>()

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> NetworkDevice? in
                let text = String(line)
                guard let open = text.firstIndex(of: "("),
                      let close = text.firstIndex(of: ")"),
                      open < close,
                      let at = text.range(of: " at "),
                      let on = text.range(of: " on ") else { return nil }

                let ip = String(text[text.index(after: open)..<close])
                guard let numeric = LocalSubnet.parse(ip),
                      subnet.contains(numeric),
                      numeric != subnet.network,
                      numeric != subnet.broadcast else { return nil }

                let macText = text[at.upperBound..<on.lowerBound].trimmingCharacters(in: .whitespaces)
                guard let mac = MACAddress(macText), !mac.isMulticast else { return nil }

                let interface = text[on.upperBound...].split(separator: " ").first.map(String.init) ?? subnet.interface
                guard interface == subnet.interface, seen.insert(ip).inserted else { return nil }

                return NetworkDevice(ipAddress: ip, mac: mac, interface: interface)
            }
    }

    // MARK: Reverse DNS

    /// Looks names up concurrently with an overall deadline. `getnameinfo` can
    /// block for seconds on a silent resolver, so anything still pending when
    /// the deadline passes is simply left unnamed.
    nonisolated private static func reverseLookup(_ addresses: [String], timeout: Duration) async -> [String: String] {
        guard !addresses.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, String?)?.self) { group in
            for address in addresses {
                group.addTask {
                    await Task.detached { (address, reverseName(address)) }.value
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            var names: [String: String] = [:]
            var remaining = addresses.count
            while remaining > 0, let result = await group.next() {
                guard let result else { break }   // the deadline fired
                remaining -= 1
                if let name = result.1 { names[result.0] = name }
            }
            group.cancelAll()
            return names
        }
    }

    nonisolated private static func reverseName(_ address: String) -> String? {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address, &socketAddress.sin_addr) == 1 else { return nil }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }

        let name = String(cString: host)
        // Trim the mDNS suffix so names read "Office-Printer", not
        // "Office-Printer.local".
        return name.hasSuffix(".local") ? String(name.dropLast(6)) : name
    }
}

// MARK: - Bonjour directory

/// What Bonjour says about one address.
nonisolated struct BonjourIdentity: Sendable {
    var name: String
    var model: String?
    var services: Set<String>
}

/// Browses the service types that cover most home and office devices and maps
/// each advertiser's IPv4 address to its name, services, and Apple model.
nonisolated enum BonjourDirectory {
    private static let serviceTypes = [
        "_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_googlecast._tcp",
        "_hap._tcp", "_homekit._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp",
        "_pdl-datastream._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp",
        "_sftp-ssh._tcp", "_http._tcp", "_spotify-connect._tcp", "_rdlink._tcp",
        "_scanner._tcp", "_uscan._tcp"
    ]

    private struct Advert: Hashable, Sendable {
        let name: String
        let type: String
        let domain: String
    }

    static func collect(for duration: Duration) async -> [String: BonjourIdentity] {
        let (adverts, models) = await browse(for: duration)

        // One resolve per device: devices use the same instance name across
        // all their services, so resolving any one of them gives the address.
        var byName: [String: Advert] = [:]
        var servicesByName: [String: Set<String>] = [:]
        for advert in adverts {
            let display = displayName(advert.name)
            byName[display] = byName[display] ?? advert
            servicesByName[display, default: []].insert(advert.type)
        }

        let resolved = await withTaskGroup(of: (String, String?).self) { group in
            for (display, advert) in byName {
                group.addTask {
                    (display, await BonjourResolver.resolveIPv4(name: advert.name, type: advert.type, domain: advert.domain))
                }
            }
            var pairs: [(String, String)] = []
            for await (display, ip) in group {
                if let ip { pairs.append((display, ip)) }
            }
            return pairs
        }

        var directory: [String: BonjourIdentity] = [:]
        for (display, ip) in resolved {
            directory[ip] = BonjourIdentity(
                name: display,
                model: models[display],
                services: servicesByName[display] ?? []
            )
        }
        return directory
    }

    /// The TXT keys that carry a model, by service: AirPlay `model`
    /// (`Mac14,3`, `AppleTV11,1`), Companion Link `rpMd`, AirPlay audio `am`,
    /// and Google Cast `md` (`Chromecast`). `_device-info` would be the obvious
    /// source, but current Apple software does not make it browsable.
    private static func model(in record: NWTXTRecord) -> String? {
        for key in ["model", "rpMd", "am", "md"] {
            if let value = record[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// AirPlay audio adverts are named `AABBCCDDEEFF@Living Room`; keep the
    /// human half.
    private static func displayName(_ name: String) -> String {
        if let at = name.firstIndex(of: "@") {
            return String(name[name.index(after: at)...])
        }
        return name
    }

    private static func browse(for duration: Duration) async -> (Set<Advert>, [String: String]) {
        let collector = Collector()
        var browsers: [NWBrowser] = []

        for type in serviceTypes {
            // Browse with TXT records: several services publish the device's
            // model there, which is how a Mac mini is told apart from an Apple
            // TV when both advertise AirPlay.
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: NWParameters())
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .service(name, type, domain, _) = result.endpoint else { continue }
                    collector.add(Advert(
                        name: name,
                        type: type.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                        domain: domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    ))
                    if case let .bonjour(record) = result.metadata, let model = model(in: record) {
                        collector.addModel(displayName(name), model)
                    }
                }
            }
            browser.start(queue: .global(qos: .userInitiated))
            browsers.append(browser)
        }

        try? await Task.sleep(for: duration)
        browsers.forEach { $0.cancel() }
        return collector.snapshot()
    }

    /// Browser callbacks arrive on a background queue; this keeps them
    /// thread-safe.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var adverts = Set<Advert>()
        private var models: [String: String] = [:]

        func add(_ advert: Advert) {
            lock.lock(); defer { lock.unlock() }
            adverts.insert(advert)
        }

        func addModel(_ name: String, _ model: String) {
            lock.lock(); defer { lock.unlock() }
            models[name] = model
        }

        func snapshot() -> (Set<Advert>, [String: String]) {
            lock.lock(); defer { lock.unlock() }
            return (adverts, models)
        }
    }
}

// MARK: - Liveness

/// Decides which addresses have a device behind them, without root.
///
/// Two probes run per address, and either one is enough:
/// - an ICMP echo through `/sbin/ping`, which is setuid and so works for any
///   user;
/// - a TCP connection to a few common ports. A *refused* connection proves a
///   host is there just as well as an accepted one, which catches machines
///   whose firewall drops ping but still answers TCP with a reset.
nonisolated enum LivenessProbe {
    /// HTTP, HTTPS, SSH, SMB, and the iOS sync port that iPhones and iPads
    /// keep open. Together they wake most consumer devices.
    private static let ports: [UInt16] = [80, 443, 22, 445, 62078]
    private static let concurrency = 48

    static func sweep(
        _ targets: [UInt32],
        progress: @escaping @MainActor (Double) -> Void
    ) async -> [UInt32] {
        guard !targets.isEmpty else { return [] }

        return await withTaskGroup(of: (UInt32, Bool).self) { group in
            var iterator = targets.makeIterator()
            var inFlight = 0
            var alive: [UInt32] = []
            var completed = 0

            // A sliding window keeps a few dozen probes in flight instead of
            // launching a thousand processes at once.
            while inFlight < concurrency, let next = iterator.next() {
                group.addTask { (next, await isAlive(next)) }
                inFlight += 1
            }

            while let (address, isUp) = await group.next() {
                inFlight -= 1
                completed += 1
                if isUp { alive.append(address) }

                let fraction = Double(completed) / Double(targets.count)
                await progress(fraction)

                if let next = iterator.next() {
                    group.addTask { (next, await isAlive(next)) }
                    inFlight += 1
                }
            }

            return alive.sorted()
        }
    }

    private static func isAlive(_ address: UInt32) async -> Bool {
        let text = LocalSubnet.format(address)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await ping(text) }
            for port in ports {
                group.addTask { await answersTCP(text, port: port) }
            }

            for await answered in group where answered {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private static func ping(_ address: String) async -> Bool {
        guard let result = try? await ProcessRunner.run(
            "/sbin/ping", ["-n", "-q", "-c", "1", "-t", "1", address]
        ) else { return false }
        return result.succeeded
    }

    /// True when the port accepts the connection or actively refuses it.
    /// Only silence — a timeout or no route — means nobody is there.
    private static func answersTCP(_ address: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        do {
            _ = try await TCPProbe.connect(host: NWEndpoint.Host(address), port: nwPort, timeout: .milliseconds(900))
            return true
        } catch let error as NWError {
            if case .posix(let code) = error, code == .ECONNREFUSED {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
