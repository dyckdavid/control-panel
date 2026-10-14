import SwiftUI

struct SystemOverviewView: View {
    let navigateBack: () -> Void

    @State private var kernel = "Loading…"

    private var facts: [(String, String)] {
        let info = ProcessInfo.processInfo
        return [
            ("Computer name", Host.current().localizedName ?? "Unknown"),
            ("Local host name", Host.current().name ?? "Unknown"),
            ("macOS", info.operatingSystemVersionString),
            ("Architecture", info.machineHardwareName),
            ("Active processors", "\(info.activeProcessorCount) of \(info.processorCount)"),
            ("Physical memory", ByteCountFormatter.string(
                fromByteCount: Int64(info.physicalMemory),
                countStyle: .memory
            )),
            ("Uptime", formattedUptime(info.systemUptime)),
            ("Thermal state", Self.thermalDescription(info.thermalState)),
            ("Low power mode", info.isLowPowerModeEnabled ? "On" : "Off"),
            ("User", "\(NSFullUserName()) (\(NSUserName()))")
        ]
    }

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "System",
                subtitle: "Machine identity, runtime state, and kernel details.",
                icon: "gearshape.2",
                navigateBack: navigateBack
            ) {
                Button("Copy", systemImage: "doc.on.doc") {
                    copyToClipboard(
                        facts.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                    )
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                Spacer()
            }

            SectionCard("Overview", icon: "info.circle") {
                ForEach(facts, id: \.0) { fact in
                    KeyValueRow(title: fact.0, value: fact.1)
                }
            }

            OutputConsole(text: kernel, title: "Kernel", minHeight: 160)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        kernel = await runCommandOutput("/usr/bin/uname", ["-a"])
    }

    private static func thermalDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
