# Control Panel

A native macOS utility hub that brings Windows Control Panel-style system management to your Mac. Built with SwiftUI, it puts system information, network diagnostics, printer management, and device discovery in one window.

![macOS](https://img.shields.io/badge/macOS-27%2B-blue)
![Xcode](https://img.shields.io/badge/Xcode-27-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Mac
- **General** — Model, chip, serial number, macOS version, uptime, and live CPU, memory, storage, and GPU readings
- **Performance** — Live CPU, memory, and disk gauges read straight from the kernel, plus top processes by CPU or memory
- **Storage** — Startup disk usage, home folder sizes, and mounted volumes
- **Displays** — Connected displays and graphics hardware
- **Sound** — Audio input and output devices
- **Battery & Power** — Charge level, power source, and the full power report
- **Privacy & Security** — FileVault, Gatekeeper, System Integrity Protection, firewall, and stealth mode
- **System** — Machine identity, processors, memory, thermal state, and kernel details

### Network
- **Network** — Public IP, gateway, DNS servers, addresses, hardware ports, services, and an exportable report
- **Device Scanner** — Finds every device on your subnet and names it using Bonjour and reverse DNS, including Apple model identifiers. Optionally shows hardware addresses and manufacturers (see [Device Scanner](#device-scanner))
- **IP & DNS** — Switch a network service between DHCP and a static address, and set its DNS servers
- **Network Quality** — Apple's `networkQuality` throughput and responsiveness test
- **Ping** — Streaming ping with a packet count or continuous mode, IPv4 and IPv6
- **Path Diagnostics** — Traceroute alongside the route table, resolver, DNS answer, and ping
- **DNS** — A, AAAA, CNAME, MX, NS, TXT, SOA, and ANY lookups through the system resolver or a server you choose
- **Port Check** — TCP reachability for single ports, lists, and ranges, with connection times
- **HTTP Inspector** — Status, timing, headers, and a body preview for any URL, with or without following redirects
- **Wi-Fi** — Radio power, the current network and signal, and a scan of nearby networks with band, channel, and security

### Devices
- **Printers** — Add printers by Bonjour discovery or by IP address, creating real macOS print queues any app can use. Pause, resume, set the default, cancel jobs, and print files, text, or a test page
- **Direct IP printing** — Print to a network printer over IPP or a raw socket without installing a queue first
- **Thermal / receipt printers** — Receipts, self-test, paper feed, full and partial cut, cash drawer kick, and status readback over ESC/POS
- **Printer admin** — Open a printer's own web page or its CUPS page in the browser

### Utilities
- **Developer Tools** — Hosts file editor that flushes the DNS cache on save, proxy and resolver configuration, and quick launchers
- **Backup & Recovery** — Time Machine status, destinations, and latest backup

## Requirements

- macOS 27 or later, which means a Mac with Apple silicon

Control Panel runs outside the App Sandbox so it can drive the system's printing and networking tools directly. That is also why it is distributed directly rather than through the Mac App Store.

## Installation

### Download

1. Open the [Releases](../../releases) page.
2. Download the latest `ControlPanel-<version>.dmg`.
3. Open the disk image and drag **Control Panel** to **Applications**.

Releases are signed with a Developer ID and notarized by Apple, so the app opens normally with no Gatekeeper workaround.

### Build from source

Requires Xcode 27 with the macOS 27 SDK.

```bash
git clone https://github.com/dyckdavid/control-panel.git
cd control-panel
open "control panel.xcodeproj"
```

Then build and run with **⌘R**.

## Permissions

Control Panel asks for each permission only when you use the feature that needs it.

| Feature | What macOS asks for | Why |
|---------|---------------------|-----|
| Printers, Device Scanner, Port Check, direct printing | **Local Network** access | macOS requires it for any connection to devices on your network, including Bonjour discovery |
| Wi-Fi network names | **Location Services** | macOS treats Wi-Fi names as location data and hides them otherwise. The app never reads your actual location |
| Hosts file save | Administrator password, each save | `/etc/hosts` is owned by root |
| IP & DNS changes | Administrator password, each change | Changing a network service requires root |
| Device hardware addresses (optional) | Administrator password, each scan | macOS 27 only shows device MAC addresses to administrators |
| Adding and removing printers | None for administrator accounts | Handled by CUPS (`lpadmin`) |

Administrator prompts are the standard macOS password dialog. Each runs a single, fixed command, and nothing is installed or left running in the background.

## Printers

### Adding a printer

**Add Printer** discovers printers advertising on your network, or takes an IP address or host name directly, and creates a queue with `lpadmin`. The queue appears in System Settings and works in every app.

- **IPP printers** — most network printers from the last decade — use the driverless **IPP Everywhere** option. **Test Connection** asks the printer to describe itself first.
- **Raw TCP / JetDirect printers** (port 9100) can't describe themselves, so they need a driver. Point-of-sale drivers (POS-58, POS-80) and label drivers (Zebra, DYMO) are offered when installed.
- Some receipt printers advertise IPP without really implementing it. When a printer doesn't answer, the form switches itself to Raw TCP with a point-of-sale driver and tells you why.

### Thermal printers and ESC/POS

macOS no longer allows raw pass-through print queues, so ESC/POS commands — cut, feed, cash drawer — cannot travel through a print queue. The thermal tools send them straight to the printer's IP address and port instead. A queue added with a POS driver still works for printing ordinary documents.

### Direct printing

**Print Directly to an IP Printer** sends a job over IPP or a raw socket with no queue installed. Many modern printers don't accept plain text over IPP and expect PDF or raster formats. The app checks what the printer supports and tells you to use a queue instead, rather than printing pages of garbage.

## Device Scanner

By default, the scanner needs no password. It probes every address in your subnet with ping and TCP, where a refused connection still proves a device is there, and adds anything advertising on Bonjour. Names come from Bonjour and reverse DNS. Apple devices also report their model identifier, such as `Mac16,10`.

Turn on **Read hardware addresses and vendors** to also see each device's MAC address and manufacturer. macOS 27 hides MAC addresses from ordinary apps, so this asks for an administrator password on each scan to read the system's network table, and changes nothing. Manufacturers come from the public IEEE registry, which is downloaded once, cached locally, and refreshed every 90 days. Downloading the registry sends nothing about your devices.

Phones, tablets, and recent Macs use randomized private addresses on each network. These are labelled **Private address**, since they have no manufacturer to look up.

On networks larger than a /22 (1,022 addresses), the scan covers the /22 around your Mac.

## Architecture

- **SwiftUI throughout**, using the macOS 27 SDK
- **No third-party dependencies** — only Apple frameworks: SwiftUI, AppKit, Network, CoreWLAN, CoreLocation, SystemConfiguration, and UniformTypeIdentifiers
- **System tools where they're the right interface** — `lpadmin`, `networksetup`, `system_profiler`, `dig`, and others. Each call checks its exit status and reports errors instead of failing silently
- **Native APIs where they're better** — kernel counters for live statistics, the Network framework for port checks and printer connections, and Bonjour for discovery
- **Swift concurrency** for all background work, with `@Observable` state

### Project structure

```
control panel/
├── control_panelApp.swift          App entry point
├── ContentView.swift               Sidebar, search, and navigation
├── ProcessRunner.swift             Running system tools
├── Design/                         Shared components: pages, cards, banners, console
├── Navigation/                     Sidebar destinations and categories
├── Pages/                          One file per screen
├── Printer/                        Printing
│   ├── CUPSController.swift          Print queues via the CUPS tools
│   ├── IPPClient.swift               IPP/2.0 client for direct printing
│   ├── ESCPOS.swift                  Receipt printer command builder
│   ├── PrinterDiscovery.swift        Bonjour printer discovery
│   └── …                             Printers page, add-printer sheet, composer
└── Providers/                      Data sources
    ├── AdminCommand.swift            Administrator prompt for privileged commands
    ├── SystemStatsSampler.swift      CPU, memory, and load from the kernel
    ├── NetworkDevicesProvider.swift  Device scanner
    ├── MACVendorDatabase.swift       IEEE manufacturer lookup
    └── …                             Network, Wi-Fi location access, TCP probes
```

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-tool`)
3. Commit your changes
4. Push and open a pull request

Issues and feature requests are welcome.
