import SwiftUI

struct DeviceScannerView: View {
    let navigateBack: () -> Void

    @State private var provider = NetworkDevicesProvider()
    @State private var filter = ""
    @State private var namedOnly = false

    private var visibleDevices: [NetworkDevice] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return provider.devices.filter { device in
            if namedOnly, !device.hasName { return false }
            guard !query.isEmpty else { return true }
            return [device.ipAddress, device.macText, device.name ?? "", device.vendorText ?? "", device.model ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        @Bindable var provider = provider

        return PageScaffold {
            PageHeader(
                title: "Device Scanner",
                subtitle: "Finds every device on this network by ARP, then names them with Bonjour, reverse DNS, and the IEEE vendor registry.",
                icon: "dot.radiowaves.up.forward",
                isBusy: provider.isScanning,
                navigateBack: navigateBack
            ) {
                Button("Scan", systemImage: "dot.radiowaves.left.and.right") {
                    Task {
                        await provider.scan()
                        // The vendor registry may still have been downloading.
                        await provider.refreshVendors()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(provider.isScanning)

                Button("Copy", systemImage: "doc.on.doc") {
                    copyToClipboard(provider.report)
                }
                .disabled(provider.devices.isEmpty)
                Spacer()
            }

            StatRow {
                StatCard(
                    title: "Network",
                    value: provider.subnet?.cidr ?? "Unknown",
                    detail: provider.subnet.map { "\($0.interface) · \($0.hostCount) addresses" } ?? "No IPv4 connection",
                    icon: "point.3.connected.trianglepath.dotted"
                )
                StatCard(
                    title: "Devices",
                    value: "\(provider.devices.count)",
                    detail: "\(provider.devices.filter(\.hasName).count) with names",
                    icon: "desktopcomputer.and.macbook"
                )
                StatCard(
                    title: "Private addresses",
                    value: provider.lastScanHadHardwareAddresses
                        ? "\(provider.devices.filter { $0.mac?.isLocallyAdministered == true }.count)"
                        : "—",
                    detail: provider.lastScanHadHardwareAddresses
                        ? "Phones and laptops using randomised MACs"
                        : "Turn on hardware addresses to see these",
                    icon: "theatermasks"
                )
            }

            if provider.isScanning {
                SectionCard("Scanning", icon: "antenna.radiowaves.left.and.right") {
                    ProgressView(value: provider.progress) {
                        Text(provider.status)
                            .font(.subheadline)
                    }
                }
            } else if !provider.status.isEmpty, provider.status != "Idle" {
                StatusBanner(message: provider.status, tone: provider.devices.isEmpty ? .warning : .success)
            }

            if provider.wasTruncated, let subnet = provider.subnet {
                StatusBanner(
                    message: "\(subnet.cidr) has \(subnet.hostCount) addresses, so only the 1,022 nearest this Mac were probed. Devices elsewhere still appear if this Mac has talked to them recently.",
                    tone: .neutral
                )
            }

            SectionCard("Hardware Addresses", icon: "barcode") {
                Toggle("Read hardware addresses and vendors", isOn: $provider.includeHardwareAddresses)
                Text("macOS 27 only shows device MAC addresses to administrators, so this asks for your password on each scan. It reads the network table and changes nothing. Vendors come from the public IEEE registry, downloaded once and cached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionCard("Devices", icon: "list.bullet") {
                HStack(spacing: Layout.control) {
                    TextField("Filter by name, IP, MAC, vendor, or model", text: $filter)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Named only", isOn: $namedOnly)
                        .toggleStyle(.checkbox)
                }

                if visibleDevices.isEmpty {
                    EmptyStateRow(
                        message: provider.isScanning ? "Scanning…" : "Nothing to show. Run a scan to discover devices.",
                        icon: "magnifyingglass"
                    )
                } else {
                    ForEach(visibleDevices) { device in
                        deviceRow(device)
                        if device.id != visibleDevices.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .task {
            if provider.devices.isEmpty {
                await provider.scan()
                await provider.refreshVendors()
            }
        }
    }

    private func deviceRow(_ device: NetworkDevice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: device.kind.symbol)
                .font(.title3)
                .foregroundStyle(device.hasName ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if device.isThisMac { Badge(text: "This Mac", tone: .accent) }
                    if device.isGateway { Badge(text: "Router", tone: .accent) }
                    if let source = device.nameSource { Badge(text: source.rawValue) }
                }

                HStack(spacing: 6) {
                    Text(device.macText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let vendor = device.vendorText {
                        Text("· \(vendor)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let model = device.model {
                        Text("· \(model)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text(device.ipAddress)
                .font(.callout.monospaced())
                .textSelection(.enabled)

            Button {
                copyToClipboard(device.ipAddress)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(device.ipAddress)")
            .accessibilityLabel("Copy \(device.ipAddress)")
        }
        .padding(.vertical, 2)
    }
}
