import SwiftUI

struct DNSLookupView: View {
    let navigateBack: () -> Void

    @State private var host = "apple.com"
    @State private var server = ""
    @State private var recordType: RecordType = .a
    @State private var task = ProcessTask()

    enum RecordType: String, CaseIterable, Identifiable {
        case a = "A"
        case aaaa = "AAAA"
        case cname = "CNAME"
        case mx = "MX"
        case ns = "NS"
        case txt = "TXT"
        case soa = "SOA"
        case any = "ANY"

        var id: String { rawValue }
    }

    private static let presetResolvers: [(name: String, address: String)] = [
        ("System resolver", ""),
        ("Cloudflare", "1.1.1.1"),
        ("Google", "8.8.8.8"),
        ("Quad9", "9.9.9.9")
    ]

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "DNS",
                subtitle: "Queries records through the system resolver or any server you name.",
                icon: "globe",
                isBusy: task.isRunning,
                navigateBack: navigateBack
            ) {
                Button("Look Up", systemImage: "magnifyingglass") {
                    start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.isRunning || trimmedHost.isEmpty)

                Button("Stop", systemImage: "stop.fill") {
                    task.stop()
                }
                .disabled(!task.isRunning)
                Spacer()
            }

            SectionCard("Query", icon: "text.magnifyingglass") {
                HStack(alignment: .bottom, spacing: 12) {
                    FormField(label: "Domain", text: $host, prompt: "example.com") {
                        start()
                    }
                    FormField(label: "Server (optional)", text: $server, prompt: "1.1.1.1", width: 170)
                }

                Picker("Record type", selection: $recordType) {
                    ForEach(RecordType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Text("Resolver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Self.presetResolvers, id: \.name) { preset in
                        Button(preset.name) {
                            server = preset.address
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }

            OutputConsole(
                text: task.output,
                title: "Answer",
                isRunning: task.isRunning,
                minHeight: 320,
                onClear: { task.output = "" }
            )
        }
        .onDisappear { task.stop() }
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start() {
        let domain = trimmedHost
        guard !domain.isEmpty else {
            task.showMessage("Enter a domain name.")
            return
        }

        guard let dig = ProcessRunner.findExecutable([
            "/usr/bin/dig", "/opt/homebrew/bin/dig", "/usr/local/bin/dig"
        ]) else {
            task.showMessage("dig is unavailable on this Mac.")
            return
        }

        var arguments: [String] = []
        let resolver = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolver.isEmpty {
            arguments.append("@\(resolver)")
        }
        arguments += [domain, recordType.rawValue, "+multiline", "+noall", "+answer", "+comments", "+stats"]

        do {
            try task.start(executable: dig, arguments: arguments)
        } catch {
            task.showMessage("Could not launch dig.\n\(error.localizedDescription)")
        }
    }
}
