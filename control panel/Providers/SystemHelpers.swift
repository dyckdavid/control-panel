import Foundation
import AppKit
import Darwin

// MARK: - Shell helpers

/// Runs a system tool and returns its output, turning every failure into a
/// readable line rather than throwing. The read-only screens all display raw
/// output, so a message in the output area is the right way to report a problem.
func runCommandOutput(_ command: String, _ arguments: [String]) async -> String {
    guard ProcessRunner.findExecutable([command]) != nil else {
        return "Command unavailable: \(command)"
    }

    do {
        let output = try await ProcessRunner.runCapture(command, arguments)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No output." : trimmed
    } catch {
        return "Failed: \(error.localizedDescription)"
    }
}

/// Concatenates several command outputs under headings, running them
/// concurrently so a slow one does not hold up the rest.
func runCommandSections(_ sections: [(title: String, command: String, arguments: [String])]) async -> String {
    await withTaskGroup(of: (Int, String).self) { group in
        for (index, section) in sections.enumerated() {
            group.addTask {
                let output = await runCommandOutput(section.command, section.arguments)
                return (index, "### \(section.title)\n\(output)")
            }
        }

        var collected: [(Int, String)] = []
        for await result in group {
            collected.append(result)
        }
        return collected
            .sorted { $0.0 < $1.0 }
            .map(\.1)
            .joined(separator: "\n\n")
    }
}

// MARK: - Text helpers

/// Returns everything after the first colon, e.g. `"Model Name: iMac"` → `"iMac"`.
func valueAfterColon(in string: String) -> String {
    string
        .split(separator: ":", maxSplits: 1)
        .dropFirst()
        .first
        .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
}

func formattedUptime(_ uptime: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: uptime) ?? "Unavailable"
}

// MARK: - App launching

func openApplication(at path: String) {
    NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: path),
        configuration: .init(),
        completionHandler: nil
    )
}

/// Opens a System Settings pane by its preference URL, e.g.
/// `x-apple.systempreferences:com.apple.preference.security`.
func openSystemSettings(pane: String? = nil) {
    if let pane, let url = URL(string: "x-apple.systempreferences:\(pane)") {
        NSWorkspace.shared.open(url)
        return
    }
    openApplication(at: "/System/Applications/System Settings.app")
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Storage

/// Used / available / total for the startup disk.
struct VolumeUsage {
    let used: Int64
    let available: Int64
    let total: Int64

    var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    var usedText: String { ByteCountFormatter.string(fromByteCount: used, countStyle: .file) }
    var availableText: String { ByteCountFormatter.string(fromByteCount: available, countStyle: .file) }
    var totalText: String { ByteCountFormatter.string(fromByteCount: total, countStyle: .file) }

    static func startupDisk() -> VolumeUsage? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }

        return VolumeUsage(
            used: max(Int64(total) - available, 0),
            available: available,
            total: Int64(total)
        )
    }
}

// MARK: - Machine info

extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
