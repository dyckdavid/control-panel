import SwiftUI
import UniformTypeIdentifiers

/// Actually print something. Three ways in, all of them ending at paper:
/// a file from disk, text typed here, or the standard macOS print panel.
struct PrintComposerCard: View {
    let store: PrinterStore
    let queue: PrinterQueue

    @State private var text = ""
    @State private var copiesText = "1"
    @State private var isPickingFile = false
    @State private var pickedFile: URL?

    private var copies: Int {
        max(1, Int(copiesText.trimmingCharacters(in: .whitespaces)) ?? 1)
    }

    var body: some View {
        SectionCard("Print", icon: "printer.filled.and.paper") {
            Text("Everything here goes through the \(queue.displayName) queue, so it uses the queue's driver and options.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // MARK: File

            HStack(spacing: Layout.control) {
                Button("Choose File…", systemImage: "folder") {
                    isPickingFile = true
                }

                if let pickedFile {
                    Text(pickedFile.lastPathComponent)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file chosen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Print File", systemImage: "paperplane") {
                    guard let pickedFile else { return }
                    Task {
                        await store.printFile(
                            at: pickedFile,
                            route: .queue(queue.name),
                            copies: copies
                        )
                    }
                }
                .disabled(pickedFile == nil || store.isBusy)
            }

            Divider()

            // MARK: Text

            Text("Or type something and send it directly:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    AnyShapeStyle(.quaternary.opacity(0.25)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            HStack(spacing: Layout.control) {
                Text("Copies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Copies", text: $copiesText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                Spacer()

                Button("Print Text", systemImage: "doc.plaintext") {
                    Task {
                        await store.printText(
                            text,
                            jobName: "Control Panel text",
                            route: .queue(queue.name),
                            copies: copies
                        )
                    }
                }
                .disabled(text.isEmpty || store.isBusy)

                Button("Print Panel…", systemImage: "macwindow") {
                    store.presentSystemPrintPanel(
                        text: text.isEmpty ? previewText : text,
                        jobName: "Control Panel"
                    )
                }
                .help("Opens the standard macOS print dialog with a printer picker, paper size, and preview.")

                Button("Test Page", systemImage: "doc.text.magnifyingglass") {
                    Task { await store.printTestPage(route: .queue(queue.name)) }
                }
                .disabled(store.isBusy)
            }

            if queue.isRawQueue {
                StatusBanner(
                    message: "This is a raw queue, so text is passed straight through with no formatting. Use the thermal tools below for receipts.",
                    tone: .neutral
                )
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: UTType.printableTypes
        ) { result in
            if case .success(let url) = result {
                pickedFile = url
            }
        }
    }

    private var previewText: String {
        "Printed from Control Panel on \(Date.now.formatted(date: .abbreviated, time: .shortened))."
    }
}

/// Printing that bypasses CUPS completely: straight at an IP printer over IPP
/// or a raw socket. Works even when nothing is installed on this Mac.
struct DirectPrintCard: View {
    let store: PrinterStore

    @State private var host = ""
    @State private var portText = "631"
    @State private var path = "/ipp/print"
    @State private var mode: Mode = .ipp
    @State private var text = ""
    @State private var probeOutput = ""

    enum Mode: String, CaseIterable, Identifiable {
        case ipp
        case raw

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ipp: "IPP (port 631)"
            case .raw: "Raw TCP (port 9100)"
            }
        }

        var defaultPort: Int {
            switch self {
            case .ipp: 631
            case .raw: 9100
            }
        }
    }

    private var port: Int {
        Int(portText.trimmingCharacters(in: .whitespaces)) ?? mode.defaultPort
    }

    private var route: PrintRoute {
        switch mode {
        case .ipp: .directIPP(host: trimmedHost, port: port, path: path)
        case .raw: .directRaw(host: trimmedHost, port: port)
        }
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SectionCard("Print Directly to an IP Printer", icon: "arrow.up.right.circle") {
            Text("Sends the job over the network without a queue or a driver. Useful for a printer you have not installed, and the only way to reach a receipt printer's control codes untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Protocol", selection: $mode) {
                ForEach(Mode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, newValue in
                portText = String(newValue.defaultPort)
            }

            HStack(alignment: .bottom, spacing: 12) {
                FormField(label: "Host or IP", text: $host, prompt: "192.168.1.50")
                FormField(label: "Port", text: $portText, width: 80)
                if mode == .ipp {
                    FormField(label: "Resource path", text: $path, width: 150)
                }
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    AnyShapeStyle(.quaternary.opacity(0.25)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            HStack(spacing: Layout.control) {
                Button("Query Printer", systemImage: "wave.3.right") {
                    Task {
                        probeOutput = await store.probe(
                            host: trimmedHost,
                            transport: mode == .ipp ? .ippEverywhere : .socket,
                            port: port
                        )
                    }
                }
                .disabled(trimmedHost.isEmpty || store.isBusy)

                Spacer()

                Button("Send Text", systemImage: "paperplane") {
                    Task {
                        await store.printText(
                            text,
                            jobName: "Control Panel direct print",
                            route: route,
                            copies: 1
                        )
                    }
                }
                .disabled(trimmedHost.isEmpty || text.isEmpty || store.isBusy)
                .buttonStyle(.borderedProminent)
            }

            if !probeOutput.isEmpty {
                Text(probeOutput)
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
    }
}
