import Foundation

enum IPPError: LocalizedError {
    case invalidHost
    case transportFailed(String)
    case badResponse
    case printerRejected(code: UInt16, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "Enter a valid printer host name or IP address."
        case .transportFailed(let detail):
            "Could not reach the printer over IPP: \(detail)"
        case .badResponse:
            "The printer replied with something that is not a valid IPP response."
        case .printerRejected(let code, let message):
            message.isEmpty
                ? "The printer rejected the request (IPP status 0x\(String(code, radix: 16)))."
                : "The printer rejected the request: \(message)"
        }
    }
}

/// A minimal IPP/2.0 client: enough to interrogate a printer and hand it a
/// document, without CUPS or a local queue in the way.
///
/// This is the path that makes "print to an IP printer" work even when nothing
/// has been installed on the Mac yet, and it is also how the add-printer flow
/// confirms that a host really is a printer before creating a queue.
///
/// Only cleartext IPP (port 631 over HTTP) is implemented. `ipps://` needs TLS
/// trust decisions for the self-signed certificates printers ship with, so TLS
/// printing is left to CUPS, which already has that policy.
struct IPPClient {
    let host: String
    var port: Int = 631
    /// Resource path on the printer. `/ipp/print` is the IPP Everywhere default.
    var resourcePath: String = "/ipp/print"
    var timeout: TimeInterval = 15

    private var printerURI: String {
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "ipp://\(bracketed):\(port)\(resourcePath)"
    }

    private var endpoint: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = resourcePath
        return components.url
    }

    // MARK: Operations

    /// `Get-Printer-Attributes`. Used to verify a host is a printer and to read
    /// its name, state, and the document formats it accepts.
    func printerAttributes() async throws -> IPPPrinterAttributes {
        var request = IPPRequestBuilder(operation: .getPrinterAttributes, requestID: Self.nextRequestID())
        request.addOperationAttributes(printerURI: printerURI, jobName: nil, documentFormat: nil)
        request.addKeyword(name: "requested-attributes", values: [
            "printer-name",
            "printer-make-and-model",
            "printer-state",
            "printer-state-reasons",
            "printer-info",
            "printer-location",
            "document-format-supported",
            "media-default",
            "color-supported",
            "sides-supported",
            "marker-names",
            "marker-levels"
        ])
        request.finish()

        let response = try await send(body: request.data)
        return IPPPrinterAttributes(response.attributes)
    }

    /// `Print-Job`: submit a document in one request.
    @discardableResult
    func printJob(
        document: Data,
        jobName: String,
        documentFormat: String,
        copies: Int = 1
    ) async throws -> Int? {
        var request = IPPRequestBuilder(operation: .printJob, requestID: Self.nextRequestID())
        request.addOperationAttributes(
            printerURI: printerURI,
            jobName: jobName,
            documentFormat: documentFormat
        )
        if copies > 1 {
            request.beginJobAttributes()
            request.addInteger(name: "copies", value: copies)
        }
        request.finish()

        let response = try await send(body: request.data + document)
        return response.attributes["job-id"]
            .flatMap { $0.first }
            .flatMap { Int($0) }
    }

    // MARK: Transport

    private func send(body: Data) async throws -> IPPResponse {
        guard let endpoint, !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw IPPError.invalidHost
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/ipp", forHTTPHeaderField: "Content-Type")
        request.setValue("Control Panel", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IPPError.transportFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IPPError.transportFailed("HTTP \(http.statusCode) from \(endpoint.absoluteString)")
        }

        guard let parsed = IPPResponse(data) else {
            throw IPPError.badResponse
        }

        // IPP status codes below 0x0100 are "successful-*".
        guard parsed.statusCode < 0x0100 else {
            let message = parsed.attributes["status-message"]?.first ?? ""
            throw IPPError.printerRejected(code: parsed.statusCode, message: message)
        }

        return parsed
    }

    /// IPP request ids must be non-zero and let us match a reply to its
    /// request. This client never has more than one request in flight, so a
    /// timestamp is sufficient and needs no shared state.
    ///
    /// RFC 8010 limits the id to a signed 32-bit positive integer, so it is
    /// masked into 1...2^31-1. Letting it run past that makes strict printers
    /// answer `client-error-bad-request` (0x0400).
    private static func nextRequestID() -> UInt32 {
        let seconds = UInt32(truncatingIfNeeded: Int(Date.now.timeIntervalSince1970))
        return (seconds & 0x7FFF_FFFF) | 1
    }
}

// MARK: - Request encoding

/// Encodes an IPP request per RFC 8010.
///
/// Layout: version (2 bytes), operation id (2), request id (4), then attribute
/// groups introduced by a delimiter tag, then `end-of-attributes` (0x03).
/// Each attribute is: value tag (1), name length (2), name, value length (2),
/// value. A name length of zero means "another value for the previous
/// attribute", which is how multi-valued attributes are expressed.
struct IPPRequestBuilder {
    enum Operation: UInt16 {
        case printJob = 0x0002
        case getPrinterAttributes = 0x000B
    }

    private enum Tag {
        static let operationAttributes: UInt8 = 0x01
        static let jobAttributes: UInt8 = 0x02
        static let endOfAttributes: UInt8 = 0x03

        static let integer: UInt8 = 0x21
        static let keyword: UInt8 = 0x44
        static let uri: UInt8 = 0x45
        static let charset: UInt8 = 0x47
        static let naturalLanguage: UInt8 = 0x48
        static let mimeMediaType: UInt8 = 0x49
        static let nameWithoutLanguage: UInt8 = 0x42
    }

    private var bytes = Data()

    init(operation: Operation, requestID: UInt32) {
        bytes.append(contentsOf: [0x02, 0x00])                  // version 2.0
        bytes.append(uint16: operation.rawValue)
        bytes.append(uint32: requestID)
        bytes.append(Tag.operationAttributes)
    }

    /// The three attributes every IPP request must open with, in this order,
    /// plus the job-specific ones when present.
    mutating func addOperationAttributes(printerURI: String, jobName: String?, documentFormat: String?) {
        append(tag: Tag.charset, name: "attributes-charset", value: "utf-8")
        append(tag: Tag.naturalLanguage, name: "attributes-natural-language", value: "en")
        append(tag: Tag.uri, name: "printer-uri", value: printerURI)
        append(tag: Tag.nameWithoutLanguage, name: "requesting-user-name", value: NSUserName())

        if let jobName, !jobName.isEmpty {
            append(tag: Tag.nameWithoutLanguage, name: "job-name", value: jobName)
        }
        if let documentFormat, !documentFormat.isEmpty {
            append(tag: Tag.mimeMediaType, name: "document-format", value: documentFormat)
        }
    }

    mutating func addKeyword(name: String, values: [String]) {
        guard let first = values.first else { return }
        append(tag: Tag.keyword, name: name, value: first)
        for extra in values.dropFirst() {
            // Zero-length name = additional value for the preceding attribute.
            append(tag: Tag.keyword, name: "", value: extra)
        }
    }

    mutating func beginJobAttributes() {
        bytes.append(Tag.jobAttributes)
    }

    mutating func addInteger(name: String, value: Int) {
        bytes.append(Tag.integer)
        let nameBytes = Data(name.utf8)
        bytes.append(uint16: UInt16(nameBytes.count))
        bytes.append(nameBytes)
        bytes.append(uint16: 4)
        bytes.append(uint32: UInt32(truncatingIfNeeded: value))
    }

    mutating func finish() {
        bytes.append(Tag.endOfAttributes)
    }

    var data: Data { bytes }

    private mutating func append(tag: UInt8, name: String, value: String) {
        bytes.append(tag)
        let nameBytes = Data(name.utf8)
        bytes.append(uint16: UInt16(nameBytes.count))
        bytes.append(nameBytes)
        let valueBytes = Data(value.utf8)
        bytes.append(uint16: UInt16(valueBytes.count))
        bytes.append(valueBytes)
    }
}

// MARK: - Response decoding

/// A decoded IPP response. Attribute values are kept as strings because this
/// client only needs them for display and for a handful of integer lookups.
struct IPPResponse {
    let statusCode: UInt16
    let requestID: UInt32
    let attributes: [String: [String]]

    init?(_ data: Data) {
        guard data.count >= 8 else { return nil }

        let bytes = [UInt8](data)
        statusCode = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        requestID = UInt32(bytes[4]) << 24
            | UInt32(bytes[5]) << 16
            | UInt32(bytes[6]) << 8
            | UInt32(bytes[7])

        var index = 8
        var parsed: [String: [String]] = [:]
        var currentName = ""

        while index < bytes.count {
            let tag = bytes[index]
            index += 1

            // 0x00...0x05 are delimiter tags (group boundaries / end).
            if tag == 0x03 { break }
            if tag <= 0x05 {
                currentName = ""
                continue
            }

            guard index + 2 <= bytes.count else { break }
            let nameLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2

            guard index + nameLength <= bytes.count else { break }
            if nameLength > 0 {
                currentName = String(decoding: bytes[index..<(index + nameLength)], as: UTF8.self)
                index += nameLength
            }

            guard index + 2 <= bytes.count else { break }
            let valueLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2

            guard index + valueLength <= bytes.count else { break }
            let valueBytes = Array(bytes[index..<(index + valueLength)])
            index += valueLength

            guard !currentName.isEmpty else { continue }
            parsed[currentName, default: []].append(Self.describe(tag: tag, bytes: valueBytes))
        }

        attributes = parsed
    }

    /// Renders a value according to its syntax tag. Integers, booleans, and
    /// enums are binary; everything else this client cares about is text.
    private static func describe(tag: UInt8, bytes: [UInt8]) -> String {
        switch tag {
        case 0x21, 0x23:    // integer, enum
            guard bytes.count == 4 else { return "" }
            let value = Int32(bitPattern:
                UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            )
            return String(value)
        case 0x22:          // boolean
            return bytes.first == 1 ? "true" : "false"
        case 0x32, 0x33:    // rangeOfInteger, dateTime — not needed, show raw
            return bytes.map { String(format: "%02X", $0) }.joined()
        default:
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}

/// The subset of printer attributes the UI displays.
struct IPPPrinterAttributes {
    let name: String
    let makeAndModel: String
    let state: String
    let stateReasons: [String]
    let location: String
    let supportedFormats: [String]
    let supportsColor: Bool
    let supportsDuplex: Bool
    let supplies: [PrinterSupply]

    init(_ attributes: [String: [String]]) {
        name = attributes["printer-name"]?.first
            ?? attributes["printer-info"]?.first
            ?? "Unnamed printer"
        makeAndModel = attributes["printer-make-and-model"]?.first ?? ""
        location = attributes["printer-location"]?.first ?? ""
        stateReasons = attributes["printer-state-reasons"] ?? []
        supportedFormats = attributes["document-format-supported"] ?? []
        supportsColor = attributes["color-supported"]?.first == "true"
        supportsDuplex = (attributes["sides-supported"] ?? []).contains { $0.contains("two-sided") }

        // printer-state is an enum: 3 idle, 4 processing, 5 stopped.
        switch attributes["printer-state"]?.first {
        case "3": state = "Idle"
        case "4": state = "Printing"
        case "5": state = "Stopped"
        default: state = "Unknown"
        }

        let names = attributes["marker-names"] ?? []
        let levels = attributes["marker-levels"] ?? []
        supplies = names.enumerated().map { index, markerName in
            PrinterSupply(
                name: markerName,
                level: index < levels.count ? Int(levels[index]) : nil
            )
        }
    }

    /// Whether the printer told us it can render plain text itself. Printers
    /// that only accept PDF/PWG need a driver, so we route those through CUPS.
    var acceptsPlainText: Bool {
        supportedFormats.contains("text/plain")
    }

    var acceptsPDF: Bool {
        supportedFormats.contains("application/pdf")
    }

    /// The best document format to send for a text document.
    var preferredTextFormat: String {
        if acceptsPlainText { return "text/plain" }
        if supportedFormats.contains("application/octet-stream") { return "application/octet-stream" }
        return supportedFormats.first ?? "application/octet-stream"
    }
}

// MARK: - Byte helpers

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [
            UInt8(value >> 24 & 0xFF),
            UInt8(value >> 16 & 0xFF),
            UInt8(value >> 8 & 0xFF),
            UInt8(value & 0xFF)
        ])
    }
}
