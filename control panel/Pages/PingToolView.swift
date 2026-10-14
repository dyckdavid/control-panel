import SwiftUI

struct PingToolView: View {
    let navigateBack: () -> Void

    @State private var host = "apple.com"
    @State private var countText = "4"
    @State private var isContinuous = false
    @State private var task = ProcessTask()

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Ping",
                subtitle: "Measures round-trip latency and packet loss with the system ping command.",
                icon: "dot.radiowaves.left.and.right",
                isBusy: task.isRunning,
                navigateBack: navigateBack
            ) {
                Button("Start", systemImage: "play.fill") {
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

            SectionCard("Target", icon: "target") {
                HStack(alignment: .bottom, spacing: 12) {
                    FormField(label: "Host or IP", text: $host, prompt: "apple.com") {
                        start()
                    }
                    FormField(label: "Packets", text: $countText, width: 90)
                }

                Toggle("Keep pinging until stopped", isOn: $isContinuous)

                Text(isContinuous
                     ? "Runs until you press Stop."
                     : "Sends \(packetCount) packet\(packetCount == 1 ? "" : "s"), then stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            OutputConsole(
                text: task.output,
                title: "Output",
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

    private var packetCount: Int {
        max(1, min(Int(countText.trimmingCharacters(in: .whitespaces)) ?? 4, 100))
    }

    private func start() {
        let target = trimmedHost
        guard !target.isEmpty else {
            task.showMessage("Enter a host or IP address.")
            return
        }

        // IPv6 literals need ping6; hostnames work with either, so prefer ping.
        let isIPv6Literal = target.contains(":")
        let candidates = isIPv6Literal
            ? ["/sbin/ping6", "/usr/sbin/ping6"]
            : ["/sbin/ping", "/usr/sbin/ping"]

        guard let tool = ProcessRunner.findExecutable(candidates) else {
            task.showMessage("ping is unavailable on this Mac.")
            return
        }

        var arguments = ["-n"]
        if !isContinuous {
            arguments += ["-c", String(packetCount)]
        }
        arguments.append(target)

        do {
            try task.start(executable: tool, arguments: arguments)
        } catch {
            task.showMessage("Could not launch ping.\n\(error.localizedDescription)")
        }
    }
}
