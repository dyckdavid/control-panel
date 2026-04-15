import SwiftUI

struct DNSLookupView: View {
    let navigateBack: () -> Void
    enum RecordType: String, CaseIterable, Identifiable {
        case A
        case AAAA
        case CNAME
        case MX
        case NS
        case TXT

        var id: String { rawValue }
    }

    @State private var host = "apple.com"
    @State private var server = ""
    @State private var type: RecordType = .A
    @StateObject private var task = ProcessTask()

    var body: some View {
        ToolShell(
            title: "DNS",
            subtitle: "Query records using the system resolver or a specific DNS server.",
            controls: {
                HStack {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    TextField("Domain", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit(startLookup)

                    TextField("Server (optional)", text: $server)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)

                    Picker("Type", selection: $type) {
                        ForEach(RecordType.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    Button(action: { startLookup() }) {
                        Label("Lookup", systemImage: "magnifyingglass")
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || task.isRunning)

                    Button(action: { task.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(!task.isRunning)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(task.output, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        task.output = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }
            },
            output: task.output,
            isRunning: task.isRunning
        )
    }

    private func startLookup() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            task.showMessage("Enter a domain name.")
            return
        }

        guard let digPath = ProcessRunner.findExecutable(["/usr/bin/dig", "/opt/homebrew/bin/dig", "/usr/local/bin/dig"]) else {
            task.showMessage("`dig` is unavailable on this Mac.")
            return
        }

        var arguments = [String]()
        if !trimmedServer.isEmpty {
            arguments.append("@\(trimmedServer)")
        }
        arguments.append(contentsOf: [trimmedHost, type.rawValue, "+multiline", "+noall", "+answer", "+comments"])

        do {
            try task.start(executable: digPath, arguments: arguments)
        } catch {
            task.showMessage("Failed to launch DNS lookup.\n\(error.localizedDescription)")
        }
    }
}
