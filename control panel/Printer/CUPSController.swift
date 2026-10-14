import Foundation

enum CUPSError: LocalizedError {
    case toolMissing(String)
    case commandFailed(tool: String, status: Int32, message: String)
    case invalidQueueName(String)
    case driverNeedsIPP(transport: String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool):
            "The macOS printing tool \(tool) is not available on this Mac."
        case .commandFailed(let tool, let status, let message):
            message.isEmpty
                ? "\(tool) exited with status \(status)."
                : Self.clean(message, tool: tool)
        case .invalidQueueName(let reason):
            reason
        case .driverNeedsIPP(let transport):
            """
            The IPP Everywhere driver asks the printer to describe itself over \
            IPP, and a \(transport) connection cannot answer that. Choose a \
            driver instead — POS-80 for an 80 mm receipt printer, POS-58 for \
            58 mm, or one of the Zebra or DYMO entries for labels.
            """
        }
    }

    /// CUPS tools prefix their own name onto their messages, so passing the
    /// tool name through again produced "lpadmin: lpadmin: …".
    private static func clean(_ message: String, tool: String) -> String {
        var text = message
        while text.hasPrefix("\(tool): ") {
            text = String(text.dropFirst(tool.count + 2))
        }

        // "Undefined error: 0" is errno 0 formatted as a failure; it carries no
        // information and only makes the real message look truncated.
        text = text
            .replacingOccurrences(of: ": Undefined error: 0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // CUPS's own wording for a failed capability query says nothing about
        // the cause or the remedy, so replace it with something actionable.
        if text.localizedCaseInsensitiveContains("unable to query printer") {
            return """
                The printer did not answer a capability query, so the IPP \
                Everywhere driver cannot be used for it. Many receipt printers \
                advertise IPP without implementing it. Choose a driver instead — \
                POS-80 for an 80 mm receipt roll, POS-58 for 58 mm — and use the \
                Raw TCP protocol on port 9100.
                """
        }

        return "\(tool): \(text)"
    }
}

/// Wraps the CUPS command-line tools that ship with macOS.
///
/// Every call checks the exit status and surfaces stderr. The previous version
/// of this screen discarded both, which is why `lpadmin` failures looked like
/// successes.
nonisolated struct CUPSController: Sendable {
    // MARK: Tool paths

    private static let lpstat = ["/usr/bin/lpstat"]
    private static let lpoptions = ["/usr/bin/lpoptions"]
    private static let lpadmin = ["/usr/sbin/lpadmin"]
    private static let lpinfo = ["/usr/sbin/lpinfo"]
    private static let lp = ["/usr/bin/lp"]
    private static let lpq = ["/usr/bin/lpq"]
    private static let cancel = ["/usr/bin/cancel"]
    private static let cupsenable = ["/usr/sbin/cupsenable"]
    private static let cupsdisable = ["/usr/sbin/cupsdisable"]
    private static let cupsaccept = ["/usr/sbin/cupsaccept"]
    private static let cupsreject = ["/usr/sbin/cupsreject"]

    // MARK: Running

    private func tool(_ candidates: [String]) throws -> String {
        guard let path = ProcessRunner.findExecutable(candidates) else {
            throw CUPSError.toolMissing(candidates[0])
        }
        return path
    }

    /// Runs a CUPS tool and throws with stderr attached when it fails.
    @discardableResult
    private func run(_ candidates: [String], _ arguments: [String]) throws -> String {
        let path = try tool(candidates)
        let result = try ProcessRunner.runSync(path, arguments)
        guard result.terminationStatus == 0 else {
            throw CUPSError.commandFailed(
                tool: (path as NSString).lastPathComponent,
                status: result.terminationStatus,
                message: result.combinedOutput
            )
        }
        return result.standardOutput
    }

    /// Runs a tool but tolerates a non-zero exit, returning whatever it printed.
    /// `lpstat` exits non-zero simply because no printers exist.
    private func runTolerant(_ candidates: [String], _ arguments: [String]) -> String {
        guard let path = ProcessRunner.findExecutable(candidates),
              let result = try? ProcessRunner.runSync(path, arguments) else {
            return ""
        }
        return result.standardOutput.isEmpty ? result.standardError : result.standardOutput
    }

    // MARK: Reading queues

    func loadQueues() -> [PrinterQueue] {
        // `lpstat -p` exits 1 when there are no destinations at all, which is a
        // valid state rather than an error.
        let statusOutput = runTolerant(Self.lpstat, ["-p"])
        let deviceOutput = runTolerant(Self.lpstat, ["-v"])
        let defaultOutput = runTolerant(Self.lpstat, ["-d"])
        let acceptingOutput = runTolerant(Self.lpstat, ["-a"])

        let statuses = Self.parseQueueStatuses(statusOutput)
        let devices = Self.parseDeviceURIs(deviceOutput)
        let defaultName = Self.parseDefaultQueue(defaultOutput)
        let accepting = Self.parseAccepting(acceptingOutput)

        var names = Set(statuses.keys)
        names.formUnion(devices.keys)

        return names.sorted().map { name in
            let detail = runTolerant(Self.lpstat, ["-l", "-p", name])
            let options = runTolerant(Self.lpoptions, ["-p", name])
            let state = statuses[name]

            return PrinterQueue(
                name: name,
                rawStatus: state?.status ?? "Unknown",
                isEnabled: state?.isEnabled ?? true,
                isAcceptingJobs: accepting[name] ?? true,
                isDefault: defaultName == name,
                deviceURI: devices[name] ?? "",
                makeAndModel: Self.optionValue("printer-make-and-model", in: options),
                info: Self.optionValue("printer-info", in: options),
                location: Self.optionValue("printer-location", in: options),
                interfacePath: Self.field("Interface:", in: detail),
                supplies: Self.parseSupplies(in: options)
            )
        }
    }

    func jobs(for queueName: String) -> String {
        let output = runTolerant(Self.lpq, ["-P", queueName])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No queued jobs." : trimmed
    }

    // MARK: Drivers and devices

    /// Reads installed drivers from `lpinfo -m`, with IPP Everywhere first.
    ///
    /// `raw` is filtered out on purpose: `lpinfo` still lists it, but `lpadmin`
    /// refuses to create a raw queue on current macOS, so offering it would
    /// only produce a confusing failure.
    func availableDrivers() -> [PrinterDriver] {
        var drivers: [PrinterDriver] = [.everywhere]
        var seenIDs: Set<String> = ["everywhere", "raw"]
        // macOS ships some PPDs both plain and gzipped, which would otherwise
        // show up as two identical-looking entries in the picker.
        var seenNames: Set<String> = []
        let output = runTolerant(Self.lpinfo, ["-m"])

        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // Format: "<model-id><space><human readable name>"
            let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  seenIDs.insert(parts[0]).inserted,
                  seenNames.insert(parts[1]).inserted else { continue }
            drivers.append(.model(id: parts[0], name: parts[1]))
        }

        return drivers
    }

    /// Picks a sensible default driver for a transport.
    ///
    /// IPP can interrogate the printer, so driverless is right there. A raw
    /// socket cannot, and is overwhelmingly a receipt or label printer, so
    /// prefer a point-of-sale PPD and fall back to a generic one.
    func suggestedDriver(for transport: PrinterTransport, from drivers: [PrinterDriver]) -> PrinterDriver {
        if transport.supportsDriverless {
            return .everywhere
        }

        if let pos = drivers.first(where: { driver in
            guard case .model(let id, _) = driver else { return false }
            return id.contains("POS-80")
        }) {
            return pos
        }

        return drivers.first(where: \.isPointOfSale)
            ?? drivers.first { driver in
                guard case .model(_, let name) = driver else { return false }
                return name.localizedCaseInsensitiveContains("generic")
            }
            ?? .everywhere
    }

    /// Devices CUPS can see right now: USB, Bonjour, and configured backends.
    func availableDevices() -> [String] {
        runTolerant(Self.lpinfo, ["-v"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Mutating queues

    /// Creates (or reconfigures) a queue and enables it.
    func addQueue(
        name: String,
        deviceURI: String,
        driver: PrinterDriver,
        description: String,
        location: String,
        makeDefault: Bool
    ) throws {
        try Self.validate(queueName: name)
        try Self.validate(driver: driver, deviceURI: deviceURI)

        var arguments = ["-p", name, "-E", "-v", deviceURI]
        arguments += driver.lpadminArguments

        if !description.isEmpty {
            arguments += ["-D", description]
        }
        if !location.isEmpty {
            arguments += ["-L", location]
        }

        try run(Self.lpadmin, arguments)

        // `-E` before `-p` means "encrypt"; after the queue exists it means
        // "enable and accept", so issue it separately to be unambiguous.
        try run(Self.cupsenable, [name])
        try run(Self.cupsaccept, [name])

        if makeDefault {
            try setDefault(name)
        }
    }

    func removeQueue(_ name: String) throws {
        try run(Self.lpadmin, ["-x", name])
    }

    func setDefault(_ name: String) throws {
        try run(Self.lpadmin, ["-d", name])
    }

    func setEnabled(_ enabled: Bool, queueName: String) throws {
        try run(enabled ? Self.cupsenable : Self.cupsdisable, [queueName])
    }

    func setAcceptingJobs(_ accepting: Bool, queueName: String) throws {
        try run(accepting ? Self.cupsaccept : Self.cupsreject, [queueName])
    }

    func cancelAllJobs(queueName: String) throws {
        try run(Self.cancel, ["-a", queueName])
    }

    // MARK: Printing

    /// Submits a file to a queue with `lp` and returns the job id it reports.
    @discardableResult
    func submit(
        fileURL: URL,
        queueName: String,
        copies: Int = 1,
        title: String? = nil,
        options: [String: String] = [:]
    ) throws -> String {
        var arguments = ["-d", queueName, "-n", String(max(1, copies))]
        if let title, !title.isEmpty {
            arguments += ["-t", title]
        }
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            arguments += ["-o", value.isEmpty ? key : "\(key)=\(value)"]
        }
        arguments.append(fileURL.path)

        let output = try run(Self.lp, arguments)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Validation

    /// Rejects the one driver/transport combination that cannot work.
    ///
    /// `-m everywhere` makes `lpadmin` query the printer over IPP. Against a
    /// `socket://` or `lpd://` URI there is nothing to query, and `lpadmin`
    /// reports the unhelpful "Unable to query printer: Undefined error: 0".
    /// Catching it here means no UI path can trigger that message.
    static func validate(driver: PrinterDriver, deviceURI: String) throws {
        guard case .everywhere = driver else { return }
        guard !Self.speaksIPP(deviceURI: deviceURI) else { return }

        throw CUPSError.driverNeedsIPP(
            transport: PrinterConnectionKind(deviceURI: deviceURI).title
        )
    }

    /// Whether a device URI leads somewhere that can answer an IPP query.
    ///
    /// A `dnssd://` URI needs looking at rather than trusting: the same printer
    /// advertises `_ipp._tcp` and `_pdl-datastream._tcp`, and a Bonjour URI for
    /// the latter is a raw socket with no IPP behind it.
    private static func speaksIPP(deviceURI: String) -> Bool {
        let connection = PrinterConnectionKind(deviceURI: deviceURI)

        guard connection == .bonjour else {
            return connection.canAnswerIPPQuery
        }

        let lowered = deviceURI.lowercased()
        return lowered.contains("._ipp._tcp") || lowered.contains("._ipps._tcp")
    }

    static func validate(queueName name: String) throws {
        guard !name.isEmpty else {
            throw CUPSError.invalidQueueName("Enter a queue name.")
        }
        guard name.count <= 127 else {
            throw CUPSError.invalidQueueName("Queue names must be 127 characters or fewer.")
        }
        let illegal = CharacterSet(charactersIn: " \t/\\#?'\"")
        guard name.rangeOfCharacter(from: illegal) == nil else {
            throw CUPSError.invalidQueueName(
                "Queue names cannot contain spaces or any of / \\ # ? ' \" — use underscores instead."
            )
        }
    }

    // MARK: Parsing

    private struct QueueState {
        let status: String
        let isEnabled: Bool
    }

    /// Parses `lpstat -p`, whose lines look like:
    /// `printer Office_LaserJet is idle.  enabled since …`
    /// `printer Receipts disabled since …`
    private static func parseQueueStatuses(_ output: String) -> [String: QueueState] {
        var results: [String: QueueState] = [:]

        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("printer ") else { continue }

            let remainder = text.dropFirst("printer ".count)
            let parts = remainder.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first, !name.isEmpty else { continue }

            let rest = parts.count > 1 ? parts[1] : ""
            let status: String
            if let range = rest.range(of: "is ") {
                status = String(rest[range.upperBound...])
                    .components(separatedBy: ".")
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? "idle"
            } else if rest.hasPrefix("disabled") {
                status = "paused"
            } else {
                status = rest.isEmpty ? "idle" : rest
            }

            results[name] = QueueState(
                status: status,
                isEnabled: !rest.lowercased().contains("disabled since")
            )
        }

        return results
    }

    /// Parses `lpstat -v`: `device for Office_LaserJet: ipp://10.0.0.5/ipp/print`
    private static func parseDeviceURIs(_ output: String) -> [String: String] {
        var results: [String: String] = [:]

        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("device for ") else { continue }
            let remainder = text.dropFirst("device for ".count)
            let parts = remainder.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            results[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        return results
    }

    /// Parses `lpstat -a`: `Office_LaserJet accepting requests since …`
    private static func parseAccepting(_ output: String) -> [String: Bool] {
        var results: [String: Bool] = [:]

        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let name = text.split(separator: " ").first.map(String.init), !name.isEmpty else { continue }
            results[name] = !text.lowercased().contains("not accepting")
        }

        return results
    }

    private static func parseDefaultQueue(_ output: String) -> String? {
        let prefix = "system default destination: "
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func field(_ label: String, in output: String) -> String {
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix(label) {
                return String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// Reads one option out of `lpoptions -p` output, honouring single quotes
    /// around values that contain spaces.
    private static func optionValue(_ key: String, in output: String) -> String {
        guard let range = output.range(of: "\(key)=") else { return "" }
        let remainder = output[range.upperBound...]

        if remainder.first == "'" {
            let afterQuote = remainder.dropFirst()
            guard let end = afterQuote.firstIndex(of: "'") else { return String(afterQuote) }
            return String(afterQuote[..<end])
        }

        if let space = remainder.firstIndex(of: " ") {
            return String(remainder[..<space])
        }
        return String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseSupplies(in output: String) -> [PrinterSupply] {
        let names = splitList(optionValue("marker-names", in: output))
        guard !names.isEmpty else { return [] }

        let levels = splitList(optionValue("marker-levels", in: output))
            .map { Int($0) }

        return names.enumerated().map { index, name in
            PrinterSupply(name: name, level: index < levels.count ? levels[index] : nil)
        }
    }

    /// Splits a comma-separated `lpoptions` list. Values that contain spaces
    /// arrive backslash-escaped (`magenta\ cartridge`), so unescape them —
    /// otherwise supply names show up with stray backslashes in the UI.
    private static func splitList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { element in
                element
                    .replacingOccurrences(of: "\\ ", with: " ")
                    .replacingOccurrences(of: "\\", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            }
            .filter { !$0.isEmpty }
    }
}
