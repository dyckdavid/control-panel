import Foundation
import AppKit
import UniformTypeIdentifiers

/// Where a job should go.
enum PrintRoute: Hashable {
    /// Through a CUPS queue on this Mac. Gets driver processing, accounting,
    /// and the queue's saved options.
    case queue(String)
    /// Straight at an IP printer over IPP, with no queue involved.
    case directIPP(host: String, port: Int, path: String)
    /// Straight at an IP printer over raw TCP, with no queue involved.
    case directRaw(host: String, port: Int)

    var title: String {
        switch self {
        case .queue(let name): "Queue \(name)"
        case .directIPP(let host, let port, _): "IPP \(host):\(port)"
        case .directRaw(let host, let port): "Raw TCP \(host):\(port)"
        }
    }
}

enum PrintJobError: LocalizedError {
    case nothingToPrint
    case unreadableFile(URL)
    case rawRouteNeedsBytes
    case escposNeedsDirectSocket
    case printerCannotRenderText(host: String, formats: [String])

    var errorDescription: String? {
        switch self {
        case .nothingToPrint:
            "There is nothing to print yet."
        case .unreadableFile(let url):
            "Could not read \(url.lastPathComponent)."
        case .rawRouteNeedsBytes:
            "A raw TCP printer needs plain text or ESC/POS bytes, not a formatted document."
        case .escposNeedsDirectSocket:
            "ESC/POS cannot go through a macOS print queue — raw queues are no longer supported, and a driver queue would rewrite the control codes. Send it to the printer's IP and port instead."
        case .printerCannotRenderText(let host, let formats):
            """
            \(host) cannot render plain text itself; it accepts \
            \(formats.isEmpty ? "no text format" : formats.joined(separator: ", ")). \
            Add it as a queue and print through that instead — the driver will \
            turn the text into something this printer understands.
            """
        }
    }
}

/// Submits jobs along whichever route the user picked.
struct PrintJobService {
    let cups = CUPSController()

    // MARK: Files

    /// Prints a file the user picked from disk.
    @discardableResult
    func printFile(
        at url: URL,
        route: PrintRoute,
        copies: Int = 1
    ) async throws -> String {
        switch route {
        case .queue(let name):
            let jobID = try cups.submit(
                fileURL: url,
                queueName: name,
                copies: copies,
                title: url.lastPathComponent
            )
            return jobID.isEmpty ? "Submitted \(url.lastPathComponent) to \(name)." : jobID

        case .directIPP(let host, let port, let path):
            guard let data = try? Data(contentsOf: url) else {
                throw PrintJobError.unreadableFile(url)
            }
            let client = IPPClient(host: host, port: port, resourcePath: path)
            let format = Self.mimeType(for: url)
            let jobID = try await client.printJob(
                document: data,
                jobName: url.lastPathComponent,
                documentFormat: format,
                copies: copies
            )
            return "Sent \(url.lastPathComponent) as \(format) to \(host)."
                + (jobID.map { " Job \($0)." } ?? "")

        case .directRaw(let host, let port):
            guard let data = try? Data(contentsOf: url) else {
                throw PrintJobError.unreadableFile(url)
            }
            // A raw socket is a byte pipe. Only pass through things the printer
            // can interpret itself.
            guard Self.isRawSafe(url) else {
                throw PrintJobError.rawRouteNeedsBytes
            }
            let (nwHost, nwPort) = try RawPrinterTransport.endpoint(host: host, portText: String(port))
            for _ in 0..<max(1, copies) {
                try await RawPrinterTransport.send(data, host: nwHost, port: nwPort)
            }
            return "Sent \(data.count) bytes of \(url.lastPathComponent) to \(host):\(port)."
        }
    }

    // MARK: Text

    /// Prints plain text. For queues and IPP the text is written to a temporary
    /// file / body; for raw sockets the bytes go straight down the wire.
    @discardableResult
    func printText(
        _ text: String,
        jobName: String,
        route: PrintRoute,
        copies: Int = 1
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PrintJobError.nothingToPrint
        }

        switch route {
        case .queue(let name):
            let url = try Self.writeTemporary(text: text, jobName: jobName)
            defer { try? FileManager.default.removeItem(at: url) }
            let jobID = try cups.submit(
                fileURL: url,
                queueName: name,
                copies: copies,
                title: jobName
            )
            return jobID.isEmpty ? "Submitted \(jobName) to \(name)." : jobID

        case .directIPP(let host, let port, let path):
            let client = IPPClient(host: host, port: port, resourcePath: path)

            // Ask the printer what it accepts rather than guessing. Most
            // printers made in the last decade cannot render text/plain at
            // all — they expect PDF, PWG-raster, or a vendor language — so
            // pushing text at them as octet-stream prints pages of garbage.
            // Say so instead of doing that.
            let attributes = try? await client.printerAttributes()
            if let attributes, !attributes.acceptsPlainText {
                throw PrintJobError.printerCannotRenderText(
                    host: host,
                    formats: attributes.supportedFormats
                )
            }

            let format = attributes?.preferredTextFormat ?? "text/plain"
            let jobID = try await client.printJob(
                document: Data(text.utf8),
                jobName: jobName,
                documentFormat: format,
                copies: copies
            )
            return "Sent \(jobName) as \(format) to \(host)."
                + (jobID.map { " Job \($0)." } ?? "")

        case .directRaw(let host, let port):
            let (nwHost, nwPort) = try RawPrinterTransport.endpoint(host: host, portText: String(port))
            let payload = Data(text.utf8) + Data([0x0A])
            for _ in 0..<max(1, copies) {
                try await RawPrinterTransport.send(payload, host: nwHost, port: nwPort)
            }
            return "Sent \(payload.count) bytes to \(host):\(port)."
        }
    }

    // MARK: ESC/POS

    /// Sends ESC/POS bytes.
    ///
    /// A local CUPS queue is not an option: macOS no longer permits raw
    /// queues, and any driver queue rewrites the control bytes, so the receipt
    /// would come out as garbage. Direct TCP is the supported path.
    @discardableResult
    func sendESCPOS(
        _ payload: Data,
        jobName: String,
        route: PrintRoute
    ) async throws -> String {
        switch route {
        case .directRaw(let host, let port):
            let (nwHost, nwPort) = try RawPrinterTransport.endpoint(host: host, portText: String(port))
            try await RawPrinterTransport.send(payload, host: nwHost, port: nwPort)
            return "Sent \(payload.count) bytes to \(host):\(port)."

        case .queue:
            throw PrintJobError.escposNeedsDirectSocket

        case .directIPP(let host, let port, let path):
            let client = IPPClient(host: host, port: port, resourcePath: path)
            let jobID = try await client.printJob(
                document: payload,
                jobName: jobName,
                documentFormat: "application/octet-stream"
            )
            return "Sent \(payload.count) bytes to \(host) over IPP."
                + (jobID.map { " Job \($0)." } ?? "")
        }
    }

    // MARK: System print panel

    /// Renders text and hands it to the standard macOS print panel, so the user
    /// gets the real printer picker, paper size, and preview.
    @MainActor
    @discardableResult
    func presentSystemPrintPanel(
        text: String,
        jobName: String,
        preferredQueue: String?
    ) -> Bool {
        guard !text.isEmpty else { return false }

        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        if let preferredQueue, let printer = NSPrinter(name: preferredQueue) {
            printInfo.printer = printer
        }

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 1))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.string = text
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.jobTitle = jobName
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation.run()
    }

    // MARK: Helpers

    private static func writeTemporary(text: String, jobName: String) throws -> URL {
        let safeName = jobName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "job" : safeName)-\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: url)
        return url
    }

    private static func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return "application/octet-stream"
        }
        return type.preferredMIMEType ?? "application/octet-stream"
    }

    /// Only formats a printer can interpret without a driver are safe to shove
    /// down a raw socket.
    private static func isRawSafe(_ url: URL) -> Bool {
        ["txt", "prn", "bin", "escpos", "pcl", "ps", "zpl"]
            .contains(url.pathExtension.lowercased())
    }
}

/// The document formats the print composer offers to pick from disk.
extension UTType {
    static var printableTypes: [UTType] {
        [.pdf, .plainText, .rtf, .png, .jpeg, .data]
    }
}
