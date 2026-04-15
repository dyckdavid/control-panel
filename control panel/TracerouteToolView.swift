import SwiftUI

struct TracerouteToolView: View {
    let navigateBack: () -> Void
    @State private var host = "apple.com"
    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        ToolShell(
            title: "Path Diagnostics",
            subtitle: "macOS blocks traceroute in this app context, so this screen runs the route, resolver, ping, and throughput checks that are permitted.",
            controls: {
                Button("Back", systemImage: "chevron.left", action: navigateBack)
                TextField("Host or IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(startDiagnostics)

                Button("Run", systemImage: "play.fill", action: startDiagnostics)
                    .disabled(isRunning || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { output = "" } label: { Label("Clear", systemImage: "xmark.circle") }
            },
            output: output,
            isRunning: isRunning
        )
    }

    private func startDiagnostics() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            output = "Enter a host or IP address."
            return
        }

        isRunning = true
        output = "Running diagnostics for \(trimmedHost)...\n"

        Task {
            let sections = await [
                runSection("Route", command: "/sbin/route", arguments: ["-n", "get", "default"]),
                runSection("Resolver", command: "/usr/sbin/scutil", arguments: ["--dns"]),
                runSection("Ping", command: "/sbin/ping", arguments: ["-n", "-c", "4", trimmedHost]),
                runSection("DNS Lookup", command: "/usr/bin/dig", arguments: [trimmedHost, "+short"]),
                runSection("Network Quality", command: "/usr/bin/networkQuality", arguments: ["-v"])
            ]

            await MainActor.run {
                output = sections.joined(separator: "\n\n")
                isRunning = false
            }
        }
    }

    private func runSection(_ title: String, command: String, arguments: [String]) async -> String {
        guard ProcessRunner.findExecutable([command]) != nil else {
            return "### \(title)\nCommand unavailable: \(command)"
        }

        do {
            let output = try await ProcessRunner.runCapture(command, arguments)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "### \(title)\n\(trimmed.isEmpty ? "No output." : trimmed)"
        } catch {
            return "### \(title)\nFailed: \(error.localizedDescription)"
        }
    }
}
