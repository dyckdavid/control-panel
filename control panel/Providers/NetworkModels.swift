import Foundation

struct NetworkInterface: Identifiable, Hashable, Sendable {
    let name: String
    let address: String
    let family: String

    var id: String { "\(name)-\(family)-\(address)" }

    var isIPv6: Bool { family == "IPv6" }
}

struct HardwarePort: Identifiable, Hashable, Sendable {
    let name: String
    let device: String
    let address: String

    var id: String { device }
}

struct NetworkDevice: Identifiable, Hashable, Sendable {
    let ipAddress: String
    let mac: MACAddress?
    let interface: String
    /// Best available name: Bonjour instance name, then reverse DNS.
    var name: String?
    var nameSource: NameSource?
    var vendor: String?
    /// Model identifier from Bonjour `_device-info`, e.g. `MacBookPro18,3`.
    var model: String?
    /// Bonjour service types the device advertises, e.g. `_airplay._tcp`.
    var services: [String] = []
    var isThisMac = false
    var isGateway = false

    enum NameSource: String, Sendable {
        case bonjour = "Bonjour"
        case reverseDNS = "DNS"
    }

    var id: String { ipAddress }

    var macText: String { mac?.canonical ?? "—" }

    var hasName: Bool { !(name ?? "").isEmpty }

    var title: String {
        if let name, !name.isEmpty { return name }
        if isThisMac { return "This Mac" }
        if isGateway { return "Router" }
        return ipAddress
    }

    /// A short manufacturer line. Randomised private addresses have no vendor,
    /// and saying so is more useful than a blank.
    var vendorText: String? {
        if let vendor { return vendor }
        if mac?.isLocallyAdministered == true { return "Private address" }
        return nil
    }

    var kind: Kind {
        if isThisMac { return .mac }
        if isGateway { return .router }
        let model = (model ?? "").lowercased()
        let joined = services.joined(separator: " ")

        if model.hasPrefix("iphone") { return .phone }
        if model.hasPrefix("ipad") { return .tablet }
        if model.hasPrefix("watch") { return .watch }
        if model.hasPrefix("appletv") || model.hasPrefix("audioaccessory") { return .tv }
        if model.hasPrefix("mac") || model.hasPrefix("imac") { return .mac }
        if joined.contains("_ipp.") || joined.contains("_printer.") || joined.contains("_pdl-datastream.") { return .printer }
        if joined.contains("_googlecast.") || joined.contains("_airplay.") { return .tv }
        if joined.contains("_hap.") || joined.contains("_homekit.") { return .accessory }
        if joined.contains("_smb.") || joined.contains("_afpovertcp.") { return .server }
        return .unknown
    }

    enum Kind {
        case mac, phone, tablet, watch, tv, printer, accessory, server, router, unknown

        var symbol: String {
            switch self {
            case .mac: "desktopcomputer"
            case .phone: "iphone"
            case .tablet: "ipad"
            case .watch: "applewatch"
            case .tv: "tv"
            case .printer: "printer"
            case .accessory: "homekit"
            case .server: "externaldrive.connected.to.line.below"
            case .router: "wifi.router"
            case .unknown: "questionmark.square.dashed"
            }
        }
    }
}

/// The IPv4 network this Mac is on, derived from its address and netmask.
nonisolated struct LocalSubnet: Sendable, Equatable {
    let interface: String
    let address: UInt32
    let netmask: UInt32

    var network: UInt32 { address & netmask }
    var broadcast: UInt32 { network | ~netmask }
    var prefixLength: Int { netmask.nonzeroBitCount }

    /// Usable host addresses, excluding network and broadcast.
    var hostCount: Int { prefixLength >= 31 ? 0 : Int(broadcast - network) - 1 }

    var cidr: String { "\(Self.format(network))/\(prefixLength)" }
    var addressText: String { Self.format(address) }

    func contains(_ ip: UInt32) -> Bool { ip & netmask == network }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    static func parse(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return nil }
        return parts.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

struct NetworkServiceDetails: Identifiable, Hashable, Sendable {
    let serviceName: String
    let configuration: String
    let ipAddress: String
    let subnetMask: String
    let router: String
    let macAddress: String
    let dnsServers: [String]

    var id: String { serviceName }

    var usesDHCP: Bool {
        configuration.localizedCaseInsensitiveContains("dhcp")
    }
}
