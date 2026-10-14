import SwiftUI

struct DisplaysGraphicsView: View {
    let navigateBack: () -> Void

    @State private var output = "Loading…"
    @State private var isLoading = false

    var body: some View {
        ToolShell(
            title: "Displays",
            subtitle: "Connected displays, resolutions, and the graphics hardware driving them.",
            icon: "display.2",
            navigateBack: navigateBack,
            output: output,
            isRunning: isLoading
        ) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isLoading)

            Button("Display Settings", systemImage: "arrow.up.forward.app") {
                openSystemSettings(pane: "com.apple.Displays-Settings.extension")
            }
            Spacer()
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        output = await runCommandOutput(
            "/usr/sbin/system_profiler",
            ["SPDisplaysDataType", "-detailLevel", "mini"]
        )
    }
}
