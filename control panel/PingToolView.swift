import SwiftUI

struct PingToolView: View {
    let navigateBack: () -> Void
    @State private var host = "apple.com"
    @State private var count = "4"
    @StateObject private var task = ProcessTask()

    var body: some View {
        ToolShell(
            title: "Ping",
            subtitle: "Measure latency and packet loss using the system ping command.",
            controls: {
                HStack {
                    Button(action: { navigateBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    TextField("Host or IP", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit(startPing)

                    TextField("Count", text: $count)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Button(action: { startPing() }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(task.isRunning || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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

    private func startPing() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            task.showMessage("Enter a host or IP address.")
            return
        }

        let isIPv6 = trimmedHost.contains(":")
        let candidates = isIPv6 ? ["/sbin/ping6", "/usr/sbin/ping6"] : ["/sbin/ping", "/usr/sbin/ping"]
        guard let pingPath = ProcessRunner.findExecutable(candidates) else {
            task.showMessage("Ping is unavailable on this Mac.")
            return
        }

        let packetCount = max(Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 4, 1)

        do {
            try task.start(executable: pingPath, arguments: ["-n", "-c", String(packetCount), trimmedHost])
        } catch {
            task.showMessage("Failed to launch ping.\n\(error.localizedDescription)")
        }
    }
}
