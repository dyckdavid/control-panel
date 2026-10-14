import SwiftUI

struct BatteryPowerView: View {
    let navigateBack: () -> Void

    @State private var output = "Loading…"
    @State private var chargeSummary = "—"
    @State private var powerSource = "—"
    @State private var isLoading = false

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Battery & Power",
                subtitle: "Charge level, power source, health, and the full power report.",
                icon: "battery.100",
                isBusy: isLoading,
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(isLoading)

                Button("Battery Settings", systemImage: "arrow.up.forward.app") {
                    openSystemSettings(pane: "com.apple.Battery-Settings.extension")
                }
                Spacer()
            }

            StatRow {
                StatCard(title: "Charge", value: chargeSummary, detail: "Current battery level", icon: "battery.75")
                StatCard(title: "Power source", value: powerSource, detail: "As reported by pmset", icon: "powerplug")
            }

            OutputConsole(text: output, title: "Power Report", isRunning: isLoading, minHeight: 320)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let batteryOutput = await runCommandOutput("/usr/bin/pmset", ["-g", "batt"])
        parse(batteryOutput)

        output = await runCommandSections([
            (title: "Battery", command: "/usr/bin/pmset", arguments: ["-g", "batt"]),
            (title: "Power settings", command: "/usr/bin/pmset", arguments: ["-g", "custom"]),
            (title: "Power hardware", command: "/usr/sbin/system_profiler", arguments: ["SPPowerDataType", "-detailLevel", "mini"])
        ])
    }

    /// `pmset -g batt` prints a line like
    /// `-InternalBattery-0 (id=…)	88%; discharging; 4:12 remaining present: true`
    private func parse(_ text: String) {
        // The first line reads: Now drawing from 'AC Power'
        let sourceLine = text
            .split(separator: "\n")
            .map(String.init)
            .first { $0.contains("Now drawing from") }
        powerSource = sourceLine?
            .components(separatedBy: "'")
            .dropFirst()
            .first ?? "Unknown"

        guard let batteryLine = text.split(separator: "\n").first(where: { $0.contains("%") }) else {
            chargeSummary = "No battery"
            return
        }

        let fields = batteryLine
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let percent = fields.first?
            .components(separatedBy: "\t")
            .last?
            .trimmingCharacters(in: .whitespaces) ?? "—"
        let state = fields.count > 1 ? fields[1] : ""

        chargeSummary = state.isEmpty ? percent : "\(percent) · \(state)"
    }
}
