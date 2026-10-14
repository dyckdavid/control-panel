import SwiftUI

struct PerformanceMonitorView: View {
    let navigateBack: () -> Void

    @State private var liveStats = LiveSystemStatsProvider()
    @State private var processes = "Loading…"
    @State private var sortMode: SortMode = .cpu

    enum SortMode: String, CaseIterable, Identifiable {
        case cpu
        case memory

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu: "By CPU"
            case .memory: "By memory"
            }
        }

        /// `ps` sorts descending by CPU with `-r` and by resident size with `-m`.
        var psFlag: String {
            switch self {
            case .cpu: "-r"
            case .memory: "-m"
            }
        }
    }

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Performance",
                subtitle: "Live processor, memory, and disk readings with the processes driving them.",
                icon: "waveform.path.ecg",
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        await liveStats.refreshNow()
                        await refreshProcesses()
                    }
                }
                Button("Activity Monitor", systemImage: "arrow.up.forward.app") {
                    openApplication(at: "/System/Applications/Utilities/Activity Monitor.app")
                }
                Spacer()
            }

            StatRow {
                StatCard(title: "CPU", value: liveStats.cpuUsage, detail: "User / system / idle", icon: "cpu")
                StatCard(title: "Load average", value: liveStats.loadAverage, detail: "1, 5, and 15 minutes", icon: "gauge.with.dots.needle.67percent")
                StatCard(title: "Memory", value: liveStats.memoryUsage, detail: "Used and wired", icon: "memorychip")
                StatCard(title: "Storage", value: liveStats.storageUsage, detail: "Startup disk", icon: "internaldrive")
            }

            SectionCard("Usage", icon: "gauge.with.dots.needle.33percent") {
                usageBar("CPU", fraction: liveStats.cpuFraction)
                usageBar("Memory", fraction: liveStats.memoryFraction)
                usageBar("Startup disk", fraction: liveStats.storageFraction)
            }

            SectionCard("Top Processes", icon: "list.number") {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: sortMode) { _, _ in
                    Task { await refreshProcesses() }
                }

                ScrollView {
                    Text(processes)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 320)
                .background(
                    AnyShapeStyle(.quaternary.opacity(0.25)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .task {
            await refreshProcesses()
            await liveStats.startPolling()
        }
    }

    private func usageBar(_ title: String, fraction: Double) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: clamped)
                .progressViewStyle(.linear)
                .tint(clamped > 0.9 ? .orange : .accentColor)
                .animation(.smooth, value: clamped)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshProcesses() async {
        processes = await runCommandOutput(
            "/bin/ps",
            ["-Aceo", "pid,comm,%cpu,%mem", sortMode.psFlag]
        )
    }
}
