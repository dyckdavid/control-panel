import SwiftUI

/// ESC/POS tools for thermal receipt printers: print a receipt, feed, cut,
/// kick the cash drawer, and read the printer's status byte.
struct ThermalToolsCard: View {
    let store: PrinterStore
    let queue: PrinterQueue

    @State private var host = ""
    @State private var portText = "9100"
    @State private var heading = ""
    @State private var receiptBody = ""
    @State private var alignment: ESCPOSBuilder.Alignment = .left
    @State private var feedLinesText = "3"
    @State private var cutAfter = true
    @State private var openDrawerAfter = false
    @State private var statusOutput = ""

    private var port: Int {
        Int(portText.trimmingCharacters(in: .whitespaces)) ?? 9100
    }

    private var feedLines: Int {
        max(0, min(Int(feedLinesText.trimmingCharacters(in: .whitespaces)) ?? 3, 20))
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ESC/POS always goes over a direct socket. macOS no longer allows raw
    /// queues, and a driver queue would rewrite the control codes.
    private var route: PrintRoute? {
        guard !trimmedHost.isEmpty else { return nil }
        return .directRaw(host: trimmedHost, port: port)
    }

    var body: some View {
        SectionCard("Thermal / Receipt Printer", icon: "receipt") {
            Text("ESC/POS is the command set receipt printers speak. These commands are raw bytes, so they must reach the printer unfiltered — over a raw TCP socket, or through a queue created with the raw driver.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            destinationControls

            Divider()

            receiptControls

            Divider()

            deviceControls

            if !statusOutput.isEmpty {
                Text(statusOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        AnyShapeStyle(.quaternary.opacity(0.25)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
        }
        .task(id: queue.id) {
            // Prefill from the selected queue so the common case needs no typing.
            if trimmedHost.isEmpty, let queueHost = queue.host, !queueHost.contains(" ") {
                host = queueHost
            }
            if let queuePort = queue.port, queue.connection == .socket {
                portText = String(queuePort)
            }
        }
    }

    // MARK: Destination

    private var destinationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                FormField(label: "Printer host or IP", text: $host, prompt: "192.168.1.90")
                FormField(label: "Port", text: $portText, width: 80)
            }

            if trimmedHost.isEmpty {
                StatusBanner(
                    message: "Enter the receipt printer's address. These commands go straight to the device, so no queue is needed.",
                    tone: .neutral
                )
            } else {
                StatusBanner(
                    message: "Commands go directly to \(trimmedHost):\(port). macOS no longer allows raw pass-through queues, so this is the only way control bytes reach the printer unaltered.",
                    tone: .success
                )
            }
        }
    }

    // MARK: Receipt

    private var receiptControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Receipt")
                .font(.subheadline.weight(.medium))

            FormField(label: "Heading", text: $heading, prompt: "My Shop")

            TextEditor(text: $receiptBody)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    AnyShapeStyle(.quaternary.opacity(0.25)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            HStack(spacing: Layout.control) {
                Picker("Align", selection: $alignment) {
                    Text("Left").tag(ESCPOSBuilder.Alignment.left)
                    Text("Center").tag(ESCPOSBuilder.Alignment.center)
                    Text("Right").tag(ESCPOSBuilder.Alignment.right)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                TextField("Feed", text: $feedLinesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                Text("feed lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(spacing: 18) {
                Toggle("Cut after printing", isOn: $cutAfter)
                Toggle("Kick drawer after printing", isOn: $openDrawerAfter)
                Spacer()
            }

            HStack(spacing: Layout.control) {
                Button("Print Receipt", systemImage: "receipt") {
                    send(
                        ESCPOSBuilder.receipt(
                            heading: heading,
                            body: receiptBody,
                            alignment: alignment,
                            feedLines: feedLines,
                            cut: cutAfter,
                            openDrawer: openDrawerAfter
                        ),
                        named: "Receipt"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(route == nil || receiptBody.isEmpty || store.isBusy)

                Button("Print Self Test", systemImage: "checkmark.seal") {
                    send(
                        ESCPOSBuilder.testReceipt(
                            title: "CONTROL PANEL",
                            subtitle: "thermal self test",
                            cut: cutAfter
                        ),
                        named: "Thermal self test"
                    )
                }
                .disabled(route == nil || store.isBusy)

                Spacer()
            }
        }
    }

    // MARK: Device commands

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device commands")
                .font(.subheadline.weight(.medium))

            FormGrid(minimum: 150) {
                Button("Feed \(feedLines) Lines", systemImage: "arrow.down.to.line") {
                    send(ESCPOSBuilder.feed(lines: max(1, feedLines)), named: "Feed")
                }
                .disabled(route == nil || store.isBusy)

                Button("Full Cut", systemImage: "scissors") {
                    send(ESCPOSBuilder.fullCut, named: "Full cut")
                }
                .disabled(route == nil || store.isBusy)

                Button("Partial Cut", systemImage: "scissors.circle") {
                    send(ESCPOSBuilder.partialCut, named: "Partial cut")
                }
                .disabled(route == nil || store.isBusy)

                Button("Open Cash Drawer", systemImage: "tray.and.arrow.up") {
                    send(ESCPOSBuilder.openDrawer, named: "Open drawer")
                }
                .disabled(route == nil || store.isBusy)

                Button("Read Status", systemImage: "waveform.badge.magnifyingglass") {
                    Task {
                        statusOutput = await store.queryThermalStatus(host: trimmedHost, port: port)
                    }
                }
                .disabled(trimmedHost.isEmpty || store.isBusy)
                .help("Sends DLE EOT 1 and decodes the reply. Requires a raw socket — a queue cannot read bytes back.")
            }
        }
    }

    // MARK: Sending

    private func send(_ payload: Data, named name: String) {
        guard let route else { return }
        Task {
            await store.sendESCPOS(payload, jobName: name, route: route)
        }
    }
}
