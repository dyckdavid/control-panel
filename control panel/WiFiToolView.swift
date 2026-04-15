import SwiftUI
import CoreWLAN

struct WiFiNetwork: Identifiable, Hashable {
    let ssid: String
    let bssid: String
    let rssi: Int

    var id: String { "\(ssid)-\(bssid)" }
}

struct WiFiToolView: View {
    let navigateBack: () -> Void
    @State private var interfaceNames = [String]()
    @State private var interfaceName = ""
    @State private var currentSSID = "Unavailable"
    @State private var powerOn = false
    @State private var networks = [WiFiNetwork]()
    @State private var isBusy = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderBlock(
                    title: "Wi-Fi",
                    subtitle: "Inspect the current radio state and nearby access points."
                ) {
                    Button("Back", systemImage: "chevron.left", action: navigateBack)
                    Picker("Interface", selection: $interfaceName) {
                        ForEach(interfaceNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .frame(width: 180)

                    Toggle("Power", isOn: $powerOn)
                        .toggleStyle(.switch)
                        .onChange(of: powerOn) { _, newValue in
                            setPower(newValue)
                        }
                        .disabled(interfaceName.isEmpty)

                    Button("Scan", systemImage: "dot.radiowaves.left.and.right", action: scan)
                        .disabled(isBusy || interfaceName.isEmpty)
                }

                HStack(spacing: 16) {
                    StatCard(
                        title: "Interface",
                        value: interfaceName.isEmpty ? "None" : interfaceName,
                        detail: interfaceNames.isEmpty ? "No Wi-Fi hardware found" : "\(interfaceNames.count) interface(s)"
                    )
                    StatCard(
                        title: "Current SSID",
                        value: currentSSID,
                        detail: powerOn ? "Radio on" : "Radio off"
                    )
                    StatCard(
                        title: "Networks",
                        value: "\(networks.count)",
                        detail: errorMessage.isEmpty ? "Latest scan" : errorMessage
                    )
                }

                SectionCard("Nearby Networks") {
                    if networks.isEmpty {
                        EmptyStateRow(message: errorMessage.isEmpty ? "Run a scan to list nearby networks." : errorMessage)
                    } else {
                        ForEach(networks) { network in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(network.ssid.isEmpty ? "<hidden>" : network.ssid)
                                    Text(network.bssid)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Text("\(network.rssi) dBm")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppBackground())
        .task { await loadState() }
    }

    private func loadState() async {
        let client = CWWiFiClient.shared()
        let interfaces = client.interfaces() ?? []
        interfaceNames = interfaces.compactMap(\.interfaceName).sorted()

        guard !interfaceNames.isEmpty else {
            interfaceName = ""
            currentSSID = "Unavailable"
            powerOn = false
            errorMessage = "No Wi-Fi interface was detected."
            return
        }

        if !interfaceNames.contains(interfaceName) {
            interfaceName = interfaceNames[0]
        }

        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            errorMessage = "Unable to open the selected Wi-Fi interface."
            return
        }

        powerOn = interface.powerOn()
        currentSSID = interface.ssid() ?? "Not connected"
        errorMessage = ""
    }

    private func setPower(_ enabled: Bool) {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            errorMessage = "Unable to open the selected Wi-Fi interface."
            return
        }

        do {
            try interface.setPower(enabled)
            errorMessage = ""
        } catch {
            errorMessage = "Failed to change Wi-Fi power."
        }

        Task { await loadState() }
    }

    private func scan() {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface(withName: interfaceName) ?? client.interface() else {
            errorMessage = "Unable to open the selected Wi-Fi interface."
            return
        }

        isBusy = true
        errorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async {
                    self.isBusy = false
                }
            }

            do {
                let results = try interface.scanForNetworks(withName: nil)
                let networks = results
                    .map { WiFiNetwork(ssid: $0.ssid ?? "", bssid: $0.bssid ?? "Unknown", rssi: $0.rssiValue) }
                    .sorted { $0.rssi > $1.rssi }

                DispatchQueue.main.async {
                    self.networks = networks
                    if networks.isEmpty {
                        self.errorMessage = "No networks were returned."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.networks = []
                    self.errorMessage = "Scan failed. Check Wi-Fi and location permissions."
                }
            }
        }
    }
}
