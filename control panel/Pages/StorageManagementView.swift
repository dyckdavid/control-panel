import SwiftUI
import AppKit

struct StorageManagementView: View {
    let navigateBack: () -> Void

    @State private var folders = FolderSizeProvider()
    @State private var usage = VolumeUsage.startupDisk()
    @State private var volumes = "Loading…"

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Storage",
                subtitle: "What is using the startup disk, broken down by volume and by home folder.",
                icon: "internaldrive",
                isBusy: folders.isMeasuring,
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(folders.isMeasuring)

                Button("Disk Utility", systemImage: "arrow.up.forward.app") {
                    openApplication(at: "/System/Applications/Utilities/Disk Utility.app")
                }
                Spacer()
            }

            if let usage {
                StatRow {
                    StatCard(
                        title: "Used",
                        value: usage.usedText,
                        detail: "\(Int(usage.usedFraction * 100))% of the disk",
                        icon: "chart.pie",
                        tone: usage.usedFraction > 0.9 ? .warning : .neutral
                    )
                    StatCard(title: "Available", value: usage.availableText, detail: "Free for important use", icon: "externaldrive.badge.checkmark")
                    StatCard(title: "Capacity", value: usage.totalText, detail: "Startup disk", icon: "internaldrive")
                }

                SectionCard("Startup Disk", icon: "chart.bar") {
                    ProgressView(value: usage.usedFraction) {
                        Text("\(usage.usedText) used of \(usage.totalText)")
                            .font(.subheadline)
                    }
                    .progressViewStyle(.linear)
                    .tint(usage.usedFraction > 0.9 ? .orange : .accentColor)

                    if usage.usedFraction > 0.9 {
                        StatusBanner(
                            message: "Less than 10% of the disk is free. macOS needs headroom for snapshots and swap.",
                            tone: .warning
                        )
                    }
                }
            }

            SectionCard("Home Folders", icon: "folder") {
                if folders.entries.isEmpty {
                    EmptyStateRow(
                        message: folders.isMeasuring ? "Measuring…" : "No folder sizes yet.",
                        icon: "folder.badge.questionmark"
                    )
                } else {
                    ForEach(folders.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            KeyValueRow(title: entry.name, value: entry.sizeText)
                            if let largest = folders.entries.first?.bytes, largest > 0 {
                                ProgressView(value: Double(entry.bytes) / Double(largest))
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor.opacity(0.6))
                            }
                        }
                    }

                    Button("Show Home Folder in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [FileManager.default.homeDirectoryForCurrentUser]
                        )
                    }
                }
            }

            OutputConsole(text: volumes, title: "Mounted Volumes", minHeight: 200)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        usage = VolumeUsage.startupDisk()
        async let listing = runCommandOutput("/bin/df", ["-H"])
        await folders.refresh()
        volumes = await listing
    }
}
