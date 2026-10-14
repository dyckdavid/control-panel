import SwiftUI

struct DeveloperToolsView: View {
    let navigateBack: () -> Void

    @State private var hostsText = ""
    @State private var originalHostsText = ""
    @State private var proxyOutput = "Loading…"
    @State private var status: String?
    @State private var statusTone: Tone = .neutral
    @State private var isConfirmingSave = false

    private static let hostsPath = "/etc/hosts"

    private var hasUnsavedChanges: Bool {
        hostsText != originalHostsText
    }

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Developer Tools",
                subtitle: "Edit the hosts file, inspect proxy settings, and jump to the utilities you use while debugging.",
                icon: "hammer",
                navigateBack: navigateBack
            ) {
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await load() }
                }

                Button("Save Hosts", systemImage: "square.and.arrow.down") {
                    isConfirmingSave = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)

                Button("Revert", systemImage: "arrow.uturn.backward") {
                    hostsText = originalHostsText
                    status = nil
                }
                .disabled(!hasUnsavedChanges)
                Spacer()
            }

            SectionCard("Hosts File", icon: "doc.text") {
                HStack(spacing: 8) {
                    Text(Self.hostsPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if hasUnsavedChanges {
                        Badge(text: "Unsaved changes", tone: .warning)
                    }
                    Spacer()
                }

                TextEditor(text: $hostsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        AnyShapeStyle(.quaternary.opacity(0.25)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Text("/etc/hosts is owned by root. Saving asks for an administrator password, then flushes the DNS cache so the change takes effect immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let status {
                    StatusBanner(message: status, tone: statusTone)
                }
            }

            SectionCard("Open", icon: "arrow.up.forward.app") {
                FormGrid(minimum: 160) {
                    Button("Terminal", systemImage: "terminal") {
                        openApplication(at: "/System/Applications/Utilities/Terminal.app")
                    }
                    Button("Console", systemImage: "doc.text.magnifyingglass") {
                        openApplication(at: "/System/Applications/Utilities/Console.app")
                    }
                    Button("Activity Monitor", systemImage: "chart.line.uptrend.xyaxis") {
                        openApplication(at: "/System/Applications/Utilities/Activity Monitor.app")
                    }
                    Button("Keychain Access", systemImage: "key") {
                        openApplication(at: "/System/Applications/Utilities/Keychain Access.app")
                    }
                }
            }

            OutputConsole(text: proxyOutput, title: "Proxy Configuration", minHeight: 200)
        }
        .task { await load() }
        .confirmationDialog(
            "Overwrite /etc/hosts?",
            isPresented: $isConfirmingSave
        ) {
            Button("Overwrite", role: .destructive) {
                Task { await save() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if keepsLocalhost {
                Text("This replaces the system hosts file and asks for an administrator password. A bad entry here can make parts of the network unreachable until it is corrected.")
            } else {
                Text("Warning: the new file has no localhost entry, which breaks many local services. This replaces the system hosts file and asks for an administrator password.")
            }
        }
    }

    private func load() async {
        status = nil
        let contents = (try? String(contentsOfFile: Self.hostsPath, encoding: .utf8))
        if let contents {
            hostsText = contents
            originalHostsText = contents
        } else {
            hostsText = ""
            originalHostsText = ""
            status = "Could not read \(Self.hostsPath)."
            statusTone = .warning
        }

        proxyOutput = await runCommandSections([
            (title: "System proxies", command: "/usr/sbin/scutil", arguments: ["--proxy"]),
            (title: "DNS configuration", command: "/usr/sbin/scutil", arguments: ["--dns"])
        ])
    }

    /// Whether the edit still maps `localhost`. Dropping it breaks a surprising
    /// amount of local software, so the confirmation calls it out.
    private var keepsLocalhost: Bool {
        hostsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { !$0.hasPrefix("#") && $0.contains("localhost") }
    }

    /// `/etc/hosts` is owned by root, so the new contents are staged in a
    /// temporary file and copied into place through the administrator prompt.
    /// Copying onto the existing file keeps its root:wheel 0644 ownership. The
    /// DNS caches are flushed in the same authorization so the change applies
    /// immediately.
    private func save() async {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("control-panel-hosts-\(UUID().uuidString)")

        do {
            try Data(hostsText.utf8).write(to: staged)
            defer { try? FileManager.default.removeItem(at: staged) }

            try await AdminCommand.run(
                [
                    ["/bin/cp", staged.path, "/private/etc/hosts"],
                    ["/usr/bin/dscacheutil", "-flushcache"],
                    ["/usr/bin/killall", "-HUP", "mDNSResponder"]
                ],
                prompt: "Control Panel wants to update /etc/hosts."
            )

            originalHostsText = hostsText
            status = "Saved \(Self.hostsPath) and flushed the DNS cache."
            statusTone = .success
        } catch AdminCommandError.cancelled {
            status = AdminCommandError.cancelled.errorDescription
            statusTone = .neutral
        } catch {
            status = "Could not save \(Self.hostsPath): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            statusTone = .warning
        }
    }
}
