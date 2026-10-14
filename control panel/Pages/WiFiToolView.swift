import SwiftUI
import CoreWLAN

struct WiFiNetwork: Identifiable, Hashable {
    let ssid: String
    let bssid: String
    let rssi: Int
    let channel: Int
    let band: String
    let security: String

    var id: String { "\(ssid)-\(bssid)-\(channel)" }

    var displayName: String {
        ssid.isEmpty ? "Hidden network" : ssid
    }

    /// Four bars mapped from dBm. −50 and up is excellent, below −80 unusable.
    var signalBars: Int {
        switch rssi {
        case (-55)...: 4
        case (-67)..<(-55): 3
        case (-75)..<(-67): 2
        default: 1
        }
    }

    var signalTone: Tone {
        switch signalBars {
        case 4, 3: .success
        case 2: .neutral
        default: .warning
        }
    }
}

struct WiFiToolView: View {
    let navigateBack: () -> Void

    @State private var interfaceNames: [String] = []
    @State private var interfaceName = ""
    @State private var currentSSID = "Not connected"
    @State private var currentRSSI: Int?
    @State private var currentChannel = "—"
    @State private var powerOn = false
    @State private var networks: [WiFiNetwork] = []
    @State private var isScanning = false
    @State private var message: String?
    @State private var messageTone: Tone = .neutral
    @State private var location = LocationAuthorization()

    var body: some View {
        PageScaffold {
            PageHeader(
                title: "Wi-Fi",
                subtitle: "The current radio state plus a scan of the access points in range.",
                icon: "wifi",
                isBusy: isScanning,
                navigateBack: navigateBack
            ) {
                Button("Scan", systemImage: "dot.radiowaves.left.and.right") {
                    Task { await scan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning || interfaceName.isEmpty)

                Button("Reload", systemImage: "arrow.clockwise") {
                    Task { await loadState() }
                }

                Button("Wi-Fi Settings", systemImage: "arrow.up.forward.app") {
                    openSystemSettings(pane: "com.apple.wifi-settings-extension")
                }
                Spacer()
            }

            StatRow {
                StatCard(
                    title: "Interface",
                    value: interfaceName.isEmpty ? "None" : interfaceName,
                    detail: interfaceNames.isEmpty
                        ? "No Wi-Fi hardware found"
                        : "\(interfaceNames.count) interface\(interfaceNames.count == 1 ? "" : "s")",
                    icon: "antenna.radiowaves.left.and.right",
                    tone: interfaceNames.isEmpty ? .warning : .neutral
                )
                StatCard(
                    title: "Network",
                    value: currentSSID,
                    detail: powerOn ? "Radio on" : "Radio off",
                    icon: "wifi",
                    tone: powerOn ? .success : .warning
                )
                StatCard(
                    title: "Signal",
                    value: currentRSSI.map { "\($0) dBm" } ?? "—",
                    detail: "Channel \(currentChannel)",
                    icon: "cellularbars"
                )
                StatCard(
                    title: "In range",
                    value: "\(networks.count)",
                    detail: "From the last scan",
                    icon: "list.bullet"
                )
            }

            if !location.isAuthorized {
                locationNotice
            }

            SectionCard("Radio", icon: "power") {
                if interfaceNames.count > 1 {
                    Picker("Interface", selection: $interfaceName) {
                        ForEach(interfaceNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: interfaceName) { _, _ in
                        Task { await loadState() }
                    }
                }

                Toggle("Wi-Fi power", isOn: $powerOn)
                    .toggleStyle(.switch)
                    .disabled(interfaceName.isEmpty)
                    .onChange(of: powerOn) { oldValue, newValue in
                        // Only react to user changes, not to `loadState`
                        // writing the value it just read back.
                        guard oldValue != newValue else { return }
                        setPower(newValue)
                    }

                if let message {
                    StatusBanner(message: message, tone: messageTone)
                }
            }

            SectionCard("Nearby Networks", icon: "antenna.radiowaves.left.and.right") {
                if networks.isEmpty {
                    EmptyStateRow(
                        message: isScanning
                            ? "Scanning…"
                            : "Run a scan to list the access points in range.",
                        icon: "magnifyingglass"
                    )
                } else {
                    ForEach(networks) { network in
                        networkRow(network)
                    }
                }
            }
        }
        .task { await loadState() }
        .onChange(of: location.status) { _, _ in
            // Names become readable the moment permission is granted.
            Task {
                await loadState()
                if location.isAuthorized, !networks.isEmpty {
                    await scan()
                }
            }
        }
    }

    // MARK: Permission

    private var locationNotice: some View {
        SectionCard("Network Names Hidden", icon: "location.slash") {
            Text("macOS treats Wi-Fi network names as location data, so it hides the connected network and the names in scan results until this app has Location access. Control Panel never reads your actual location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Layout.control) {
                if location.needsSettings {
                    Button("Open Location Settings", systemImage: "arrow.up.forward.app") {
                        location.openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Access was declined earlier, so it has to be turned on in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Allow Location Access", systemImage: "location") {
                        location.request()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
    }

    // MARK: Rows

    private func networkRow(_ network: WiFiNetwork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi", variableValue: Double(network.signalBars) / 4)
                .font(.title3)
                .foregroundStyle(network.signalTone.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(network.ssid.isEmpty && !location.isAuthorized
                         ? "Name hidden by macOS"
                         : network.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(network.ssid.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    if network.ssid == currentSSID {
                        Badge(text: "Connected", tone: .accent)
                    }
                }
                Text(network.bssid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(network.rssi) dBm")
                    .font(.callout)
                HStack(spacing: 4) {
                    Badge(text: network.band)
                    Badge(text: "ch \(String(network.channel))")
                    Badge(text: network.security)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: State

    private func loadState() async {
        let client = CWWiFiClient.shared()
        let interfaces = client.interfaces() ?? []
        interfaceNames = interfaces.compactMap(\.interfaceName).sorted()

        guard !interfaceNames.isEmpty else {
            interfaceName = ""
            currentSSID = "Unavailable"
            powerOn = false
            message = "No Wi-Fi interface was detected on this Mac."
            messageTone = .warning
            return
        }

        if !interfaceNames.contains(interfaceName) {
            interfaceName = interfaceNames[0]
        }

        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            message = "Could not open the \(interfaceName) interface."
            messageTone = .warning
            return
        }

        powerOn = interface.powerOn()
        let rssi = interface.rssiValue()
        // A non-zero RSSI means the radio is associated even when macOS is
        // withholding the network's name.
        let isAssociated = powerOn && rssi != 0
        if let ssid = interface.ssid() {
            currentSSID = ssid
        } else if isAssociated {
            currentSSID = location.isAuthorized ? "Connected" : "Connected · name hidden"
        } else {
            currentSSID = "Not connected"
        }
        currentRSSI = isAssociated ? rssi : nil
        currentChannel = interface.wlanChannel().map { String($0.channelNumber) } ?? "—"
        message = nil
    }

    private func setPower(_ enabled: Bool) {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            message = "Could not open the \(interfaceName) interface."
            messageTone = .warning
            return
        }

        do {
            try interface.setPower(enabled)
            message = enabled ? "Wi-Fi turned on." : "Wi-Fi turned off."
            messageTone = .success
        } catch {
            message = "Could not change Wi-Fi power: \(error.localizedDescription)"
            messageTone = .warning
        }

        Task { await loadState() }
    }

    private func scan() async {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            message = "Could not open the \(interfaceName) interface."
            messageTone = .warning
            return
        }

        isScanning = true
        message = nil
        defer { isScanning = false }

        // `scanForNetworks` blocks for a couple of seconds, so keep it off the
        // main actor.
        let found = await Task.detached {
            (try? interface.scanForNetworks(withName: nil)).map { results in
                results.map { network in
                    WiFiNetwork(
                        ssid: network.ssid ?? "",
                        bssid: network.bssid ?? "Unknown",
                        rssi: network.rssiValue,
                        channel: network.wlanChannel?.channelNumber ?? 0,
                        band: Self.bandTitle(network.wlanChannel?.channelBand),
                        security: Self.securityTitle(network)
                    )
                }
            }
        }.value

        guard let found else {
            networks = []
            message = "The scan failed. Wi-Fi scanning needs Location Services permission for this app."
            messageTone = .warning
            return
        }

        networks = found.sorted { $0.rssi > $1.rssi }
        if networks.isEmpty {
            message = "The scan returned no networks."
            messageTone = .neutral
        }
    }

    // MARK: Formatting

    nonisolated private static func bandTitle(_ band: CWChannelBand?) -> String {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: "—"
        }
    }

    nonisolated private static func securityTitle(_ network: CWNetwork) -> String {
        let candidates: [(CWSecurity, String)] = [
            (.wpa3Personal, "WPA3"),
            (.wpa3Enterprise, "WPA3-E"),
            (.wpa2Personal, "WPA2"),
            (.wpa2Enterprise, "WPA2-E"),
            (.wpaPersonal, "WPA"),
            (.dynamicWEP, "WEP"),
            (.none, "Open")
        ]

        for (security, title) in candidates where network.supportsSecurity(security) {
            return title
        }
        return "Unknown"
    }
}
