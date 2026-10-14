import Foundation

// MARK: - Transport

/// How a queue talks to a printer. Determines the device URI and the default
/// driver we hand to `lpadmin`.
enum PrinterTransport: String, CaseIterable, Identifiable, Sendable {
    /// Driverless IPP. What almost every network printer made since ~2015 wants.
    case ippEverywhere
    /// Raw TCP, a.k.a. JetDirect / AppSocket. What thermal receipt printers want.
    case socket
    /// Line Printer Daemon. Older network printers and print servers.
    case lpd
    /// A Bonjour service picked from discovery; CUPS resolves it itself.
    case bonjour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ippEverywhere: "IPP (driverless)"
        case .socket: "Raw TCP / JetDirect"
        case .lpd: "LPD"
        case .bonjour: "Bonjour"
        }
    }

    var detail: String {
        switch self {
        case .ippEverywhere: "Standard for modern network printers. No driver needed."
        case .socket: "Byte pass-through on port 9100. Use for ESC/POS thermal printers."
        case .lpd: "Legacy print servers and older network printers."
        case .bonjour: "Let CUPS resolve the printer by its advertised service name."
        }
    }

    var defaultPort: Int {
        switch self {
        case .ippEverywhere: 631
        case .socket: 9100
        case .lpd: 515
        case .bonjour: 0
        }
    }

    /// Whether IPP Everywhere can be used.
    ///
    /// `-m everywhere` makes `lpadmin` open an IPP capability query against the
    /// device URI. Only IPP transports can answer one: a raw socket on port
    /// 9100 and an LPD queue on 515 both carry no IPP, so `lpadmin` fails with
    /// "Unable to query printer". Those need a real driver.
    var supportsDriverless: Bool {
        switch self {
        case .ippEverywhere, .bonjour: true
        case .socket, .lpd: false
        }
    }

    /// Builds the CUPS device URI.
    func deviceURI(host: String, port: Int, queue: String) -> String {
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        switch self {
        case .ippEverywhere:
            let path = queue.isEmpty ? "ipp/print" : queue
            return "ipp://\(bracketed):\(port)/\(path)"
        case .socket:
            return "socket://\(bracketed):\(port)"
        case .lpd:
            let path = queue.isEmpty ? "" : "/\(queue)"
            return "lpd://\(bracketed)\(path)"
        case .bonjour:
            return host
        }
    }
}

// MARK: - Driver

/// A driver choice for `lpadmin`. `everywhere` is always available; everything
/// else comes from `lpinfo -m`.
///
/// There is deliberately no `raw` case. `lpinfo -m` still advertises `raw`, but
/// macOS now rejects it outright — `lpadmin` answers "Raw queues are no longer
/// supported on macOS". ESC/POS therefore cannot travel through a local queue
/// at all, and goes over a direct TCP socket instead.
nonisolated enum PrinterDriver: Hashable, Identifiable, Sendable {
    /// `-m everywhere`: IPP Everywhere, queried from the printer at add time.
    case everywhere
    /// A model string from `lpinfo -m`.
    case model(id: String, name: String)
    /// A PPD file the user picked from disk.
    case ppd(path: String)

    var id: String {
        switch self {
        case .everywhere: "everywhere"
        case .model(let id, _): "model:\(id)"
        case .ppd(let path): "ppd:\(path)"
        }
    }

    var title: String {
        switch self {
        case .everywhere: "IPP Everywhere (driverless)"
        case .model(_, let name): name
        case .ppd(let path): (path as NSString).lastPathComponent
        }
    }

    /// The `lpadmin` arguments that select this driver.
    var lpadminArguments: [String] {
        switch self {
        case .everywhere: ["-m", "everywhere"]
        case .model(let id, _): ["-m", id]
        case .ppd(let path): ["-P", path]
        }
    }

    /// Drivers that suit receipt and label printers. macOS ships PPDs for the
    /// common 58 mm and 80 mm point-of-sale widths plus Zebra and DYMO labels.
    var isPointOfSale: Bool {
        guard case .model(let id, let name) = self else { return false }
        let haystack = "\(id) \(name)".lowercased()
        return ["pos-", "pos ", "label", "zebra", "dymo", "intellibar"]
            .contains { haystack.contains($0) }
    }
}

// MARK: - Supplies

struct PrinterSupply: Identifiable, Hashable, Sendable {
    let name: String
    let level: Int?

    var id: String { name }

    var levelText: String {
        guard let level else { return "—" }
        return "\(level)%"
    }

    var isLow: Bool {
        guard let level else { return false }
        return level >= 0 && level <= 15
    }
}

// MARK: - Queue

/// A CUPS print queue installed on this Mac.
struct PrinterQueue: Identifiable, Hashable, Sendable {
    let name: String
    var rawStatus: String = ""
    var isEnabled: Bool = true
    var isAcceptingJobs: Bool = true
    var isDefault: Bool = false
    var deviceURI: String = ""
    var makeAndModel: String = ""
    var info: String = ""
    var location: String = ""
    var interfacePath: String = ""
    var supplies: [PrinterSupply] = []

    var id: String { name }

    /// CUPS queue names cannot contain spaces, so underscores stand in for them.
    var displayName: String {
        info.isEmpty ? name.replacingOccurrences(of: "_", with: " ") : info
    }

    var connection: PrinterConnectionKind {
        PrinterConnectionKind(deviceURI: deviceURI)
    }

    /// Host or IP parsed out of the device URI, when there is one.
    ///
    /// USB URIs look like `usb://Canon/iP110%20series`, where the "host" is the
    /// manufacturer, not an address — so those report nothing. Bonjour URIs
    /// parse as a host too, but it is the full mDNS instance name, so those go
    /// through `bonjourServiceName` to get something readable.
    var host: String? {
        guard !deviceURI.isEmpty else { return nil }

        switch connection {
        case .usb, .unknown:
            return nil
        case .bonjour:
            return bonjourServiceName
        default:
            guard let components = URLComponents(string: deviceURI),
                  let host = components.host,
                  !host.isEmpty else {
                return nil
            }
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
    }

    var port: Int? {
        URLComponents(string: deviceURI)?.port ?? connection.defaultPort
    }

    /// For `dnssd://Printer%20Name._ipp._tcp.local./…` URIs there is no host, so
    /// pull the advertised service name out instead.
    private var bonjourServiceName: String? {
        guard let range = deviceURI.range(of: "._tcp.local.") else { return nil }
        let prefix = deviceURI[..<range.lowerBound]
        guard let slash = prefix.lastIndex(of: "/") else { return nil }
        var name = String(prefix[prefix.index(after: slash)...])
        // Strip the trailing `._ipp` / `._pdl-datastream` service-type fragment.
        if let dot = name.range(of: "._", options: .backwards) {
            name = String(name[..<dot.lowerBound])
        }
        return name.removingPercentEncoding ?? name
    }

    var adminURL: URL? {
        guard let host, !host.contains(" "), connection.isNetwork else { return nil }
        return URL(string: "http://\(host)")
    }

    var cupsURL: URL? {
        URL(string: "http://localhost:631/printers/\(name)")
    }

    /// Whether this queue was created with `-m raw`, i.e. bytes pass straight
    /// through. Only raw queues can carry ESC/POS.
    var isRawQueue: Bool {
        makeAndModel.localizedCaseInsensitiveContains("raw")
            || makeAndModel.isEmpty && connection == .socket
    }

    var statusTone: Tone {
        if !isEnabled { return .warning }
        if !isAcceptingJobs { return .warning }
        if rawStatus.localizedCaseInsensitiveContains("idle") { return .success }
        if rawStatus.localizedCaseInsensitiveContains("printing") { return .accent }
        return .neutral
    }

    var statusSummary: String {
        var parts: [String] = []
        if !rawStatus.isEmpty { parts.append(rawStatus) }
        if !isEnabled { parts.append("paused") }
        if !isAcceptingJobs { parts.append("rejecting jobs") }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " · ")
    }
}

// MARK: - Connection kind

enum PrinterConnectionKind: String, Sendable {
    case usb
    case socket
    case ipp
    case ipps
    case bonjour
    case lpd
    case smb
    case unknown

    init(deviceURI: String) {
        let scheme = deviceURI
            .components(separatedBy: "://")
            .first?
            .lowercased() ?? ""

        switch scheme {
        case "usb": self = .usb
        case "socket": self = .socket
        case "ipps": self = .ipps
        case "ipp", "http", "https": self = .ipp
        case "dnssd", "mdns": self = .bonjour
        case "lpd": self = .lpd
        case "smb": self = .smb
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .usb: "USB"
        case .socket: "Raw TCP"
        case .ipp: "IPP"
        case .ipps: "IPP (TLS)"
        case .bonjour: "Bonjour"
        case .lpd: "LPD"
        case .smb: "SMB"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .usb: "cable.connector"
        case .socket: "app.connected.to.app.below.fill"
        case .ipp, .ipps, .lpd, .smb: "network"
        case .bonjour: "dot.radiowaves.left.and.right"
        case .unknown: "printer"
        }
    }

    var isNetwork: Bool {
        switch self {
        case .usb, .unknown: false
        default: true
        }
    }

    /// Whether a queue on this transport can answer an IPP capability query,
    /// which is what the `everywhere` driver depends on.
    var canAnswerIPPQuery: Bool {
        switch self {
        case .ipp, .ipps, .bonjour: true
        case .usb, .socket, .lpd, .smb, .unknown: false
        }
    }

    var defaultPort: Int? {
        switch self {
        case .socket: 9100
        case .ipp, .ipps: 631
        case .lpd: 515
        default: nil
        }
    }
}

// MARK: - Discovery

/// A printer advertised on the local network over Bonjour.
struct DiscoveredPrinter: Identifiable, Hashable, Sendable {
    /// Bonjour instance name, e.g. "HP LaserJet 400".
    let serviceName: String
    /// Bonjour service type, e.g. `_ipp._tcp`.
    let serviceType: String
    let domain: String
    /// Resolved address, filled in once we probe the endpoint.
    var host: String?
    var port: Int?

    var id: String { "\(serviceName).\(serviceType).\(domain)" }

    var transport: PrinterTransport {
        serviceType.contains("pdl-datastream") ? .socket : .ippEverywhere
    }

    var kindTitle: String {
        switch serviceType {
        case let type where type.contains("ipps"): "IPP over TLS"
        case let type where type.contains("ipp"): "IPP"
        case let type where type.contains("pdl-datastream"): "Raw TCP (port 9100)"
        case let type where type.contains("printer"): "LPD"
        default: serviceType
        }
    }

    /// The `dnssd://` URI CUPS uses to talk to a Bonjour printer without us
    /// having to resolve an address.
    ///
    /// The domain carries a trailing dot (`local.`) to match the form macOS
    /// writes itself, so a queue added here is indistinguishable from one added
    /// in System Settings.
    var bonjourDeviceURI: String {
        let encodedName = serviceName
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? serviceName
        return "dnssd://\(encodedName).\(serviceType).\(domain)./"
    }

    /// Ranks service types so the best one wins when a printer advertises
    /// several. Plain IPP first: it is what `-m everywhere` speaks, and unlike
    /// IPPS it needs no decision about the printer's self-signed certificate.
    var preferenceRank: Int {
        switch serviceType {
        case let type where type.hasPrefix("_ipp."): 0
        case let type where type.hasPrefix("_ipps."): 1
        case let type where type.hasPrefix("_pdl-datastream."): 2
        default: 3
        }
    }

    /// A queue name CUPS will accept: no spaces, slashes, or `#`.
    var suggestedQueueName: String {
        let allowed = serviceName.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let collapsed = String(allowed)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return collapsed.isEmpty ? "Printer" : collapsed
    }
}

/// One physical printer, with every service type it advertises.
///
/// A single printer typically shows up on Bonjour three or four times — once
/// each for `_ipp`, `_ipps`, `_pdl-datastream`, and sometimes `_printer`.
/// Listing those separately would show the same device four times, so they are
/// grouped by advertised name.
struct DiscoveredPrinterGroup: Identifiable, Hashable, Sendable {
    let name: String
    let services: [DiscoveredPrinter]

    var id: String { name }

    /// The service to add a queue for by default.
    var preferredService: DiscoveredPrinter {
        services.min { $0.preferenceRank < $1.preferenceRank } ?? services[0]
    }

    var host: String? { services.compactMap(\.host).first }
    var port: Int? { preferredService.port }

    /// Short protocol labels for display, e.g. ["IPP", "IPPS", "Raw TCP"].
    var protocolLabels: [String] {
        services
            .sorted { $0.preferenceRank < $1.preferenceRank }
            .map { service in
                switch service.serviceType {
                case let type where type.hasPrefix("_ipps."): "IPPS"
                case let type where type.hasPrefix("_ipp."): "IPP"
                case let type where type.hasPrefix("_pdl-datastream."): "Raw TCP"
                case let type where type.hasPrefix("_printer."): "LPD"
                default: service.serviceType
                }
            }
    }

    /// Whether this printer can take ESC/POS over a direct socket.
    var supportsRawSocket: Bool {
        rawSocketService != nil
    }

    /// The raw-socket advertisement, used as a fallback when the printer's IPP
    /// support turns out to be nominal.
    var rawSocketService: DiscoveredPrinter? {
        services.first { $0.serviceType.hasPrefix("_pdl-datastream.") }
    }
}
