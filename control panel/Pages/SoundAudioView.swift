import SwiftUI

struct SoundAudioView: View {
    let navigateBack: () -> Void

    @State private var output = "Loading…"
    @State private var isLoading = false

    var body: some View {
        ToolShell(
            title: "Sound",
            subtitle: "Audio input and output devices, sample rates, and the current routing.",
            icon: "speaker.wave.2",
            navigateBack: navigateBack,
            output: output,
            isRunning: isLoading
        ) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isLoading)

            Button("Sound Settings", systemImage: "arrow.up.forward.app") {
                openSystemSettings(pane: "com.apple.Sound-Settings.extension")
            }

            Button("Audio MIDI Setup", systemImage: "pianokeys") {
                openApplication(at: "/System/Applications/Utilities/Audio MIDI Setup.app")
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
            ["SPAudioDataType", "-detailLevel", "mini"]
        )
    }
}
