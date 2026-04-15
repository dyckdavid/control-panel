# Control Panel

A native macOS utility hub that brings Windows Control Panel-style system management to your Mac. Built with SwiftUI, it provides a unified interface for system info, network diagnostics, printer management, and more — all from one window.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Core System
- **General** — Model, serial number, macOS version, uptime, and live CPU/memory/storage stats
- **Performance** — Real-time CPU, memory, and top process monitoring
- **Storage** — Disk usage breakdown and home folder sizes
- **Displays** — Connected displays and GPU summary
- **Sound** — Audio device listing
- **Battery & Power** — Battery health, charge state, and power details
- **Privacy & Security** — FileVault, Gatekeeper, and firewall status
- **System** — Architecture, processor count, and memory overview

### Network
- **Network Dashboard** — Public IP, gateway, DNS, interfaces, hardware ports, and benchmark
- **Device Scanner** — ARP + ping sweep to discover LAN devices
- **IP & DNS Config** — DHCP, static IP, subnet, router, and DNS via `networksetup`
- **Network Quality** — Apple's `networkQuality` throughput and responsiveness test
- **Ping** — Streaming ping with configurable count and IPv6 support
- **Path Diagnostics** — Route, resolver, ping, DNS, and throughput checks combined
- **DNS Lookup** — Query A, AAAA, CNAME, MX, NS, and TXT records using `dig`
- **Port Check** — TCP reachability test for multiple ports via `nc`
- **HTTP Inspector** — Fetch status, headers, and body preview for any URL
- **Wi-Fi** — Radio state, current SSID, power toggle, and nearby network scan (CoreWLAN)

### Devices
- **Printers** — Full CUPS queue management: add, remove, pause, resume, set default, print test page, view jobs
- **Thermal Printer Tools** — ESC/POS commands over raw TCP: open drawer, full/partial cut, paper feed, status query
- **Printer Web Admin** — Embedded browser for printer admin pages and CUPS interface

### Advanced
- **Developer Tools** — Hosts file editor, proxy settings viewer, Terminal/Console launchers
- **Backup & Recovery** — Time Machine status, destinations, and latest backup info

## Requirements

- macOS 14 (Sonoma) or later
- No App Store sandbox restrictions — runs with full system access for diagnostics

## Installation

### Download

1. Go to the [Releases](../../releases) page
2. Download the latest `.dmg` or `.zip`
3. Drag **Control Panel.app** to your Applications folder
4. On first launch, right-click the app and choose **Open** (required for apps outside the App Store)

### Build from Source

```bash
git clone https://github.com/dyckdavid/control-panel.git
cd control-panel
open "control panel.xcodeproj"
```

Then build and run with **Cmd+R** in Xcode.

## Permissions

Some features require elevated access:

| Feature | Requirement |
|---------|-------------|
| Wi-Fi scan | Location Services permission (macOS requires this for SSID/scan) |
| IP & DNS config | Admin password (prompted by `networksetup`) |
| Hosts file editing | Write access to `/etc/hosts` (may need to run as admin) |
| Printer queue management | CUPS admin access |
| Device scanner | Local network access |

The app will show clear messages when a permission is missing rather than failing silently.

## Architecture

- **Pure SwiftUI** — No storyboards, no UIKit bridging (except `WKWebView` for printer admin)
- **No external dependencies** — Uses only Apple frameworks: SwiftUI, AppKit, CoreWLAN, Network, SystemConfiguration, WebKit
- **Process-based diagnostics** — Leverages macOS CLI tools (`ping`, `dig`, `route`, `lpstat`, `system_profiler`, etc.) for maximum capability outside the App Store sandbox
- **Async/await throughout** — Modern Swift concurrency for all background operations

### Project Structure

```
control panel/
├── control_panelApp.swift    # App entry point and window config
├── ContentView.swift         # Navigation, all system views, and shared UI components
├── PingToolView.swift        # Ping tool
├── DNSLookupView.swift       # DNS lookup tool
├── TracerouteToolView.swift  # Path diagnostics tool
├── WiFiToolView.swift        # Wi-Fi inspector
├── PrinterToolView.swift     # Printer management and thermal controls
└── ProcessRunner.swift       # Shell command execution utilities
```

## Distribution

This app is distributed directly (not via the App Store). Download the latest release from the [Releases](../../releases) page, or build from source using Xcode.

On first launch, you may need to right-click the app and choose **Open** to bypass Gatekeeper.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-tool`)
3. Commit your changes
4. Push and open a Pull Request

Issues and feature requests are welcome.
