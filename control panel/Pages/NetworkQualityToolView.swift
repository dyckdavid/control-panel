import SwiftUI

struct NetworkQualityToolView: View {
    let navigateBack: () -> Void

    @State private var output = ""
    @State private var isRunning = false

    var body: some View {
        ToolShell(
            title: "Network Quality",
            subtitle: "Measures uplink, downlink, and responsiveness with Apple's networkQuality tool.",
            icon: "speedometer",
            navigateBack: navigateBack,
            output: output,
            isRunning: isRunning,
            onClear: { output = "" }
        ) {
            Button("Run Benchmark", systemImage: "play.fill") {
                Task { await run() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
            Spacer()
        }
        .task {
            if output.isEmpty {
                await run()
            }
        }
    }

    private func run() async {
        guard let tool = ProcessRunner.findExecutable(["/usr/bin/networkQuality"]) else {
            output = "networkQuality is unavailable on this Mac."
            return
        }

        isRunning = true
        output = "Running the benchmark. This takes about 15 seconds…"
        defer { isRunning = false }

        do {
            output = try await ProcessRunner.runCapture(tool, ["-v"])
        } catch {
            output = "Benchmark failed.\n\(error.localizedDescription)"
        }
    }
}
