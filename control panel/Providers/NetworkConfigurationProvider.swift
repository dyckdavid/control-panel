import Foundation
import Observation

/// Reads and applies IPv4 / DNS configuration through `networksetup`.
@MainActor
@Observable
final class NetworkConfigurationProvider {
    var services: [String] = []
    var details: NetworkServiceDetails?
    var selectedService = ""
    var statusMessage = ""
    var statusTone: Tone = .neutral
    var isBusy = false

    private static let networksetup = ["/usr/sbin/networksetup"]

    func refreshServices() async {
        guard let tool = ProcessRunner.findExecutable(Self.networksetup) else {
            statusMessage = "networksetup is unavailable on this Mac."
            statusTone = .warning
            return
        }

        let output = (try? await ProcessRunner.runCapture(tool, ["-listallnetworkservices"])) ?? ""
        let parsed = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }

        services = parsed

        if selectedService.isEmpty || !parsed.contains(selectedService) {
            selectedService = parsed.first ?? ""
        }

        if !selectedService.isEmpty {
            await loadDetails(for: selectedService)
        }
    }

    func loadDetails(for service: String) async {
        guard !service.isEmpty,
              let tool = ProcessRunner.findExecutable(Self.networksetup) else { return }

        let infoOutput = (try? await ProcessRunner.runCapture(tool, ["-getinfo", service])) ?? ""
        let dnsOutput = (try? await ProcessRunner.runCapture(tool, ["-getdnsservers", service])) ?? ""

        selectedService = service
        details = NetworkServiceDetails(
            serviceName: service,
            configuration: Self.field("Configuration", in: infoOutput),
            ipAddress: Self.field("IP address", in: infoOutput),
            subnetMask: Self.field("Subnet mask", in: infoOutput),
            router: Self.field("Router", in: infoOutput),
            macAddress: Self.field(
                "\(service) ID",
                in: infoOutput,
                fallbacks: ["Wi-Fi ID", "Ethernet Address"]
            ),
            dnsServers: Self.parseDNS(dnsOutput)
        )
        statusMessage = "Loaded \(service)."
        statusTone = .neutral
    }

    // MARK: Applying

    func applyDHCP() async {
        guard !selectedService.isEmpty else { return }
        await apply(["-setdhcp", selectedService], success: "Switched \(selectedService) to DHCP.")
    }

    func applyManual(ip: String, subnet: String, router: String) async {
        guard !selectedService.isEmpty else { return }
        await apply(
            ["-setmanual", selectedService, ip, subnet, router],
            success: "Applied \(ip) to \(selectedService)."
        )
    }

    func applyAutomaticDNS() async {
        guard !selectedService.isEmpty else { return }
        await apply(
            ["-setdnsservers", selectedService, "Empty"],
            success: "\(selectedService) now uses the DNS servers from DHCP."
        )
    }

    func applyManualDNS(_ servers: [String]) async {
        guard !selectedService.isEmpty, !servers.isEmpty else { return }
        await apply(
            ["-setdnsservers", selectedService] + servers,
            success: "Set DNS for \(selectedService) to \(servers.joined(separator: ", "))."
        )
    }

    /// Changing a network service needs root, so the command goes through the
    /// administrator prompt. Reading configuration does not, and stays a plain
    /// call above.
    private func apply(_ arguments: [String], success: String) async {
        guard let tool = ProcessRunner.findExecutable(Self.networksetup) else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            // `networksetup` writes its complaints to stdout and still exits 0,
            // so the text has to be inspected rather than the status code.
            let output = try await AdminCommand.run(
                [[tool] + arguments],
                prompt: "Control Panel wants to change the \(selectedService) network settings."
            )

            if Self.looksLikeFailure(output) {
                statusMessage = output
                statusTone = .warning
            } else {
                statusMessage = output.isEmpty ? success : "\(success)\n\(output)"
                statusTone = .success
            }
        } catch AdminCommandError.cancelled {
            statusMessage = AdminCommandError.cancelled.errorDescription ?? "Cancelled."
            statusTone = .neutral
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusTone = .warning
        }

        await loadDetails(for: selectedService)
    }

    private static func looksLikeFailure(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return ["error", "not a recognized", "failed", "permission denied", "invalid"]
            .contains { lowered.contains($0) }
    }

    // MARK: Parsing

    private static func field(_ label: String, in output: String, fallbacks: [String] = []) -> String {
        for prefix in [label] + fallbacks {
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(prefix):") {
                    let value = String(trimmed.dropFirst(prefix.count + 1))
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
        }
        return "Unavailable"
    }

    private static func parseDNS(_ output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("aren't any DNS Servers") else { return [] }
        return trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
