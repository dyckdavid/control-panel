import SwiftUI

struct TracerouteToolView: View {
    let navigateBack: () -> Void

    @State private var host = "apple.com"
    @State private var output = ""
    @State private var isRunning = false
    @State private var includeBenchmark = false

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Path Diagnostics",
                subtitle: "Traces the route to a host and gathers the route table, resolver, and latency alongside it.",
                icon: "arrow.triangle.branch",
                isBusy: isRunning,
                navigateBack: navigateBack
            ) {
                Button("Run", systemImage: "play.fill") {
                    Task { await run() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || trimmedHost.isEmpty)
                Spacer()
            }

            SectionCard("Target", icon: "target") {
                FormField(label: "Host or IP", text: $host, prompt: "apple.com") {
                    Task { await run() }
                }

                Toggle("Include a throughput benchmark", isOn: $includeBenchmark)

                Text("traceroute sends raw ICMP, which needs elevated privileges. If it reports nothing, the route table and ping results below still show where traffic is going.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OutputConsole(
                text: output,
                title: "Diagnostics",
                isRunning: isRunning,
                minHeight: 380,
                onClear: { output = "" }
            )
        }
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run() async {
        let target = trimmedHost
        guard !target.isEmpty else {
            output = "Enter a host or IP address."
            return
        }

        isRunning = true
        output = "Running diagnostics for \(target)…"
        defer { isRunning = false }

        var sections: [(title: String, command: String, arguments: [String])] = [
            (title: "Traceroute", command: "/usr/sbin/traceroute", arguments: ["-n", "-w", "1", "-q", "1", "-m", "20", target]),
            (title: "Default route", command: "/sbin/route", arguments: ["-n", "get", "default"]),
            (title: "Resolver", command: "/usr/sbin/scutil", arguments: ["--dns"]),
            (title: "DNS answer", command: "/usr/bin/dig", arguments: [target, "+short"]),
            (title: "Ping", command: "/sbin/ping", arguments: ["-n", "-c", "5", target])
        ]

        if includeBenchmark {
            sections.append((title: "Network quality", command: "/usr/bin/networkQuality", arguments: ["-v"]))
        }

        output = await runCommandSections(sections)
    }
}
