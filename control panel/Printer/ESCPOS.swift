import Foundation

/// Builds ESC/POS byte streams for thermal receipt printers.
///
/// ESC/POS is the de-facto command set for receipt printers (Epson TM series
/// and the many clones). Commands are raw control bytes, so they must reach the
/// printer unfiltered — either over a raw TCP socket or through a CUPS queue
/// created with `-m raw`.
struct ESCPOSBuilder {
    private var bytes: [UInt8] = []

    // MARK: Control sequences

    private enum Command {
        static let initialize: [UInt8] = [0x1B, 0x40]              // ESC @
        static let lineFeed: [UInt8] = [0x0A]
        static let alignLeft: [UInt8] = [0x1B, 0x61, 0x00]         // ESC a 0
        static let alignCenter: [UInt8] = [0x1B, 0x61, 0x01]       // ESC a 1
        static let alignRight: [UInt8] = [0x1B, 0x61, 0x02]        // ESC a 2
        static let boldOn: [UInt8] = [0x1B, 0x45, 0x01]            // ESC E 1
        static let boldOff: [UInt8] = [0x1B, 0x45, 0x00]           // ESC E 0
        static let underlineOn: [UInt8] = [0x1B, 0x2D, 0x01]       // ESC - 1
        static let underlineOff: [UInt8] = [0x1B, 0x2D, 0x00]      // ESC - 0
        static let normalSize: [UInt8] = [0x1D, 0x21, 0x00]        // GS ! 0
        static let doubleSize: [UInt8] = [0x1D, 0x21, 0x11]        // GS ! 17
        static let fullCut: [UInt8] = [0x1D, 0x56, 0x00]           // GS V 0
        static let partialCut: [UInt8] = [0x1D, 0x56, 0x01]        // GS V 1
        static let statusRequest: [UInt8] = [0x10, 0x04, 0x01]     // DLE EOT 1
        /// ESC p 0 t1 t2 — pulse pin 2 of the cash-drawer connector.
        static let openDrawer: [UInt8] = [0x1B, 0x70, 0x00, 0x19, 0xFA]
        /// Code page 16 (WPC1252), which matches the CP1252 encoding used below.
        static let codePage1252: [UInt8] = [0x1B, 0x74, 0x10]      // ESC t 16
    }

    enum Alignment {
        case left, center, right

        var command: [UInt8] {
            switch self {
            case .left: Command.alignLeft
            case .center: Command.alignCenter
            case .right: Command.alignRight
            }
        }
    }

    // MARK: Stand-alone payloads

    static var openDrawer: Data { Data(Command.openDrawer) }
    static var fullCut: Data { Data(Command.initialize + Command.fullCut) }
    static var partialCut: Data { Data(Command.initialize + Command.partialCut) }
    static var statusRequest: Data { Data(Command.statusRequest) }

    static func feed(lines: Int) -> Data {
        let clamped = UInt8(clamping: max(1, min(lines, 255)))
        return Data([0x1B, 0x64, clamped])       // ESC d n
    }

    // MARK: Building

    init(initialize: Bool = true) {
        if initialize {
            bytes += Command.initialize
            bytes += Command.codePage1252
        }
    }

    mutating func align(_ alignment: Alignment) {
        bytes += alignment.command
    }

    mutating func text(
        _ string: String,
        bold: Bool = false,
        underline: Bool = false,
        doubleSize: Bool = false
    ) {
        if bold { bytes += Command.boldOn }
        if underline { bytes += Command.underlineOn }
        if doubleSize { bytes += Command.doubleSize }

        bytes += Self.encode(string)

        if doubleSize { bytes += Command.normalSize }
        if underline { bytes += Command.underlineOff }
        if bold { bytes += Command.boldOff }
    }

    mutating func line(
        _ string: String = "",
        bold: Bool = false,
        underline: Bool = false,
        doubleSize: Bool = false
    ) {
        text(string, bold: bold, underline: underline, doubleSize: doubleSize)
        bytes += Command.lineFeed
    }

    /// A full-width rule, e.g. `--------------------------------`.
    mutating func rule(width: Int = 32, character: Character = "-") {
        line(String(repeating: character, count: max(1, width)))
    }

    /// A label on the left and a value flushed right within `width` columns.
    mutating func columns(_ left: String, _ right: String, width: Int = 32) {
        let padding = max(1, width - left.count - right.count)
        line(left + String(repeating: " ", count: padding) + right)
    }

    mutating func feed(lines: Int) {
        bytes += Array(Self.feed(lines: lines))
    }

    mutating func cut(partial: Bool = false) {
        bytes += partial ? Command.partialCut : Command.fullCut
    }

    mutating func openDrawer() {
        bytes += Command.openDrawer
    }

    var data: Data { Data(bytes) }

    // MARK: Encoding

    /// Thermal printers speak single-byte code pages, not UTF-8. Encode as
    /// CP1252 to match the code page selected above, and fall back to ASCII so
    /// a stray emoji can't desynchronise the byte stream.
    private static func encode(_ string: String) -> [UInt8] {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")

        if let data = normalized.data(using: .windowsCP1252) {
            return Array(data)
        }

        return normalized.unicodeScalars.map { scalar in
            scalar.isASCII ? UInt8(scalar.value) : 0x3F     // "?"
        }
    }

    // MARK: Convenience documents

    /// A self-test receipt that exercises alignment, emphasis, feed, and cut.
    static func testReceipt(title: String, subtitle: String, cut: Bool) -> Data {
        var builder = ESCPOSBuilder()
        builder.align(.center)
        builder.line(title, bold: true, doubleSize: true)
        builder.line(subtitle)
        builder.rule()
        builder.align(.left)
        builder.columns("Alignment", "left")
        builder.align(.center)
        builder.line("centered")
        builder.align(.right)
        builder.line("right")
        builder.align(.left)
        builder.rule()
        builder.line("Bold text", bold: true)
        builder.line("Underlined text", underline: true)
        builder.line("Normal text")
        builder.rule()
        builder.columns("Printed", Date.now.formatted(date: .abbreviated, time: .standard))
        builder.feed(lines: 3)
        if cut {
            builder.cut()
        }
        return builder.data
    }

    /// Wraps arbitrary user text into a receipt.
    static func receipt(
        heading: String,
        body: String,
        alignment: Alignment,
        feedLines: Int,
        cut: Bool,
        openDrawer: Bool
    ) -> Data {
        var builder = ESCPOSBuilder()

        if !heading.isEmpty {
            builder.align(.center)
            builder.line(heading, bold: true, doubleSize: true)
            builder.rule()
        }

        builder.align(alignment)
        for line in body.components(separatedBy: "\n") {
            builder.line(line)
        }

        builder.feed(lines: max(0, feedLines))
        if cut {
            builder.cut()
        }
        if openDrawer {
            builder.openDrawer()
        }

        return builder.data
    }
}

/// Decodes the one-byte reply to a DLE EOT 1 status request.
struct ESCPOSStatus {
    let raw: UInt8

    var isOnline: Bool { raw & 0b0000_1000 == 0 }
    var drawerIsOpen: Bool { raw & 0b0000_0100 != 0 }

    var summary: String {
        var parts = [isOnline ? "online" : "offline"]
        parts.append(drawerIsOpen ? "drawer open" : "drawer closed")
        parts.append(String(format: "raw 0x%02X", raw))
        return parts.joined(separator: " · ")
    }

    init?(_ data: Data) {
        guard let first = data.first else { return nil }
        raw = first
    }
}
