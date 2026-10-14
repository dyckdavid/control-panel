import SwiftUI

struct PrinterToolView: View {
    let navigateBack: () -> Void

    @State private var store = PrinterStore()
    @State private var isAddingPrinter = false
    @State private var queueToRemove: PrinterQueue?

    var body: some View {
        PageScaffold {
            header
            overview
            queueGrid

            if let queue = store.selectedQueue {
                PrinterDetailCard(store: store, queue: queue) {
                    queueToRemove = queue
                }
                PrintComposerCard(store: store, queue: queue)
                ThermalToolsCard(store: store, queue: queue)
                PrinterAdminCard(queue: queue)
            } else if !store.queues.isEmpty {
                SectionCard("Selected Printer") {
                    EmptyStateRow(message: "Pick a queue above to see its actions.", icon: "hand.tap")
                }
            }

            DirectPrintCard(store: store)
        }
        .task {
            await store.load()
            await store.loadDrivers()
        }
        .onChange(of: store.selectedQueueName) { _, _ in
            Task { await store.loadJobs() }
        }
        .sheet(isPresented: $isAddingPrinter) {
            AddPrinterSheet(store: store)
        }
        .confirmationDialog(
            "Remove this print queue?",
            item: $queueToRemove
        ) { queue in
            Button("Remove \(queue.displayName)", role: .destructive) {
                Task { await store.removeQueue(queue) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { queue in
            Text("\(queue.displayName) will be deleted from this Mac. Any queued jobs are discarded. The printer itself is not changed.")
        }
    }

    // MARK: Header

    private var header: some View {
        PageHeader(
            title: "Printers",
            subtitle: "Add printers over IP or Bonjour, manage their queues, and print — through CUPS or straight at the device.",
            icon: "printer",
            isBusy: store.isBusy,
            navigateBack: navigateBack
        ) {
            Button("Add Printer", systemImage: "plus") {
                isAddingPrinter = true
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await store.load() }
            }
            .disabled(store.isBusy)

            Button("Print Test Page", systemImage: "doc.text") {
                guard let name = store.selectedQueueName else { return }
                Task { await store.printTestPage(route: .queue(name)) }
            }
            .disabled(store.selectedQueue == nil || store.isBusy)

            Spacer()
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatRow {
                StatCard(
                    title: "Queues",
                    value: "\(store.queues.count)",
                    detail: store.queues.isEmpty ? "Nothing installed yet" : "Installed on this Mac",
                    icon: "tray.full",
                    tone: store.queues.isEmpty ? .warning : .neutral
                )
                StatCard(
                    title: "Default",
                    value: store.defaultQueue?.displayName ?? "None",
                    detail: store.defaultQueue?.connection.title ?? "Set one below",
                    icon: "star",
                    tone: store.defaultQueue == nil ? .warning : .success
                )
                StatCard(
                    title: "Selected",
                    value: store.selectedQueue?.displayName ?? "None",
                    detail: store.selectedQueue?.statusSummary ?? "Pick a queue",
                    icon: "printer",
                    tone: store.selectedQueue?.statusTone ?? .neutral
                )
                StatCard(
                    title: "Discovered",
                    value: "\(store.discovery.found.count)",
                    detail: "Advertising on this network",
                    icon: "antenna.radiowaves.left.and.right"
                )
            }

            if let status = store.status {
                StatusBanner(message: status.text, tone: status.tone)
            }
        }
    }

    // MARK: Queues

    private var queueGrid: some View {
        SectionCard("Queues", icon: "list.bullet.rectangle") {
            if store.queues.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    EmptyStateRow(
                        message: "No print queues are installed. Add one and every app on this Mac can use it.",
                        icon: "printer.trianglebadge.exclamationmark"
                    )
                    Button("Add a Printer", systemImage: "plus") {
                        isAddingPrinter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(store.queues) { queue in
                        queueCard(queue)
                    }
                }
            }
        }
    }

    private func queueCard(_ queue: PrinterQueue) -> some View {
        let isSelected = store.selectedQueueName == queue.name

        return Button {
            store.selectedQueueName = queue.name
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: queue.connection.symbol)
                        .foregroundStyle(.tint)
                    Text(queue.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if queue.isDefault {
                        Badge(text: "Default", tone: .accent)
                    }
                }

                HStack(spacing: 6) {
                    Badge(text: queue.connection.title)
                    Badge(text: queue.rawStatus, tone: queue.statusTone)
                    if !queue.isEnabled {
                        Badge(text: "Paused", tone: .warning)
                    }
                }

                if !queue.makeAndModel.isEmpty {
                    Text(queue.makeAndModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !queue.supplies.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(queue.supplies.prefix(4)) { supply in
                            Badge(
                                text: "\(supply.name) \(supply.levelText)",
                                tone: supply.isLow ? .warning : .neutral
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .panelSurface(corner: 12, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selected printer detail

private struct PrinterDetailCard: View {
    let store: PrinterStore
    let queue: PrinterQueue
    let requestRemove: () -> Void

    var body: some View {
        SectionCard(queue.displayName, icon: queue.connection.symbol) {
            KeyValueRow(title: "Queue name", value: queue.name, isMonospaced: true)
            KeyValueRow(title: "Status", value: queue.statusSummary)
            KeyValueRow(title: "Connection", value: queue.connection.title)
            if let host = queue.host {
                KeyValueRow(title: "Host", value: host, isMonospaced: true)
            }
            if !queue.makeAndModel.isEmpty {
                KeyValueRow(title: "Model", value: queue.makeAndModel)
            }
            if !queue.location.isEmpty {
                KeyValueRow(title: "Location", value: queue.location)
            }
            if !queue.deviceURI.isEmpty {
                KeyValueRow(title: "Device URI", value: queue.deviceURI, isMonospaced: true)
            }
            if !queue.interfacePath.isEmpty {
                KeyValueRow(title: "PPD", value: queue.interfacePath, isMonospaced: true)
            }

            Divider()

            FormGrid(minimum: 160) {
                Button("Set as Default", systemImage: "star") {
                    Task { await store.setDefault() }
                }
                .disabled(queue.isDefault || store.isBusy)

                Button(
                    queue.isEnabled ? "Pause Queue" : "Resume Queue",
                    systemImage: queue.isEnabled ? "pause.circle" : "play.circle"
                ) {
                    Task { await store.setEnabled(!queue.isEnabled) }
                }
                .disabled(store.isBusy)

                Button(
                    queue.isAcceptingJobs ? "Reject New Jobs" : "Accept Jobs",
                    systemImage: queue.isAcceptingJobs ? "nosign" : "checkmark.circle"
                ) {
                    Task { await store.setAcceptingJobs(!queue.isAcceptingJobs) }
                }
                .disabled(store.isBusy)

                Button("Cancel All Jobs", systemImage: "xmark.circle") {
                    Task { await store.cancelAllJobs() }
                }
                .disabled(store.isBusy)

                Button(role: .destructive) {
                    requestRemove()
                } label: {
                    Label("Remove Queue", systemImage: "trash")
                }
                .disabled(store.isBusy)
            }

            Divider()

            HStack {
                Text("Job queue")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.loadJobs() }
                }
                .controlSize(.small)
            }

            ScrollView {
                Text(store.jobListing.isEmpty ? "No queued jobs." : store.jobListing)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 80, maxHeight: 180)
            .background(
                AnyShapeStyle(.quaternary.opacity(0.25)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
}

// MARK: - Printer admin page

private struct PrinterAdminCard: View {
    let queue: PrinterQueue

    var body: some View {
        SectionCard("Printer Admin", icon: "globe") {
            Text("Network settings like DHCP, a static IP, DNS, and maintenance live on the printer's own web page. macOS cannot change them for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Layout.control) {
                if let url = queue.adminURL {
                    Link(destination: url) {
                        Label("Open \(url.host() ?? "printer")", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("This queue has no reachable web address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let cupsURL = queue.cupsURL {
                    Link(destination: cupsURL) {
                        Label("Open in CUPS", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
    }
}
