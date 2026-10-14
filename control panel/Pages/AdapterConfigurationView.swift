import SwiftUI

struct AdapterConfigurationView: View {
    let navigateBack: () -> Void

    @State private var provider = NetworkConfigurationProvider()
    @State private var manualIP = ""
    @State private var subnetMask = "255.255.255.0"
    @State private var router = ""
    @State private var dnsServers = ""

    var body: some View {
        @Bindable var provider = provider

        return PageScaffold {
            PageHeader(
                title: "IP & DNS",
                subtitle: "Switch a network service between DHCP and a static address, and set its resolvers.",
                icon: "slider.horizontal.3",
                isBusy: provider.isBusy,
                navigateBack: navigateBack
            ) {
                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await provider.refreshServices() }
                }
                .disabled(provider.isBusy)
                Spacer()
            }

            SectionCard("Network Service", icon: "list.bullet.rectangle") {
                if provider.services.isEmpty {
                    EmptyStateRow(message: "No network services reported.", icon: "questionmark.circle")
                } else {
                    Picker("Service", selection: $provider.selectedService) {
                        ForEach(provider.services, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: provider.selectedService) { _, newValue in
                        Task { await provider.loadDetails(for: newValue) }
                    }
                }
            }

            if let details = provider.details {
                StatRow {
                    StatCard(
                        title: "Configuration",
                        value: details.configuration,
                        detail: details.usesDHCP ? "Address assigned automatically" : "Address set manually",
                        icon: details.usesDHCP ? "arrow.triangle.2.circlepath" : "hand.point.up.left",
                        tone: details.usesDHCP ? .success : .accent
                    )
                    StatCard(title: "IPv4", value: details.ipAddress, detail: details.subnetMask, icon: "number")
                    StatCard(title: "Router", value: details.router, detail: "Default gateway", icon: "arrow.triangle.branch")
                    StatCard(
                        title: "DNS",
                        value: details.dnsServers.first ?? "Automatic",
                        detail: details.dnsServers.isEmpty ? "From DHCP" : "\(details.dnsServers.count) configured",
                        icon: "globe"
                    )
                }

                SectionCard("Current Configuration", icon: "doc.text") {
                    KeyValueRow(title: "Service", value: details.serviceName)
                    KeyValueRow(title: "Configuration", value: details.configuration)
                    KeyValueRow(title: "IPv4 address", value: details.ipAddress, isMonospaced: true)
                    KeyValueRow(title: "Subnet mask", value: details.subnetMask, isMonospaced: true)
                    KeyValueRow(title: "Router", value: details.router, isMonospaced: true)
                    KeyValueRow(title: "MAC address", value: details.macAddress, isMonospaced: true)
                    KeyValueRow(
                        title: "DNS servers",
                        value: details.dnsServers.isEmpty ? "Automatic" : details.dnsServers.joined(separator: ", "),
                        isMonospaced: true
                    )
                }
            }

            SectionCard("IPv4", icon: "number.square") {
                Text("Changes ask for an administrator password and take effect immediately. A static address that is wrong for this network will drop the connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: 12) {
                    FormField(label: "IP address", text: $manualIP, prompt: "192.168.1.20")
                    FormField(label: "Subnet mask", text: $subnetMask, prompt: "255.255.255.0")
                    FormField(label: "Router", text: $router, prompt: "192.168.1.1")
                }

                HStack(spacing: Layout.control) {
                    Button("Apply Static IP", systemImage: "checkmark.circle") {
                        Task { await provider.applyManual(ip: manualIP, subnet: subnetMask, router: router) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyStatic || provider.isBusy)

                    Button("Switch to DHCP", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await provider.applyDHCP() }
                    }
                    .disabled(provider.selectedService.isEmpty || provider.isBusy)

                    Spacer()
                }
            }

            SectionCard("DNS", icon: "globe") {
                FormField(
                    label: "DNS servers (comma separated)",
                    text: $dnsServers,
                    prompt: "1.1.1.1, 9.9.9.9"
                )

                HStack(spacing: Layout.control) {
                    Button("Apply DNS", systemImage: "checkmark.circle") {
                        Task { await provider.applyManualDNS(parsedDNSServers) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedDNSServers.isEmpty || provider.selectedService.isEmpty || provider.isBusy)

                    Button("Use DHCP Servers", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await provider.applyAutomaticDNS() }
                    }
                    .disabled(provider.selectedService.isEmpty || provider.isBusy)

                    Spacer()
                }
            }

            if !provider.statusMessage.isEmpty {
                StatusBanner(message: provider.statusMessage, tone: provider.statusTone)
            }
        }
        .task { await provider.refreshServices() }
        .onChange(of: provider.details) { _, details in
            syncFields(from: details)
        }
    }

    private var parsedDNSServers: [String] {
        dnsServers
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canApplyStatic: Bool {
        !provider.selectedService.isEmpty
            && !manualIP.trimmingCharacters(in: .whitespaces).isEmpty
            && !subnetMask.trimmingCharacters(in: .whitespaces).isEmpty
            && !router.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func syncFields(from details: NetworkServiceDetails?) {
        guard let details else { return }
        manualIP = details.ipAddress == "Unavailable" ? "" : details.ipAddress
        subnetMask = details.subnetMask == "Unavailable" ? "255.255.255.0" : details.subnetMask
        router = details.router == "Unavailable" ? "" : details.router
        dnsServers = details.dnsServers.joined(separator: ", ")
    }
}
