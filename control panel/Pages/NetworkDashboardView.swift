import SwiftUI
import AppKit

struct NetworkDashboardView: View {
    let navigateBack: () -> Void

    @State private var provider = NetworkInfoProvider()
    @State private var showIPv6 = false

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Network",
                subtitle: "Internet reachability, addresses, DNS, routing, and adapters.",
                icon: "network",
                isBusy: provider.isRefreshing,
                navigateBack: navigateBack
            ) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await provider.refresh() }
                }
                .disabled(provider.isRefreshing)

                Button("Run Benchmark", systemImage: "speedometer") {
                    Task { await provider.runBenchmark() }
                }
                .disabled(provider.isBenchmarking)

                Button("Copy Report", systemImage: "doc.on.doc") {
                    copyToClipboard(provider.report)
                }

                Button("Save Report…", systemImage: "square.and.arrow.down") {
                    saveReport()
                }
                Spacer()
            }

            StatRow {
                StatCard(
                    title: "Public IP",
                    value: provider.publicIP,
                    detail: provider.publicIPDetail,
                    icon: "globe",
                    tone: provider.publicIP == "Unavailable" ? .warning : .success
                )
                StatCard(
                    title: "Gateway",
                    value: provider.defaultGateway,
                    detail: "via \(provider.primaryInterface)",
                    icon: "arrow.triangle.branch"
                )
                StatCard(
                    title: "DNS",
                    value: provider.dnsServers.first ?? "Unavailable",
                    detail: "\(provider.dnsServers.count) server\(provider.dnsServers.count == 1 ? "" : "s")",
                    icon: "list.bullet.indent"
                )
                StatCard(
                    title: "Interfaces",
                    value: "\(provider.interfaces.count)",
                    detail: "\(provider.hardwarePorts.count) hardware port\(provider.hardwarePorts.count == 1 ? "" : "s")",
                    icon: "cable.connector"
                )
            }

            if provider.publicIP == "Unavailable" {
                StatusBanner(
                    message: "The public IP lookup failed. A proxy, VPN, or firewall may be blocking outbound HTTPS.",
                    tone: .warning
                )
            }

            SectionCard("Addresses", icon: "number") {
                Toggle("Show IPv6 addresses", isOn: $showIPv6)

                let visible = provider.interfaces.filter { showIPv6 || !$0.isIPv6 }

                if visible.isEmpty {
                    EmptyStateRow(message: "No addresses found.", icon: "questionmark.circle")
                } else {
                    ForEach(visible) { interface in
                        KeyValueRow(
                            title: "\(interface.name) · \(interface.family)",
                            value: interface.address,
                            isMonospaced: true
                        )
                    }
                }
            }

            SectionCard("DNS Servers", icon: "list.bullet.indent") {
                if provider.dnsServers.isEmpty {
                    EmptyStateRow(message: "No resolvers reported.", icon: "questionmark.circle")
                } else {
                    ForEach(provider.dnsServers, id: \.self) { server in
                        Text(server)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SectionCard("Hardware Ports", icon: "cable.connector") {
                if provider.hardwarePorts.isEmpty {
                    EmptyStateRow(message: "No hardware ports reported.", icon: "questionmark.circle")
                } else {
                    ForEach(provider.hardwarePorts) { port in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(port.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(port.device)\(port.address.isEmpty ? "" : " · \(port.address)")")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SectionCard("Network Services", icon: "list.bullet.rectangle") {
                if provider.networkServices.isEmpty {
                    EmptyStateRow(message: "No services reported.", icon: "questionmark.circle")
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(provider.networkServices, id: \.self) { service in
                            Text(service)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .panelSurface(corner: 10)
                        }
                    }
                }
            }

            OutputConsole(
                text: provider.benchmarkSummary,
                title: "Benchmark",
                isRunning: provider.isBenchmarking,
                minHeight: 140
            )
        }
        .task { await provider.refresh() }
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NetworkReport-\(Int(Date.now.timeIntervalSince1970)).txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(provider.report.utf8).write(to: url)
    }
}
