import Foundation
import Observation

/// Polls CPU, memory, storage, and GPU on a timer.
@MainActor
@Observable
final class LiveSystemStatsProvider {
    var cpuUsage = "—"
    var memoryUsage = "—"
    var storageUsage = "—"
    var gpuInfo = "Loading…"
    var loadAverage = "—"
    /// 0…1, for gauges.
    var cpuFraction = 0.0
    var memoryFraction = 0.0
    var storageFraction = 0.0

    @ObservationIgnored private let sampler = SystemStatsSampler()

    /// Starts polling and keeps going until the task is cancelled. Call from a
    /// view's `.task` so SwiftUI tears it down when the screen goes away —
    /// the old version started a timer in `init` that never stopped.
    func startPolling(interval: Duration = .seconds(3)) async {
        await refreshStatic()
        while !Task.isCancelled {
            await refreshDynamic()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    func refreshNow() async {
        await refreshDynamic()
    }

    private func refreshStatic() async {
        guard let profiler = ProcessRunner.findExecutable(["/usr/sbin/system_profiler"]),
              let output = try? await ProcessRunner.runCapture(
                  profiler, ["SPDisplaysDataType", "-detailLevel", "mini"]
              ) else {
            gpuInfo = "Unavailable"
            return
        }

        let line = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Chipset Model:") || $0.hasPrefix("Graphics:") }

        gpuInfo = line.map { valueAfterColon(in: $0) } ?? "Unavailable"
    }

    private func refreshDynamic() async {
        if let sample = sampler.sample() {
            let percent = { (fraction: Double) in fraction.formatted(.percent.precision(.fractionLength(0))) }

            cpuFraction = sample.cpuBusy
            cpuUsage = "\(percent(sample.cpuBusy)) · \(percent(sample.cpuUser)) user, \(percent(sample.cpuSystem)) system"

            memoryFraction = sample.memoryFraction
            memoryUsage = "\(Self.bytes(sample.memoryUsed)) of \(Self.bytes(sample.memoryTotal))"

            let load = sample.loadAverage
            loadAverage = [load.one, load.five, load.fifteen]
                .map { $0.formatted(.number.precision(.fractionLength(2))) }
                .joined(separator: "  ")
        }

        if let usage = VolumeUsage.startupDisk() {
            storageFraction = usage.usedFraction
            storageUsage = "\(usage.usedText) of \(usage.totalText)"
        }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }
}

/// One-shot hardware and OS facts for the General screen.
@MainActor
@Observable
final class MacOverviewProvider {
    var modelName = "Loading…"
    var modelIdentifier = "Loading…"
    var serialNumber = "Loading…"
    var chip = "Loading…"
    var memory = ByteCountFormatter.string(
        fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
        countStyle: .memory
    )
    var macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var uptime = ""

    func refresh() async {
        uptime = formattedUptime(ProcessInfo.processInfo.systemUptime)

        guard let profiler = ProcessRunner.findExecutable(["/usr/sbin/system_profiler"]),
              let output = try? await ProcessRunner.runCapture(
                  profiler, ["SPHardwareDataType", "SPSoftwareDataType", "-detailLevel", "mini"]
              ) else {
            return
        }

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Model Name:") {
                modelName = valueAfterColon(in: trimmed)
            } else if trimmed.hasPrefix("Model Identifier:") {
                modelIdentifier = valueAfterColon(in: trimmed)
            } else if trimmed.hasPrefix("Serial Number") {
                serialNumber = valueAfterColon(in: trimmed)
            } else if trimmed.hasPrefix("System Version:") {
                macOSVersion = valueAfterColon(in: trimmed)
            } else if trimmed.hasPrefix("Chip:") || trimmed.hasPrefix("Processor Name:") {
                chip = valueAfterColon(in: trimmed)
            }
        }
    }
}

/// Measures the size of the folders that usually account for a full disk.
@MainActor
@Observable
final class FolderSizeProvider {
    struct Entry: Identifiable, Hashable {
        let name: String
        let bytes: Int64

        var id: String { name }
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    var entries: [Entry] = []
    var isMeasuring = false

    private static let targets = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library/Caches"]

    func refresh() async {
        isMeasuring = true
        defer { isMeasuring = false }

        let home = FileManager.default.homeDirectoryForCurrentUser

        // Walking several directory trees is slow, so measure them off the main
        // actor and concurrently rather than serially on it.
        let measured = await withTaskGroup(of: Entry?.self) { group in
            for target in Self.targets {
                let url = home.appending(path: target)
                group.addTask {
                    await Task.detached {
                        guard let size = Self.directorySize(at: url) else { return nil }
                        return Entry(name: (target as NSString).lastPathComponent, bytes: size)
                    }.value
                }
            }

            var collected: [Entry] = []
            for await entry in group {
                if let entry { collected.append(entry) }
            }
            return collected
        }

        entries = measured.sorted { $0.bytes > $1.bytes }
    }

    nonisolated private static func directorySize(at url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey, .fileSizeKey
            ]) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
