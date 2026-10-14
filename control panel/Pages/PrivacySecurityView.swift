import SwiftUI

struct PrivacySecurityView: View {
    let navigateBack: () -> Void

    @State private var checks: [SecurityCheck] = []
    @State private var output = ""
    @State private var isLoading = false

    struct SecurityCheck: Identifiable {
        let name: String
        let value: String
        let icon: String
        let tone: Tone

        var id: String { name }
    }

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Privacy & Security",
                subtitle: "FileVault, Gatekeeper, System Integrity Protection, and the firewall at a glance.",
                icon: "lock.shield",
                isBusy: isLoading,
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .disabled(isLoading)

                Button("Privacy Settings", systemImage: "arrow.up.forward.app") {
                    openSystemSettings(pane: "com.apple.settings.PrivacySecurity.extension")
                }
                Spacer()
            }

            SectionCard("Protection Status", icon: "checkmark.shield") {
                if checks.isEmpty {
                    EmptyStateRow(message: isLoading ? "Checking…" : "No results yet.", icon: "questionmark.circle")
                } else {
                    ForEach(checks) { check in
                        HStack(spacing: 10) {
                            Image(systemName: check.icon)
                                .foregroundStyle(check.tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(check.tone.color))
                                .frame(width: 20)
                            Text(check.name)
                            Spacer()
                            Badge(text: check.value, tone: check.tone)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            OutputConsole(text: output, title: "Full Report", isRunning: isLoading, minHeight: 260)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let fileVault = runCommandOutput("/usr/bin/fdesetup", ["status"])
        async let gatekeeper = runCommandOutput("/usr/sbin/spctl", ["--status"])
        async let sip = runCommandOutput("/usr/bin/csrutil", ["status"])
        // The firewall used to be read from the `com.apple.alf` preferences
        // domain. That domain no longer exists on current macOS, so ask the
        // firewall's own control tool instead.
        async let firewall = runCommandOutput(Self.socketfilterfw, ["--getglobalstate"])
        async let blockAll = runCommandOutput(Self.socketfilterfw, ["--getblockall"])
        async let stealth = runCommandOutput(Self.socketfilterfw, ["--getstealthmode"])

        let (fileVaultText, gatekeeperText, sipText) = await (fileVault, gatekeeper, sip)
        let (firewallText, blockAllText, stealthText) = await (firewall, blockAll, stealth)

        checks = [
            Self.check(
                name: "FileVault",
                enabled: fileVaultText.localizedCaseInsensitiveContains("is on"),
                icon: "lock.doc",
                enabledText: "On",
                disabledText: "Off"
            ),
            Self.check(
                name: "Gatekeeper",
                enabled: gatekeeperText.localizedCaseInsensitiveContains("assessments enabled"),
                icon: "hand.raised",
                enabledText: "Enabled",
                disabledText: "Disabled"
            ),
            Self.check(
                name: "System Integrity Protection",
                enabled: sipText.localizedCaseInsensitiveContains("enabled"),
                icon: "shield.lefthalf.filled",
                enabledText: "Enabled",
                disabledText: "Disabled"
            ),
            Self.firewallCheck(firewallText, blockAll: blockAllText),
            Self.check(
                name: "Stealth mode",
                enabled: stealthText.localizedCaseInsensitiveContains("is on"),
                icon: "eye.slash",
                enabledText: "On",
                disabledText: "Off"
            )
        ]

        output = """
        ### FileVault
        \(fileVaultText)

        ### Gatekeeper
        \(gatekeeperText)

        ### System Integrity Protection
        \(sipText)

        ### Firewall
        \(firewallText)
        \(blockAllText)
        \(stealthText)
        """
    }

    private static let socketfilterfw = "/usr/libexec/ApplicationFirewall/socketfilterfw"

    private static func check(
        name: String,
        enabled: Bool,
        icon: String,
        enabledText: String,
        disabledText: String
    ) -> SecurityCheck {
        SecurityCheck(
            name: name,
            value: enabled ? enabledText : disabledText,
            icon: icon,
            tone: enabled ? .success : .warning
        )
    }

    /// Reads `socketfilterfw --getglobalstate`, which prints e.g.
    /// "Firewall is disabled. (State = 0)" or "Firewall is enabled. (State = 1)".
    private static func firewallCheck(_ state: String, blockAll: String) -> SecurityCheck {
        let lowered = state.lowercased()

        if lowered.contains("is enabled") || lowered.contains("state = 1") || lowered.contains("state = 2") {
            let blocksAll = blockAll.lowercased().contains("enabled")
            return SecurityCheck(
                name: "Firewall",
                value: blocksAll ? "On · block all" : "On",
                icon: "firewall",
                tone: .success
            )
        }
        if lowered.contains("is disabled") || lowered.contains("state = 0") {
            return SecurityCheck(name: "Firewall", value: "Off", icon: "firewall", tone: .warning)
        }
        return SecurityCheck(name: "Firewall", value: "Unknown", icon: "firewall", tone: .neutral)
    }
}
