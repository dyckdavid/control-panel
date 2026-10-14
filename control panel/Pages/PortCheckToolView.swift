import SwiftUI
import Network

struct PortCheckToolView: View {
    let navigateBack: () -> Void

    @State private var host = "apple.com"
    @State private var ports = "80,443,8080"
    @State private var timeoutText = "3"
    @State private var results: [PortResult] = []
    @State private var isRunning = false
    @State private var message = ""

    struct PortResult: Identifiable {
        let port: UInt16
        let isOpen: Bool
        let detail: String

        var id: UInt16 { port }
    }

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Port Check",
                subtitle: "Tests whether a TCP port accepts a connection, using the Network framework rather than netcat.",
                icon: "firewall",
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
                HStack(alignment: .bottom, spacing: 12) {
                    FormField(label: "Host or IP", text: $host, prompt: "apple.com") {
                        Task { await run() }
                    }
                    FormField(label: "Ports", text: $ports, prompt: "80,443", width: 180)
                    FormField(label: "Timeout (s)", text: $timeoutText, width: 90)
                }

                Text("Separate ports with commas. Ranges like 8000-8010 work too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !message.isEmpty {
                StatusBanner(message: message, tone: isRunning ? .running : inferredTone(for: message))
            }

            SectionCard("Results", icon: "list.bullet.clipboard") {
                if results.isEmpty {
                    EmptyStateRow(
                        message: isRunning ? "Checking…" : "No results yet.",
                        icon: "questionmark.circle"
                    )
                } else {
                    ForEach(results) { result in
                        HStack(spacing: 10) {
                            Image(systemName: result.isOpen ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isOpen ? .green : .red)
                            Text("Port \(String(result.port))")
                                .font(.callout.monospaced())
                            Spacer()
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Badge(text: result.isOpen ? "Open" : "Closed", tone: result.isOpen ? .success : .warning)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var timeout: Duration {
        .seconds(max(1, min(Int(timeoutText.trimmingCharacters(in: .whitespaces)) ?? 3, 30)))
    }

    /// Accepts `80`, `80,443`, and `8000-8010`, capped so a typo cannot open
    /// thousands of sockets.
    private var parsedPorts: [UInt16] {
        var collected: [UInt16] = []

        for chunk in ports.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let token = chunk.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            if token.contains("-") {
                let bounds = token.split(separator: "-").compactMap { UInt16($0) }
                guard bounds.count == 2, bounds[0] <= bounds[1] else { continue }
                collected.append(contentsOf: bounds[0]...bounds[1])
            } else if let port = UInt16(token) {
                collected.append(port)
            }
        }

        return Array(Set(collected)).sorted().prefix(128).map { $0 }
    }

    private func run() async {
        let target = trimmedHost
        let portList = parsedPorts

        guard !target.isEmpty else {
            message = "Enter a host or IP address."
            return
        }
        guard !portList.isEmpty else {
            message = "Enter one or more ports, separated by commas."
            return
        }

        isRunning = true
        results = []
        message = "Checking \(portList.count) port\(portList.count == 1 ? "" : "s") on \(target)…"
        defer { isRunning = false }

        let timeout = timeout
        let collected = await withTaskGroup(of: PortResult.self) { group in
            for port in portList {
                group.addTask {
                    await Self.check(host: target, port: port, timeout: timeout)
                }
            }

            var found: [PortResult] = []
            for await result in group {
                found.append(result)
            }
            return found.sorted { $0.port < $1.port }
        }

        results = collected
        let openCount = collected.count(where: \.isOpen)
        message = "\(openCount) of \(collected.count) port\(collected.count == 1 ? "" : "s") open on \(target)."
    }

    private static func check(host: String, port: UInt16, timeout: Duration) async -> PortResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return PortResult(port: port, isOpen: false, detail: "Invalid port")
        }

        do {
            let elapsed = try await TCPProbe.connect(
                host: NWEndpoint.Host(host),
                port: nwPort,
                timeout: timeout
            )
            return PortResult(
                port: port,
                isOpen: true,
                detail: "connected in \(TCPProbe.milliseconds(elapsed)) ms"
            )
        } catch {
            return PortResult(
                port: port,
                isOpen: false,
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
