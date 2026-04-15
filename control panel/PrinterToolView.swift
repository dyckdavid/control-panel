import SwiftUI
import Foundation
import Combine
import Network
import WebKit

struct PrinterToolView: View {
    let navigateBack: () -> Void

    @StateObject private var manager = PrinterManager()
    @State private var queueName = ""
    @State private var printerHost = ""
    @State private var printerPort = "9100"
    @State private var selectedProtocol: PrinterQueueProtocol = .ippEverywhere
    @State private var makeDefault = false
    @State private var thermalHost = ""
    @State private var thermalPort = "9100"
    @State private var feedLines = "3"
    @State private var webAdminURL = ""
    private let actionColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overviewSection
                printerListSection
                queueManagementSection
                jobQueueSection
                addPrinterSection
                thermalControlsSection
                webAdminSection
                supportNotesSection
            }
            .padding(24)
        }
        .task {
            await manager.refresh()
            await manager.loadSelectedPrinterDetails()
            syncSelectedPrinterState()
        }
        .onChange(of: manager.selectedPrinterName) { _, _ in
            syncSelectedPrinterState()
            Task {
                await manager.loadSelectedPrinterDetails()
            }
        }
    }

    private var header: some View {
        HeaderBlock(
            title: "Printers",
            subtitle: "Manage queues, inspect status, open printer admin pages, and use thermal-printer actions when supported."
        ) {
            Button("Back", systemImage: "chevron.left", action: navigateBack)
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task {
                    await manager.refresh()
                    await manager.loadSelectedPrinterDetails()
                }
            }
            .buttonStyle(.borderedProminent)
            if manager.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var overviewSection: some View {
        SectionCard("Overview") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                StatCard(
                    title: "Queues",
                    value: "\(manager.printers.count)",
                    detail: "Printers available on this Mac"
                )
                StatCard(
                    title: "Selected",
                    value: manager.selectedPrinter?.displayName ?? "None",
                    detail: manager.selectedPrinter?.connectionSummary ?? "Choose a printer to continue"
                )
            }

            if !manager.statusMessage.isEmpty {
                StatusBanner(
                    message: manager.statusMessage,
                    tone: manager.statusMessage.localizedCaseInsensitiveContains("failed") ? .warning : .success
                )
            } else {
                StatusBanner(message: "Select a printer to see actions and connection details.", tone: .neutral)
            }
        }
    }

    private var printerListSection: some View {
        SectionCard("Queues") {
            VStack(alignment: .leading, spacing: 16) {
                if manager.printers.isEmpty {
                    Text("No printers found. Add a queue below or connect a printer first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.printers) { printer in
                        Button {
                            manager.selectedPrinterName = printer.name
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: printer.iconName)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(printer.displayName)
                                            .font(.headline)
                                        if printer.isDefault {
                                            Text("Default")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.thinMaterial, in: Capsule())
                                        }
                                    }

                                    Text(printer.status)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    LabeledContent("Connection", value: printer.connectionSummary)
                                        .font(.caption)

                                    if !printer.makeAndModel.isEmpty {
                                        LabeledContent("Model", value: printer.makeAndModel)
                                            .font(.caption)
                                    }

                                    if !printer.deviceURI.isEmpty {
                                        Text(printer.deviceURI)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .lineLimit(2)
                                            .truncationMode(.middle)
                                    }

                                    if !printer.supplies.isEmpty {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                                            ForEach(printer.supplies) { supply in
                                                Text("\(supply.name): \(supply.levelText)")
                                                    .font(.caption)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(.thinMaterial, in: Capsule())
                                            }
                                        }
                                    }
                                }

                                Spacer()
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(manager.selectedPrinterName == printer.name ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var queueManagementSection: some View {
        SectionCard("Selected Printer") {
            VStack(alignment: .leading, spacing: 16) {
                if let printer = manager.selectedPrinter {
                    KeyValueRow(title: "Queue", value: printer.displayName)
                    KeyValueRow(title: "Connection", value: printer.connectionSummary)
                    if printer.hostDisplay != "Unavailable" {
                        KeyValueRow(title: "Host", value: printer.hostDisplay)
                    }
                    if !printer.descriptionText.isEmpty {
                        KeyValueRow(title: "Description", value: printer.descriptionText)
                    }
                    if !printer.interfacePath.isEmpty {
                        KeyValueRow(title: "PPD / Interface", value: printer.interfacePath)
                    }
                } else {
                    Text("Select a printer to manage queue actions.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 12) {
                    Button("Set Default") {
                        Task {
                            await manager.setDefaultPrinter()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Pause Queue") {
                        Task {
                            await manager.pauseSelectedPrinter()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Resume Queue") {
                        Task {
                            await manager.resumeSelectedPrinter()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Accept Jobs") {
                        Task {
                            await manager.acceptJobs()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Reject Jobs") {
                        Task {
                            await manager.rejectJobs()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Print Test Page") {
                        Task {
                            await manager.printTestPage()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)

                    Button("Remove Queue", role: .destructive) {
                        Task {
                            await manager.removeSelectedPrinter()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)
                }

                if manager.selectedPrinter != nil {
                    Button("Cancel All Jobs") {
                        Task {
                            await manager.cancelAllJobs()
                        }
                    }
                    .disabled(manager.isBusy)
                }
            }
        }
    }

    private var jobQueueSection: some View {
        SectionCard("Queue Status") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Pending Jobs")
                        .font(.headline)
                    Spacer()
                    Button("Refresh Jobs") {
                        Task {
                            await manager.loadSelectedPrinterDetails()
                        }
                    }
                    .disabled(manager.selectedPrinter == nil || manager.isBusy)
                }

                if manager.jobOutput.isEmpty {
                    Text("Select a printer to inspect its queue.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(manager.jobOutput)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }
        }
    }

    private var addPrinterSection: some View {
        SectionCard("Add Printer") {
            DisclosureGroup("Show network queue setup") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Create a printer queue for an IPP or raw-socket printer already on your network.")
                        .foregroundStyle(.secondary)

                    TextField("Queue Name", text: $queueName)
                    TextField("Printer Host or IP", text: $printerHost)

                    HStack {
                        Picker("Protocol", selection: $selectedProtocol) {
                            ForEach(PrinterQueueProtocol.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Port", text: $printerPort)
                            .frame(width: 100)
                    }

                    Toggle("Set as default after adding", isOn: $makeDefault)

                    Button("Add Printer Queue") {
                        Task {
                            await manager.addNetworkPrinter(
                                queueName: queueName,
                                host: printerHost,
                                portText: printerPort,
                                protocolType: selectedProtocol,
                                makeDefault: makeDefault
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || printerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                }
            }
            .disclosureGroupStyle(.automatic)
            .tint(.primary)
        }
    }

    private var thermalControlsSection: some View {
        SectionCard("Thermal Printer Tools") {
            DisclosureGroup("Show thermal actions") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Use these only with compatible ESC/POS thermal printers on the network.")
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Thermal Printer Host", text: $thermalHost)
                        TextField("Port", text: $thermalPort)
                            .frame(width: 100)
                    }

                    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 12) {
                        Button("Open Drawer") {
                            Task {
                                await manager.openDrawer(host: thermalHost, portText: thermalPort)
                            }
                        }

                        Button("Full Cut") {
                            Task {
                                await manager.fullCut(host: thermalHost, portText: thermalPort)
                            }
                        }

                        Button("Partial Cut") {
                            Task {
                                await manager.partialCut(host: thermalHost, portText: thermalPort)
                            }
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        TextField("Feed Lines", text: $feedLines)
                            .frame(width: 100)

                        Button("Feed Paper") {
                            Task {
                                await manager.feedPaper(host: thermalHost, portText: thermalPort, linesText: feedLines)
                            }
                        }

                        Button("Status Query") {
                            Task {
                                await manager.queryThermalStatus(host: thermalHost, portText: thermalPort)
                            }
                        }
                    }
                }
            }
        }
    }

    private var webAdminSection: some View {
        SectionCard("Network & Web Admin") {
            DisclosureGroup("Show web admin") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Use the printer’s local admin page for network settings like DHCP, static IP, DNS, maintenance, and device-specific options.")
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Admin URL", text: $webAdminURL)

                        Button("Use Selected Printer") {
                            if let selected = manager.selectedPrinter, let defaultURL = selected.defaultAdminURL {
                                webAdminURL = defaultURL
                            }
                        }
                        .disabled(manager.selectedPrinter?.defaultAdminURL == nil)

                        Button("Use CUPS") {
                            if let selected = manager.selectedPrinter {
                                webAdminURL = "http://localhost:631/printers/\(selected.name)"
                            } else {
                                webAdminURL = "http://localhost:631/printers"
                            }
                        }
                    }

                    let normalizedURL = normalizedAdminURL(webAdminURL)
                    if let url = URL(string: normalizedURL), !normalizedURL.isEmpty {
                        PrinterAdminWebView(url: url)
                            .frame(minHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ContentUnavailableView("Enter a printer admin URL", systemImage: "network")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 220)
                    }
                }
            }
        }
    }

    private var supportNotesSection: some View {
        SectionCard("Notes") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Native limits")
                    .font(.headline)

                Text("CUPS manages queues on your Mac. Direct device IP or DHCP changes are only standard on network printers that expose those settings over their own admin interface or vendor protocol.")
                    .foregroundStyle(.secondary)

                Text("USB thermal printers usually do not have IP or DHCP settings. Use the queue tools for macOS-side configuration and raw ESC/POS commands for drawer, cutter, and feed actions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncSelectedPrinterState() {
        guard let selected = manager.selectedPrinter else { return }
        if thermalHost.isEmpty, let host = selected.host {
            thermalHost = host
        }
        if webAdminURL.isEmpty, let admin = selected.defaultAdminURL {
            webAdminURL = admin
        }
    }

    private func normalizedAdminURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }
}

private enum PrinterQueueProtocol: String, CaseIterable, Identifiable {
    case ippEverywhere
    case rawSocket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ippEverywhere:
            return "IPP Everywhere"
        case .rawSocket:
            return "Raw Socket"
        }
    }
}

private struct PrinterSupply: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let level: Int?

    var levelText: String {
        if let level {
            return "\(level)%"
        }
        return "Unknown"
    }
}

private struct PrinterInfo: Identifiable, Hashable {
    let name: String
    var status: String
    var isDefault: Bool
    var deviceURI: String
    var makeAndModel: String
    var descriptionText: String
    var interfacePath: String
    var supplies: [PrinterSupply]

    var id: String { name }

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    var host: String? {
        guard !deviceURI.isEmpty else { return nil }
        guard let components = URLComponents(string: deviceURI), let host = components.host, !host.isEmpty else {
            return extractBonjourHost(from: deviceURI)
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    var defaultAdminURL: String? {
        guard let host else { return nil }
        return "http://\(host)"
    }

    var hostDisplay: String {
        host ?? "Unavailable"
    }

    var connectionSummary: String {
        if deviceURI.hasPrefix("usb://") {
            return "USB"
        }
        if deviceURI.hasPrefix("socket://") {
            return "Raw Socket"
        }
        if deviceURI.hasPrefix("ipp://") || deviceURI.hasPrefix("ipps://") || deviceURI.contains("._ipp") || deviceURI.contains("._ipps") {
            return "IPP"
        }
        if deviceURI.hasPrefix("dnssd://") {
            return "Bonjour"
        }
        if deviceURI.isEmpty {
            return "Unknown"
        }
        return deviceURI.components(separatedBy: "://").first?.uppercased() ?? "Unknown"
    }

    var iconName: String {
        if deviceURI.hasPrefix("usb://") {
            return "cable.connector"
        }
        if host != nil {
            return "network"
        }
        return "printer"
    }

    private func extractBonjourHost(from uri: String) -> String? {
        guard let range = uri.range(of: "._tcp.local.") else { return nil }
        let prefix = uri[..<range.lowerBound]
        guard let start = prefix.lastIndex(of: "/") else { return nil }
        let rawName = prefix[prefix.index(after: start)...]
        let decoded = rawName.removingPercentEncoding ?? String(rawName)
        return decoded.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    }
}

@MainActor
private final class PrinterManager: ObservableObject {
    @Published var printers: [PrinterInfo] = []
    @Published var selectedPrinterName: String?
    @Published var statusMessage = ""
    @Published var jobOutput = ""
    @Published var isBusy = false

    var selectedPrinter: PrinterInfo? {
        guard let selectedPrinterName else { return nil }
        return printers.first(where: { $0.name == selectedPrinterName })
    }

    func refresh() async {
        await perform("Refreshing printers") {
            let lpstatPath = try self.requireExecutable(["/usr/bin/lpstat"])
            let lpoptionsPath = try self.requireExecutable(["/usr/bin/lpoptions"])

            let printerOutput = try ProcessRunner.runCaptureSync(lpstatPath, ["-p"])
            let deviceOutput = try ProcessRunner.runCaptureSync(lpstatPath, ["-v"])
            let defaultOutput = try ProcessRunner.runCaptureSync(lpstatPath, ["-d"])

            let statuses = self.parseStatuses(printerOutput)
            let deviceMap = self.parseDeviceURIs(deviceOutput)
            let defaultPrinter = self.parseDefaultPrinter(defaultOutput)

            var discoveredNames = Set(statuses.keys)
            discoveredNames.formUnion(deviceMap.keys)

            var loadedPrinters: [PrinterInfo] = []
            for name in discoveredNames.sorted() {
                let infoOutput = try? ProcessRunner.runCaptureSync(lpstatPath, ["-l", "-p", name])
                let optionsOutput = try? ProcessRunner.runCaptureSync(lpoptionsPath, ["-p", name])

                let descriptionText = self.parsePrefixedField("Description:", in: infoOutput ?? "")
                let interfacePath = self.parsePrefixedField("Interface:", in: infoOutput ?? "")
                let makeAndModel = self.parseOptionValue("printer-make-and-model", in: optionsOutput ?? "")
                let supplies = self.parseSupplies(in: optionsOutput ?? "")

                loadedPrinters.append(
                    PrinterInfo(
                        name: name,
                        status: statuses[name] ?? "Available",
                        isDefault: defaultPrinter == name,
                        deviceURI: deviceMap[name] ?? "",
                        makeAndModel: makeAndModel,
                        descriptionText: descriptionText,
                        interfacePath: interfacePath,
                        supplies: supplies
                    )
                )
            }

            self.printers = loadedPrinters
            if let selectedPrinterName = self.selectedPrinterName, loadedPrinters.contains(where: { $0.name == selectedPrinterName }) {
                self.selectedPrinterName = selectedPrinterName
            } else {
                self.selectedPrinterName = loadedPrinters.first?.name
            }
            self.statusMessage = loadedPrinters.isEmpty ? "No printer queues found." : "Loaded \(loadedPrinters.count) printer queue(s)."
        }
    }

    func setDefaultPrinter() async {
        guard let printer = selectedPrinter else { return }
        await perform("Setting default printer") {
            let lpadminPath = try self.requireExecutable(["/usr/sbin/lpadmin"])
            _ = try ProcessRunner.runCaptureSync(lpadminPath, ["-d", printer.name])
            self.statusMessage = "Set \(printer.displayName) as the default printer."
            await self.refresh()
            await self.loadSelectedPrinterDetails()
        }
    }

    func removeSelectedPrinter() async {
        guard let printer = selectedPrinter else { return }
        await perform("Removing printer") {
            let lpadminPath = try self.requireExecutable(["/usr/sbin/lpadmin"])
            _ = try ProcessRunner.runCaptureSync(lpadminPath, ["-x", printer.name])
            self.statusMessage = "Removed queue \(printer.displayName)."
            self.selectedPrinterName = nil
            self.jobOutput = ""
            await self.refresh()
        }
    }

    func cancelAllJobs() async {
        guard let printer = selectedPrinter else { return }
        await perform("Cancelling jobs") {
            let cancelPath = try self.requireExecutable(["/usr/bin/cancel"])
            _ = try ProcessRunner.runCaptureSync(cancelPath, ["-a", printer.name])
            self.statusMessage = "Cancelled all jobs for \(printer.displayName)."
            await self.loadSelectedPrinterDetails()
        }
    }

    func pauseSelectedPrinter() async {
        guard let printer = selectedPrinter else { return }
        await perform("Pausing printer") {
            let commandPath = try self.requireExecutable(["/usr/sbin/cupsdisable"])
            _ = try ProcessRunner.runCaptureSync(commandPath, [printer.name])
            self.statusMessage = "Paused queue \(printer.displayName)."
            await self.refresh()
            await self.loadSelectedPrinterDetails()
        }
    }

    func resumeSelectedPrinter() async {
        guard let printer = selectedPrinter else { return }
        await perform("Resuming printer") {
            let commandPath = try self.requireExecutable(["/usr/sbin/cupsenable"])
            _ = try ProcessRunner.runCaptureSync(commandPath, [printer.name])
            self.statusMessage = "Resumed queue \(printer.displayName)."
            await self.refresh()
            await self.loadSelectedPrinterDetails()
        }
    }

    func acceptJobs() async {
        guard let printer = selectedPrinter else { return }
        await perform("Accepting jobs") {
            let commandPath = try self.requireExecutable(["/usr/sbin/cupsaccept"])
            _ = try ProcessRunner.runCaptureSync(commandPath, [printer.name])
            self.statusMessage = "Queue \(printer.displayName) is now accepting jobs."
            await self.loadSelectedPrinterDetails()
        }
    }

    func rejectJobs() async {
        guard let printer = selectedPrinter else { return }
        await perform("Rejecting jobs") {
            let commandPath = try self.requireExecutable(["/usr/sbin/cupsreject"])
            _ = try ProcessRunner.runCaptureSync(commandPath, [printer.name])
            self.statusMessage = "Queue \(printer.displayName) is rejecting new jobs."
            await self.loadSelectedPrinterDetails()
        }
    }

    func printTestPage() async {
        guard let printer = selectedPrinter else { return }
        await perform("Printing test page") {
            let lpPath = try self.requireExecutable(["/usr/bin/lp"])
            let testPage = """
            Control Panel printer check

            Queue: \(printer.name)
            Device URI: \(printer.deviceURI)
            Time: \(Date().formatted(date: .abbreviated, time: .standard))
            """
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("control-panel-printer-test.txt")
            try testPage.write(to: tempURL, atomically: true, encoding: .utf8)
            _ = try ProcessRunner.runCaptureSync(lpPath, ["-d", printer.name, tempURL.path])
            self.statusMessage = "Submitted a test page to \(printer.displayName)."
            await self.loadSelectedPrinterDetails()
        }
    }

    func addNetworkPrinter(
        queueName: String,
        host: String,
        portText: String,
        protocolType: PrinterQueueProtocol,
        makeDefault: Bool
    ) async {
        let trimmedQueueName = queueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQueueName.isEmpty, !trimmedHost.isEmpty else {
            statusMessage = "Queue name and host are required."
            return
        }

        let port = Int(portText) ?? 9100

        await perform("Adding printer") {
            let lpadminPath = try self.requireExecutable(["/usr/sbin/lpadmin"])
            let uri: String
            let modelArgs: [String]

            switch protocolType {
            case .ippEverywhere:
                uri = "ipp://\(trimmedHost):\(port)/ipp/print"
                modelArgs = ["-m", "everywhere"]
            case .rawSocket:
                uri = "socket://\(trimmedHost):\(port)"
                modelArgs = ["-m", "raw"]
            }

            _ = try ProcessRunner.runCaptureSync(lpadminPath, ["-p", trimmedQueueName, "-E", "-v", uri] + modelArgs)

            if makeDefault {
                _ = try ProcessRunner.runCaptureSync(lpadminPath, ["-d", trimmedQueueName])
            }

            self.statusMessage = "Added queue \(trimmedQueueName) using \(protocolType.title)."
            self.selectedPrinterName = trimmedQueueName
            await self.refresh()
            await self.loadSelectedPrinterDetails()
        }
    }

    func loadSelectedPrinterDetails() async {
        guard let printer = selectedPrinter else {
            jobOutput = ""
            return
        }

        await perform("Loading queue details") {
            let lpqPath = try self.requireExecutable(["/usr/bin/lpq"])
            let output = try ProcessRunner.runCaptureSync(lpqPath, ["-P", printer.name])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            self.jobOutput = trimmed.isEmpty ? "No queued jobs." : trimmed
        }
    }

    func openDrawer(host: String, portText: String) async {
        await sendThermalCommand(
            host: host,
            portText: portText,
            payload: Data([0x1B, 0x70, 0x00, 0x19, 0xFA]),
            success: "Drawer open command sent."
        )
    }

    func fullCut(host: String, portText: String) async {
        await sendThermalCommand(
            host: host,
            portText: portText,
            payload: Data([0x1D, 0x56, 0x00]),
            success: "Full cut command sent."
        )
    }

    func partialCut(host: String, portText: String) async {
        await sendThermalCommand(
            host: host,
            portText: portText,
            payload: Data([0x1D, 0x56, 0x01]),
            success: "Partial cut command sent."
        )
    }

    func feedPaper(host: String, portText: String, linesText: String) async {
        let lines = UInt8(max(1, min(Int(linesText) ?? 3, 10)))
        await sendThermalCommand(
            host: host,
            portText: portText,
            payload: Data([0x1B, 0x64, lines]),
            success: "Feed command sent for \(lines) line(s)."
        )
    }

    func queryThermalStatus(host: String, portText: String) async {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            statusMessage = "Thermal printer host is required."
            return
        }

        guard let port = NWEndpoint.Port(portText) else {
            statusMessage = "Enter a valid thermal printer port."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let response = try await RawPrinterTransport.sendAndReceive(
                payload: Data([0x10, 0x04, 0x01]),
                host: trimmedHost,
                port: port
            )
            if response.isEmpty {
                statusMessage = "Status query sent. The printer did not return a readable response."
            } else {
                statusMessage = "Status response: \(response.map { String(format: "%02X", $0) }.joined(separator: " "))"
            }
        } catch {
            statusMessage = "Status query failed: \(error.localizedDescription)"
        }
    }

    private func sendThermalCommand(host: String, portText: String, payload: Data, success: String) async {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            statusMessage = "Thermal printer host is required."
            return
        }

        guard let port = NWEndpoint.Port(portText) else {
            statusMessage = "Enter a valid thermal printer port."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await RawPrinterTransport.send(payload: payload, host: trimmedHost, port: port)
            statusMessage = success
        } catch {
            statusMessage = "Thermal command failed: \(error.localizedDescription)"
        }
    }

    private func perform(_ fallbackMessage: String, operation: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            statusMessage = "\(fallbackMessage) failed: \(error.localizedDescription)"
        }
    }

    private func requireExecutable(_ candidates: [String]) throws -> String {
        if let path = ProcessRunner.findExecutable(candidates) {
            return path
        }
        throw PrinterManagerError.missingTool(candidates.joined(separator: ", "))
    }

    private func parseStatuses(_ output: String) -> [String: String] {
        var results: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("printer ") else { continue }
            let remainder = text.dropFirst("printer ".count)
            let parts = remainder.split(separator: " ", maxSplits: 1).map(String.init)
            guard let name = parts.first else { continue }
            let status = parts.count > 1 ? parts[1] : "Available"
            results[name] = status
        }
        return results
    }

    private func parseDeviceURIs(_ output: String) -> [String: String] {
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

    private func parseDefaultPrinter(_ output: String) -> String? {
        let prefix = "system default destination: "
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix(prefix) {
                return text.replacingOccurrences(of: prefix, with: "")
            }
        }
        return nil
    }

    private func parsePrefixedField(_ field: String, in output: String) -> String {
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix(field) {
                return text.replacingOccurrences(of: field, with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func parseOptionValue(_ key: String, in output: String) -> String {
        let pattern = "\(key)="
        guard let range = output.range(of: pattern) else { return "" }
        let remainder = output[range.upperBound...]
        if let space = remainder.firstIndex(of: " ") {
            return String(remainder[..<space]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        return String(remainder).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    private func parseSupplies(in output: String) -> [PrinterSupply] {
        let names = parseOptionValue("marker-names", in: output)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\" ")) }
            .filter { !$0.isEmpty }
        let levels = parseOptionValue("marker-levels", in: output)
            .split(separator: ",")
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard !names.isEmpty else { return [] }
        return names.enumerated().map { index, name in
            PrinterSupply(name: name, level: index < levels.count ? levels[index] : nil)
        }
    }
}

private enum PrinterManagerError: LocalizedError {
    case missingTool(String)

    var errorDescription: String? {
        switch self {
        case .missingTool(let value):
            return "Required macOS print tool not found: \(value)"
        }
    }
}

private enum RawPrinterTransport {
    static func send(payload: Data, host: String, port: NWEndpoint.Port) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        try await waitUntilReady(connection)
        try await send(payload: payload, over: connection)
        connection.cancel()
    }

    static func sendAndReceive(payload: Data, host: String, port: NWEndpoint.Port) async throws -> Data {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        try await waitUntilReady(connection)
        try await send(payload: payload, over: connection)
        let data = try await receive(over: connection)
        connection.cancel()
        return data
    }

    private static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func send(payload: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func receive(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }
}

private struct PrinterAdminWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
