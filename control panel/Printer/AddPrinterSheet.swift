import SwiftUI

/// The add-printer flow: discover a printer on the network (or type in an
/// address), confirm it answers, pick a driver, and create a real CUPS queue.
struct AddPrinterSheet: View {
    let store: PrinterStore
    @Environment(\.dismiss) private var dismiss

    @State private var source: Source = .discovered
    @State private var selectedDiscovery: DiscoveredPrinter?
    @State private var queueName = ""
    @State private var host = ""
    @State private var portText = ""
    @State private var transport: PrinterTransport = .ippEverywhere
    @State private var driver: PrinterDriver = .everywhere
    @State private var description = ""
    @State private var location = ""
    @State private var makeDefault = false
    @State private var useBonjourURI = true
    @State private var probeResult = ""
    @State private var isProbing = false
    @State private var isAdding = false
    @State private var validationMessage: String?

    enum Source: String, CaseIterable, Identifiable {
        case discovered
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .discovered: "Discovered"
            case .manual: "IP or host name"
            }
        }

        var symbol: String {
            switch self {
            case .discovered: "dot.radiowaves.left.and.right"
            case .manual: "keyboard"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.section) {
                    sourcePicker

                    switch source {
                    case .discovered: discoverySection
                    case .manual: manualSection
                    }

                    queueSection
                    driverSection

                    if !probeResult.isEmpty {
                        SectionCard("Printer Response", icon: "checkmark.seal") {
                            Text(probeResult)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let validationMessage {
                        StatusBanner(message: validationMessage, tone: .warning)
                    }
                }
                .padding(Layout.page)
            }

            Divider()

            footer
        }
        .frame(width: 620, height: 680)
        .background(AppBackground())
        .task {
            await store.loadDrivers()
            // `store.drivers` only holds `everywhere` until lpinfo returns, so
            // re-derive now that the real list is in — otherwise a transport
            // chosen during that window keeps an unusable driverless setting.
            reconcileDriver()
            store.discovery.start()
        }
        .onDisappear { store.discovery.stop() }
        .onChange(of: transport) { _, newValue in
            portText = newValue.defaultPort == 0 ? "" : String(newValue.defaultPort)
            driver = store.suggestedDriver(for: newValue)
            reconcileDriver()
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "printer.filled.and.paper")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text("Add a Printer")
                    .font(.title2.weight(.semibold))
                Text("Creates a real print queue on this Mac with lpadmin, so every app can use it — not just this one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.page)
    }

    private var footer: some View {
        HStack(spacing: Layout.control) {
            Button("Test Connection", systemImage: "wave.3.right") {
                Task { await runProbe() }
            }
            .disabled(resolvedHost.isEmpty || isProbing || isAdding)

            if isProbing || isAdding {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Add Printer") {
                Task { await add() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdd || isAdding)
        }
        .padding(Layout.page)
    }

    // MARK: Sections

    private var sourcePicker: some View {
        Picker("How do you want to find the printer?", selection: $source) {
            ForEach(Source.allCases) { value in
                Label(value.title, systemImage: value.symbol).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var discoverySection: some View {
        SectionCard("On This Network", icon: "antenna.radiowaves.left.and.right") {
            HStack {
                if store.discovery.isBrowsing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(store.discovery.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Rescan", systemImage: "arrow.clockwise") {
                    store.discovery.refresh()
                }
            }

            if store.discovery.groups.isEmpty {
                EmptyStateRow(
                    message: "Nothing found yet. Make sure the printer is powered on and on the same network, or enter its address manually.",
                    icon: "magnifyingglass"
                )
            } else {
                ForEach(store.discovery.groups) { group in
                    discoveryRow(group)
                }
            }
        }
    }

    private func discoveryRow(_ group: DiscoveredPrinterGroup) -> some View {
        let isSelected = selectedDiscovery?.serviceName == group.name

        return Button {
            select(group.preferredService)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: group.supportsRawSocket && group.protocolLabels.count == 1
                      ? "printer.dotmatrix"
                      : "printer")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)

                    HStack(spacing: 5) {
                        ForEach(group.protocolLabels, id: \.self) { label in
                            Badge(text: label)
                        }
                    }

                    if let host = resolvedAddress(for: group) {
                        Text(host)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelSurface(corner: 12, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    /// The address shown under a discovered printer, once resolution has filled
    /// it in for the selected one.
    private func resolvedAddress(for group: DiscoveredPrinterGroup) -> String? {
        guard selectedDiscovery?.serviceName == group.name,
              let host = selectedDiscovery?.host,
              let port = selectedDiscovery?.port else {
            return nil
        }
        return "\(host):\(port)"
    }

    private var manualSection: some View {
        SectionCard("Printer Address", icon: "network") {
            Picker("Protocol", selection: $transport) {
                ForEach([PrinterTransport.ippEverywhere, .socket, .lpd]) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.radioGroup)

            Text(transport.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 12) {
                FormField(label: "Host or IP", text: $host, prompt: "192.168.1.50")
                FormField(label: "Port", text: $portText, width: 90)
            }

            Text("Device URI: \(previewDeviceURI)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var queueSection: some View {
        SectionCard("Queue", icon: "tray.full") {
            FormField(label: "Queue name", text: $queueName, prompt: "Office_LaserJet")
            Text("No spaces or / \\ # ? ' \" — this is the short name CUPS uses.")
                .font(.caption)
                .foregroundStyle(.secondary)

            FormField(label: "Description", text: $description, prompt: "Office LaserJet by the window")
            FormField(label: "Location", text: $location, prompt: "Second floor")

            Toggle("Make this the default printer", isOn: $makeDefault)

            if source == .discovered, selectedDiscovery != nil {
                Toggle("Let CUPS track the printer by Bonjour name", isOn: $useBonjourURI)
                    .help("Recommended: the queue keeps working when the printer's DHCP address changes.")
            }
        }
    }

    /// Drivers valid for the chosen transport. IPP Everywhere is hidden for
    /// transports that cannot answer its capability query, so it is not even
    /// selectable for a raw socket or LPD printer.
    private var selectableDrivers: [PrinterDriver] {
        transport.supportsDriverless
            ? store.drivers
            : store.drivers.filter { $0 != .everywhere }
    }

    private var driverSection: some View {
        SectionCard("Driver", icon: "gearshape.2") {
            Picker("Driver", selection: $driver) {
                ForEach(selectableDrivers) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Text(driverAdvice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsThermalNote {
                StatusBanner(
                    message: "For ESC/POS receipt printing, skip the queue entirely — macOS no longer allows raw pass-through queues. Use the thermal tools on the Printers page to send commands over a direct TCP socket.",
                    tone: .neutral
                )
            }
        }
    }

    private var driverAdvice: String {
        switch driver {
        case .everywhere where !transport.supportsDriverless:
            "IPP Everywhere needs to query the printer over IPP, which a raw socket cannot do. Pick a driver that matches the printer instead."
        case .everywhere:
            "The queue asks the printer for its own capabilities when it is created. Right for any IPP printer made in roughly the last decade."
        case .model where driver.isPointOfSale:
            "A point-of-sale driver. POS-58 is for 58 mm receipt rolls and POS-80 for 80 mm. Use the Zebra or DYMO entries for label printers."
        case .model:
            "Uses a driver installed on this Mac."
        case .ppd:
            "Uses a PPD file from disk."
        }
    }

    /// macOS no longer allows raw queues, so ESC/POS cannot go through one.
    private var showsThermalNote: Bool {
        transport == .socket
    }

    // MARK: Derived state

    private var resolvedHost: String {
        if source == .manual { return host.trimmingCharacters(in: .whitespacesAndNewlines) }
        return selectedDiscovery?.host ?? ""
    }

    private var resolvedPort: Int {
        Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? transport.defaultPort
    }

    private var previewDeviceURI: String {
        if source == .discovered, let selectedDiscovery, useBonjourURI {
            return selectedDiscovery.bonjourDeviceURI
        }
        guard !resolvedHost.isEmpty else { return "—" }
        return transport.deviceURI(host: resolvedHost, port: resolvedPort, queue: "")
    }

    private var canAdd: Bool {
        guard !queueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if source == .discovered {
            guard let selectedDiscovery else { return false }
            return useBonjourURI || selectedDiscovery.host != nil
        }
        return !resolvedHost.isEmpty
    }

    // MARK: Actions

    /// Keeps `driver` consistent with `transport`. Called after the driver list
    /// loads and after any transport change, so a driverless selection can
    /// never survive onto a transport that cannot use it.
    private func reconcileDriver() {
        guard !transport.supportsDriverless, driver == .everywhere else { return }
        let replacement = store.suggestedDriver(for: transport)
        driver = replacement == .everywhere
            ? (selectableDrivers.first ?? .everywhere)
            : replacement
    }

    private func select(_ printer: DiscoveredPrinter) {
        selectedDiscovery = printer
        transport = printer.transport
        driver = store.suggestedDriver(for: printer.transport)
        reconcileDriver()
        portText = String(printer.transport.defaultPort)
        if queueName.isEmpty {
            queueName = printer.suggestedQueueName
        }
        if description.isEmpty {
            description = printer.serviceName
        }
        probeResult = ""
        validationMessage = nil

        // Resolve the Bonjour name to an address so "Test Connection" and the
        // manual URI preview have something to work with.
        Task {
            guard let resolved = await PrinterDiscovery.resolve(printer),
                  selectedDiscovery?.id == printer.id else { return }
            var updated = printer
            updated.host = resolved.host
            updated.port = resolved.port
            selectedDiscovery = updated
            host = resolved.host
            portText = String(resolved.port)
        }
    }

    /// Whether the printer really answers an IPP capability query — the thing
    /// the `everywhere` driver depends on. A printer we cannot reach an address
    /// for gets the benefit of the doubt, since CUPS may still resolve it.
    private func printerAnswersIPP() async -> Bool {
        let probeHost = resolvedHost
        guard !probeHost.isEmpty else { return true }

        let client = IPPClient(
            host: probeHost,
            port: transport == .ippEverywhere ? resolvedPort : 631,
            timeout: 6
        )
        return (try? await client.printerAttributes()) != nil
    }

    /// Recovery when a printer claims IPP but cannot answer it. If it also
    /// advertises a raw socket — which receipt printers do — move the form onto
    /// that with a point-of-sale driver and let the user confirm.
    private func switchToRawSocketFallback() {
        let group = store.discovery.groups.first { $0.name == selectedDiscovery?.serviceName }

        if source == .discovered, let rawService = group?.rawSocketService {
            selectedDiscovery = rawService
            useBonjourURI = false
            transport = .socket
            portText = String(PrinterTransport.socket.defaultPort)
            driver = store.suggestedDriver(for: .socket)
            reconcileDriver()

            validationMessage = """
                \(rawService.serviceName) advertises IPP but did not answer a \
                capability query, so the driverless option cannot work. It does \
                offer raw TCP on port \(PrinterTransport.socket.defaultPort), so \
                the form has been switched to that with the \(driver.title) \
                driver. Press Add Printer again to continue, or pick a different \
                driver first.
                """
            return
        }

        transport = .socket
        portText = String(PrinterTransport.socket.defaultPort)
        driver = store.suggestedDriver(for: .socket)
        reconcileDriver()

        validationMessage = """
            This printer did not answer an IPP capability query, so the \
            driverless option cannot work. The form has been switched to raw TCP \
            with the \(driver.title) driver — check the port, then press Add \
            Printer again.
            """
    }

    private func runProbe() async {
        isProbing = true
        defer { isProbing = false }
        validationMessage = nil
        probeResult = await store.probe(host: resolvedHost, transport: transport, port: resolvedPort)
    }

    private func add() async {
        let trimmedName = queueName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try CUPSController.validate(queueName: trimmedName)
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        guard store.queues.allSatisfy({ $0.name != trimmedName }) else {
            validationMessage = "A queue named \(trimmedName) already exists. Pick a different name or remove the old one first."
            return
        }

        let uri = previewDeviceURI
        guard uri != "—" else {
            validationMessage = "Pick a discovered printer or enter a host address."
            return
        }

        // Last line of defence before lpadmin: catch an unusable driver so the
        // sheet can explain it, rather than surfacing lpadmin's
        // "Unable to query printer".
        do {
            try CUPSController.validate(driver: driver, deviceURI: uri)
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        // Advertising `_ipp._tcp` is not the same as implementing it. Plenty of
        // receipt printers announce IPP for AirPrint's benefit and then fail
        // the capability query, which is exactly what lpadmin reports as
        // "Unable to query printer". Ask the printer ourselves first so we can
        // fall back instead of handing the user that message.
        if driver == .everywhere, await !printerAnswersIPP() {
            switchToRawSocketFallback()
            return
        }

        isAdding = true
        defer { isAdding = false }
        validationMessage = nil

        let added = await store.addQueue(
            name: trimmedName,
            deviceURI: uri,
            driver: driver,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            makeDefault: makeDefault
        )

        if added {
            dismiss()
        } else {
            validationMessage = store.status?.text
        }
    }
}
