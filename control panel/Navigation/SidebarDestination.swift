import Foundation

/// Every screen the app can show.
enum SidebarDestination: String, Hashable, Identifiable, CaseIterable {
    case generalAbout
    case performance
    case storage
    case displays
    case sound
    case battery
    case privacySecurity
    case system
    case networkDashboard
    case deviceScanner
    case adapterConfig
    case networkQuality
    case ping
    case traceroute
    case dnsLookup
    case portCheck
    case httpInspector
    case wifi
    case printers
    case developerTools
    case backupRecovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalAbout: "General"
        case .performance: "Performance"
        case .storage: "Storage"
        case .displays: "Displays"
        case .sound: "Sound"
        case .battery: "Battery & Power"
        case .privacySecurity: "Privacy & Security"
        case .system: "System"
        case .networkDashboard: "Network"
        case .deviceScanner: "Device Scanner"
        case .adapterConfig: "IP & DNS"
        case .networkQuality: "Network Quality"
        case .ping: "Ping"
        case .traceroute: "Path Diagnostics"
        case .dnsLookup: "DNS"
        case .portCheck: "Port Check"
        case .httpInspector: "HTTP Inspector"
        case .wifi: "Wi-Fi"
        case .printers: "Printers"
        case .developerTools: "Developer Tools"
        case .backupRecovery: "Backup & Recovery"
        }
    }

    var icon: String {
        switch self {
        case .generalAbout: "macwindow"
        case .performance: "waveform.path.ecg"
        case .storage: "internaldrive"
        case .displays: "display.2"
        case .sound: "speaker.wave.2"
        case .battery: "battery.100"
        case .privacySecurity: "lock.shield"
        case .system: "gearshape.2"
        case .networkDashboard: "network"
        case .deviceScanner: "dot.radiowaves.up.forward"
        case .adapterConfig: "slider.horizontal.3"
        case .networkQuality: "speedometer"
        case .ping: "dot.radiowaves.left.and.right"
        case .traceroute: "arrow.triangle.branch"
        case .dnsLookup: "globe"
        case .portCheck: "firewall"
        case .httpInspector: "network.badge.shield.half.filled"
        case .wifi: "wifi"
        case .printers: "printer"
        case .developerTools: "hammer"
        case .backupRecovery: "externaldrive.badge.timemachine"
        }
    }

    var summary: String {
        switch self {
        case .generalAbout: "About this Mac, version, model, serial, uptime."
        case .performance: "CPU, memory, disk, and top processes."
        case .storage: "Storage usage and folder breakdown."
        case .displays: "Displays, GPUs, and the current display summary."
        case .sound: "Audio devices and the output/input summary."
        case .battery: "Battery health, capacity, and power status."
        case .privacySecurity: "FileVault, Gatekeeper, firewall, and permission links."
        case .system: "Machine and runtime information."
        case .networkDashboard: "Adapters, gateway, DNS, and internet status."
        case .deviceScanner: "Scan local devices by ARP and ping sweep."
        case .adapterConfig: "Set DHCP, static IP, subnet, router, and DNS."
        case .networkQuality: "Throughput and responsiveness."
        case .ping: "Latency and packet loss."
        case .traceroute: "Route, resolver, and throughput diagnostics."
        case .dnsLookup: "A, AAAA, MX, NS, TXT, and more."
        case .portCheck: "Test TCP reachability for one or more ports."
        case .httpInspector: "Fetch headers, status, and a body preview."
        case .wifi: "Current radio state and scan results."
        case .printers: "Add printers, manage queues, and print."
        case .developerTools: "Hosts file, proxies, Terminal, and Console."
        case .backupRecovery: "Time Machine status and destinations."
        }
    }

    var category: SidebarCategory {
        switch self {
        case .generalAbout, .performance, .storage, .displays, .sound, .battery, .privacySecurity, .system:
            .mac
        case .networkDashboard, .deviceScanner, .adapterConfig, .networkQuality,
             .ping, .traceroute, .dnsLookup, .portCheck, .httpInspector, .wifi:
            .network
        case .printers:
            .devices
        case .developerTools, .backupRecovery:
            .utilities
        }
    }

    /// Screens that change system state rather than just reporting it. The
    /// sidebar marks these so it is obvious which tools can alter the Mac.
    var isMutating: Bool {
        switch self {
        case .adapterConfig, .printers, .developerTools, .wifi: true
        default: false
        }
    }
}

/// Sidebar grouping.
enum SidebarCategory: String, CaseIterable, Identifiable {
    case mac = "Mac"
    case network = "Network"
    case devices = "Devices"
    case utilities = "Utilities"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mac: "macwindow"
        case .network: "network"
        case .devices: "printer"
        case .utilities: "hammer"
        }
    }

    var summary: String {
        switch self {
        case .mac: "Mac information, performance, storage, displays, and privacy."
        case .network: "Connection status, Wi-Fi, DNS, diagnostics, and IP tools."
        case .devices: "Printers and device-specific controls."
        case .utilities: "Backup, developer, and maintenance tools."
        }
    }

    /// Derived from `SidebarDestination.category`, so adding a screen only
    /// means updating one switch.
    var destinations: [SidebarDestination] {
        SidebarDestination.allCases.filter { $0.category == self }
    }

    var featuredDestinations: [SidebarDestination] {
        switch self {
        case .mac: [.generalAbout, .performance, .privacySecurity]
        case .network: [.networkDashboard, .adapterConfig, .wifi]
        case .devices: [.printers]
        case .utilities: [.backupRecovery, .developerTools]
        }
    }

    var secondaryDestinations: [SidebarDestination] {
        destinations.filter { !featuredDestinations.contains($0) }
    }
}
