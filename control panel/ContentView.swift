import SwiftUI

struct ContentView: View {
    @State private var activeDestination: SidebarDestination?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $activeDestination) {
            if searchText.isEmpty {
                ForEach(SidebarCategory.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(category.destinations) { destination in
                            sidebarRow(destination)
                        }
                    }
                }
            } else if searchResults.isEmpty {
                Text("No tools match “\(searchText)”.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Results") {
                    ForEach(searchResults) { destination in
                        sidebarRow(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Control Panel")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Find a tool")
    }

    private func sidebarRow(_ destination: SidebarDestination) -> some View {
        Label(destination.title, systemImage: destination.icon)
            .tag(destination)
            .help(destination.summary)
    }

    private var searchResults: [SidebarDestination] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return SidebarDestination.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: Detail

    private var detail: some View {
        Group {
            if let activeDestination {
                destinationView(for: activeDestination)
            } else {
                AppOverviewView { destination in
                    self.activeDestination = destination
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }

    @ViewBuilder
    private func destinationView(for destination: SidebarDestination) -> some View {
        let goBack = { activeDestination = nil }

        switch destination {
        case .generalAbout: GeneralAboutView(navigateBack: goBack)
        case .performance: PerformanceMonitorView(navigateBack: goBack)
        case .storage: StorageManagementView(navigateBack: goBack)
        case .displays: DisplaysGraphicsView(navigateBack: goBack)
        case .sound: SoundAudioView(navigateBack: goBack)
        case .battery: BatteryPowerView(navigateBack: goBack)
        case .privacySecurity: PrivacySecurityView(navigateBack: goBack)
        case .system: SystemOverviewView(navigateBack: goBack)
        case .networkDashboard: NetworkDashboardView(navigateBack: goBack)
        case .deviceScanner: DeviceScannerView(navigateBack: goBack)
        case .adapterConfig: AdapterConfigurationView(navigateBack: goBack)
        case .networkQuality: NetworkQualityToolView(navigateBack: goBack)
        case .ping: PingToolView(navigateBack: goBack)
        case .traceroute: TracerouteToolView(navigateBack: goBack)
        case .dnsLookup: DNSLookupView(navigateBack: goBack)
        case .portCheck: PortCheckToolView(navigateBack: goBack)
        case .httpInspector: HTTPInspectorToolView(navigateBack: goBack)
        case .wifi: WiFiToolView(navigateBack: goBack)
        case .printers: PrinterToolView(navigateBack: goBack)
        case .developerTools: DeveloperToolsView(navigateBack: goBack)
        case .backupRecovery: BackupRecoveryView(navigateBack: goBack)
        }
    }
}

#Preview {
    ContentView()
}
