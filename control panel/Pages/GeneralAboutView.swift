import SwiftUI

struct GeneralAboutView: View {
    let navigateBack: () -> Void

    @State private var overview = MacOverviewProvider()
    @State private var liveStats = LiveSystemStatsProvider()

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "General",
                subtitle: "About this Mac, live hardware readings, and the settings you open most.",
                icon: "macwindow",
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task {
                        await overview.refresh()
                        await liveStats.refreshNow()
                    }
                }
                Button("Copy Summary", systemImage: "doc.on.doc") {
                    copyToClipboard(summary)
                }
                Spacer()
            }

            StatRow {
                StatCard(title: "CPU", value: liveStats.cpuUsage, detail: "Live processor usage", icon: "cpu")
                StatCard(title: "Memory", value: liveStats.memoryUsage, detail: "Physical memory", icon: "memorychip")
                StatCard(title: "Storage", value: liveStats.storageUsage, detail: "Startup disk", icon: "internaldrive")
                StatCard(title: "Graphics", value: liveStats.gpuInfo, detail: "GPU", icon: "display")
            }

            SectionCard("This Mac", icon: "desktopcomputer") {
                KeyValueRow(title: "Model", value: overview.modelName)
                KeyValueRow(title: "Identifier", value: overview.modelIdentifier, isMonospaced: true)
                KeyValueRow(title: "Chip", value: overview.chip)
                KeyValueRow(title: "Memory", value: overview.memory)
                KeyValueRow(title: "Serial", value: overview.serialNumber, isMonospaced: true)
                KeyValueRow(title: "macOS", value: overview.macOSVersion)
                KeyValueRow(title: "Uptime", value: overview.uptime)
            }

            SectionCard("Open", icon: "arrow.up.forward.app") {
                FormGrid(minimum: 170) {
                    Button("System Settings", systemImage: "gearshape") {
                        openSystemSettings()
                    }
                    Button("Activity Monitor", systemImage: "chart.line.uptrend.xyaxis") {
                        openApplication(at: "/System/Applications/Utilities/Activity Monitor.app")
                    }
                    Button("Disk Utility", systemImage: "internaldrive") {
                        openApplication(at: "/System/Applications/Utilities/Disk Utility.app")
                    }
                    Button("Terminal", systemImage: "terminal") {
                        openApplication(at: "/System/Applications/Utilities/Terminal.app")
                    }
                    Button("Console", systemImage: "doc.text.magnifyingglass") {
                        openApplication(at: "/System/Applications/Utilities/Console.app")
                    }
                }
            }

            SectionCard("About Control Panel", icon: "info.circle") {
                KeyValueRow(title: "Version", value: Self.appVersion)
                KeyValueRow(title: "Built for", value: "macOS 27 and later")
                KeyValueRow(title: "Runtime", value: "Native · Hardened Runtime · unsandboxed")
                Text("The app runs outside the App Sandbox so it can drive the system printing and networking tools directly. That also means it cannot be distributed through the Mac App Store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await overview.refresh()
            await liveStats.startPolling()
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var summary: String {
        """
        Model:      \(overview.modelName)
        Identifier: \(overview.modelIdentifier)
        Chip:       \(overview.chip)
        Memory:     \(overview.memory)
        Serial:     \(overview.serialNumber)
        macOS:      \(overview.macOSVersion)
        Uptime:     \(overview.uptime)
        CPU:        \(liveStats.cpuUsage)
        Storage:    \(liveStats.storageUsage)
        """
    }
}
