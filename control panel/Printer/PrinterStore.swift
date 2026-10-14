import Foundation
import Observation

/// Owns printer state for the Printers page: installed queues, the selection,
/// job listings, and the result of the last action.
@MainActor
@Observable
final class PrinterStore {
    // MARK: State

    private(set) var queues: [PrinterQueue] = []
    private(set) var drivers: [PrinterDriver] = [.everywhere]
    private(set) var jobListing = ""
    private(set) var isBusy = false
    private(set) var status: StatusMessage?

    var selectedQueueName: String?

    let discovery = PrinterDiscovery()

    private let cups = CUPSController()
    private let jobs = PrintJobService()

    struct StatusMessage: Equatable {
        let text: String
        let tone: Tone

        static func success(_ text: String) -> StatusMessage { .init(text: text, tone: .success) }
        static func failure(_ text: String) -> StatusMessage { .init(text: text, tone: .warning) }
        static func info(_ text: String) -> StatusMessage { .init(text: text, tone: .neutral) }
    }

    var selectedQueue: PrinterQueue? {
        guard let selectedQueueName else { return nil }
        return queues.first { $0.name == selectedQueueName }
    }

    var defaultQueue: PrinterQueue? {
        queues.first(where: \.isDefault)
    }

    // MARK: Loading

    func load() async {
        isBusy = true
        defer { isBusy = false }

        let loaded = await Task.detached { CUPSController().loadQueues() }.value
        queues = loaded

        // Keep the current selection when it still exists, otherwise fall back
        // to the default queue.
        let selectionSurvives = selectedQueueName.map { name in
            loaded.contains { $0.name == name }
        } ?? false
        if !selectionSurvives {
            selectedQueueName = loaded.first(where: \.isDefault)?.name ?? loaded.first?.name
        }

        await loadJobs()

        if loaded.isEmpty {
            status = .info("No print queues are installed. Add a printer to get started.")
        }
    }

    func loadJobs() async {
        guard let name = selectedQueueName else {
            jobListing = ""
            return
        }
        jobListing = await Task.detached { CUPSController().jobs(for: name) }.value
    }

    func loadDrivers() async {
        drivers = await Task.detached { CUPSController().availableDrivers() }.value
    }

    /// The default driver for a transport, chosen from what is installed.
    func suggestedDriver(for transport: PrinterTransport) -> PrinterDriver {
        cups.suggestedDriver(for: transport, from: drivers)
    }

    // MARK: Queue actions

    func setDefault() async {
        guard let queue = selectedQueue else { return }
        await perform("Set \(queue.displayName) as the default printer.") {
            try self.cups.setDefault(queue.name)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard let queue = selectedQueue else { return }
        await perform(enabled ? "Resumed \(queue.displayName)." : "Paused \(queue.displayName).") {
            try self.cups.setEnabled(enabled, queueName: queue.name)
        }
    }

    func setAcceptingJobs(_ accepting: Bool) async {
        guard let queue = selectedQueue else { return }
        let message = accepting
            ? "\(queue.displayName) is accepting jobs."
            : "\(queue.displayName) is rejecting new jobs."
        await perform(message) {
            try self.cups.setAcceptingJobs(accepting, queueName: queue.name)
        }
    }

    func cancelAllJobs() async {
        guard let queue = selectedQueue else { return }
        await perform("Cancelled all jobs on \(queue.displayName).") {
            try self.cups.cancelAllJobs(queueName: queue.name)
        }
    }

    /// Takes the queue explicitly rather than acting on the current selection:
    /// the confirmation dialog is asynchronous, and the selection can move
    /// between opening it and confirming it.
    func removeQueue(_ queue: PrinterQueue) async {
        await perform("Removed the queue \(queue.displayName).") {
            try self.cups.removeQueue(queue.name)
            if self.selectedQueueName == queue.name {
                self.selectedQueueName = nil
            }
        }
    }

    // MARK: Adding

    /// Creates a queue. Returns true on success so the sheet can dismiss itself.
    func addQueue(
        name: String,
        deviceURI: String,
        driver: PrinterDriver,
        description: String,
        location: String,
        makeDefault: Bool
    ) async -> Bool {
        isBusy = true
        defer { isBusy = false }

        do {
            try cups.addQueue(
                name: name,
                deviceURI: deviceURI,
                driver: driver,
                description: description,
                location: location,
                makeDefault: makeDefault
            )
            selectedQueueName = name
            status = .success("Added the queue \(name).")
            await load()
            return true
        } catch {
            status = .failure(Self.describe(error))
            return false
        }
    }

    // MARK: Printing

    func printTestPage(route: PrintRoute) async {
        let body = Self.testPageText(route: route)
        await runPrint {
            try await self.jobs.printText(body, jobName: "Control Panel test page", route: route)
        }
    }

    func printText(_ text: String, jobName: String, route: PrintRoute, copies: Int) async {
        await runPrint {
            try await self.jobs.printText(text, jobName: jobName, route: route, copies: copies)
        }
    }

    func printFile(at url: URL, route: PrintRoute, copies: Int) async {
        await runPrint {
            try await self.jobs.printFile(at: url, route: route, copies: copies)
        }
    }

    func sendESCPOS(_ payload: Data, jobName: String, route: PrintRoute) async {
        await runPrint {
            try await self.jobs.sendESCPOS(payload, jobName: jobName, route: route)
        }
    }

    func presentSystemPrintPanel(text: String, jobName: String) {
        let printed = jobs.presentSystemPrintPanel(
            text: text,
            jobName: jobName,
            preferredQueue: selectedQueueName
        )
        status = printed
            ? .success("Handed \(jobName) to the system print panel.")
            : .info("Printing was cancelled.")
    }

    // MARK: Probing

    /// Asks an IP printer to describe itself. Used by "Test connection".
    func probe(host: String, transport: PrinterTransport, port: Int) async -> String {
        isBusy = true
        defer { isBusy = false }

        switch transport {
        case .ippEverywhere, .lpd, .bonjour:
            do {
                let client = IPPClient(host: host, port: transport == .ippEverywhere ? port : 631)
                let attributes = try await client.printerAttributes()
                var lines = [
                    "Reachable over IPP.",
                    "Name: \(attributes.name)"
                ]
                if !attributes.makeAndModel.isEmpty {
                    lines.append("Model: \(attributes.makeAndModel)")
                }
                lines.append("State: \(attributes.state)")
                if !attributes.stateReasons.isEmpty {
                    lines.append("Reasons: \(attributes.stateReasons.joined(separator: ", "))")
                }
                if !attributes.supportedFormats.isEmpty {
                    lines.append("Formats: \(attributes.supportedFormats.joined(separator: ", "))")
                }
                lines.append("Colour: \(attributes.supportsColor ? "yes" : "no") · Duplex: \(attributes.supportsDuplex ? "yes" : "no")")
                for supply in attributes.supplies {
                    lines.append("Supply \(supply.name): \(supply.levelText)")
                }
                status = .success("\(attributes.name) answered over IPP.")
                return lines.joined(separator: "\n")
            } catch {
                let message = Self.describe(error)
                status = .failure(message)
                return "IPP query failed.\n\(message)"
            }

        case .socket:
            do {
                let (nwHost, nwPort) = try RawPrinterTransport.endpoint(host: host, portText: String(port))
                let elapsed = try await RawPrinterTransport.probe(host: nwHost, port: nwPort)
                status = .success("TCP \(host):\(port) accepted a connection.")
                return """
                    Reachable over raw TCP.
                    Connected to \(host):\(port) in \(TCPProbe.milliseconds(elapsed)) ms.

                    Raw sockets do not report a model or status, so there is \
                    nothing more to read here. Use the thermal tools to send a \
                    status request if the printer speaks ESC/POS.
                    """
            } catch {
                let message = Self.describe(error)
                status = .failure(message)
                return "Raw TCP connection failed.\n\(message)"
            }
        }
    }

    func queryThermalStatus(host: String, port: Int) async -> String {
        isBusy = true
        defer { isBusy = false }

        do {
            let (nwHost, nwPort) = try RawPrinterTransport.endpoint(host: host, portText: String(port))
            let response = try await RawPrinterTransport.sendAndReceive(
                ESCPOSBuilder.statusRequest,
                host: nwHost,
                port: nwPort
            )

            guard let decoded = ESCPOSStatus(response) else {
                status = .info("The printer accepted the status request but sent no reply.")
                return "No response. Many clones ignore DLE EOT."
            }

            status = .success("Status: \(decoded.summary)")
            return decoded.summary
        } catch {
            let message = Self.describe(error)
            status = .failure(message)
            return message
        }
    }

    // MARK: Plumbing

    private func perform(_ successMessage: String, _ work: @escaping () throws -> Void) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try work()
            status = .success(successMessage)
            await load()
        } catch {
            status = .failure(Self.describe(error))
        }
    }

    private func runPrint(_ work: @escaping () async throws -> String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            status = .success(try await work())
            await loadJobs()
        } catch {
            status = .failure(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func testPageText(route: PrintRoute) -> String {
        """
        Control Panel — printer test page
        =================================

        Route:   \(route.title)
        Host:    \(Host.current().localizedName ?? "this Mac")
        User:    \(NSUserName())
        Printed: \(Date.now.formatted(date: .complete, time: .standard))

        If you can read this line, the full path from this app to the
        printer works: job submission, transport, and rendering.

        Character check: ABCDEFGHIJKLMNOPQRSTUVWXYZ
                         abcdefghijklmnopqrstuvwxyz
                         0123456789 !@#$%^&*()-=_+[]{}

        Width check (80 columns):
        12345678901234567890123456789012345678901234567890123456789012345678901234567890
        """
    }
}
