import SwiftUI

struct BackupRecoveryView: View {
    let navigateBack: () -> Void

    @State private var output = "Loading…"
    @State private var latestBackup = "—"
    @State private var isRunningNow = false
    @State private var isLoading = false

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Backup & Recovery",
                subtitle: "Time Machine status, destinations, and the most recent snapshot.",
                icon: "externaldrive.badge.timemachine",
                isBusy: isLoading,
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(isLoading)

                Button("Time Machine Settings", systemImage: "arrow.up.forward.app") {
                    openSystemSettings(pane: "com.apple.settings.TimeMachine")
                }
                Spacer()
            }

            StatRow {
                StatCard(
                    title: "Backing up",
                    value: isRunningNow ? "In progress" : "Idle",
                    detail: isRunningNow ? "A backup is running now" : "No backup running",
                    icon: "clock.arrow.circlepath",
                    tone: isRunningNow ? .accent : .neutral
                )
                StatCard(
                    title: "Latest backup",
                    value: latestBackup,
                    detail: "Most recent snapshot on disk",
                    icon: "externaldrive.badge.checkmark",
                    tone: latestBackup == "—" ? .warning : .success
                )
            }

            if latestBackup == "—" {
                StatusBanner(
                    message: "No Time Machine backup was found. Either no destination is configured, or the backup disk is not attached.",
                    tone: .warning
                )
            }

            OutputConsole(text: output, title: "Time Machine Report", isRunning: isLoading, minHeight: 320)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let status = await runCommandOutput("/usr/bin/tmutil", ["status"])
        isRunningNow = status.contains("Running = 1")

        let latest = await runCommandOutput("/usr/bin/tmutil", ["latestbackup"])
        latestBackup = Self.formatLatest(latest)

        output = await runCommandSections([
            (title: "Status", command: "/usr/bin/tmutil", arguments: ["status"]),
            (title: "Destinations", command: "/usr/bin/tmutil", arguments: ["destinationinfo"]),
            (title: "Latest backup", command: "/usr/bin/tmutil", arguments: ["latestbackup"])
        ])
    }

    /// `tmutil latestbackup` prints a path whose last component is a timestamp
    /// like `2026-09-17-084500`.
    private static func formatLatest(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return "—" }

        let stamp = (trimmed as NSString).lastPathComponent
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd-HHmmss"

        guard let date = parser.date(from: stamp) else { return stamp }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
