import Foundation
import Network

/// Browses Bonjour for printers on the local network.
///
/// Three service types cover essentially everything: `_ipp._tcp` and
/// `_ipps._tcp` for IPP printers, and `_pdl-datastream._tcp` for the raw
/// port-9100 printers, which is what receipt and label printers advertise.
@MainActor
@Observable
final class PrinterDiscovery {
    private(set) var found: [DiscoveredPrinter] = []
    private(set) var isBrowsing = false
    private(set) var statusMessage = ""

    /// `found` collapsed to one entry per physical printer.
    var groups: [DiscoveredPrinterGroup] {
        Dictionary(grouping: found, by: \.serviceName)
            .map { DiscoveredPrinterGroup(name: $0.key, services: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var browsers: [NWBrowser] = []

    private static let serviceTypes = [
        "_ipp._tcp",
        "_ipps._tcp",
        "_pdl-datastream._tcp",
        "_printer._tcp"
    ]

    func start() {
        guard !isBrowsing else { return }
        stop()

        isBrowsing = true
        statusMessage = "Looking for printers on the local network…"

        for type in Self.serviceTypes {
            let parameters = NWParameters()
            parameters.includePeerToPeer = false

            let browser = NWBrowser(
                for: .bonjour(type: type, domain: nil),
                using: parameters
            )

            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    self?.apply(results: results, serviceType: type)
                }
            }

            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .failed(let error) = state {
                        self.statusMessage = "Bonjour browse failed: \(error.localizedDescription)"
                    }
                }
            }

            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()
        isBrowsing = false
    }

    /// Re-runs discovery from scratch.
    func refresh() {
        stop()
        found.removeAll()
        start()
    }

    private func apply(results: Set<NWBrowser.Result>, serviceType: String) {
        // Drop everything previously seen for this service type, then re-add,
        // so removals are handled as well as additions.
        found.removeAll { $0.serviceType == serviceType }

        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            found.append(
                DiscoveredPrinter(
                    serviceName: name,
                    serviceType: type.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    domain: domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    host: nil,
                    port: nil
                )
            )
        }

        found.sort { $0.serviceName.localizedStandardCompare($1.serviceName) == .orderedAscending }

        let count = groups.count
        statusMessage = count == 0
            ? "No printers are advertising themselves on this network yet."
            : "Found \(count) printer\(count == 1 ? "" : "s")."
    }

    /// Resolves a discovered service to an IP address and port by opening a
    /// connection to its Bonjour endpoint and reading back the resolved path.
    ///
    /// `NWBrowser` hands back service names, not addresses. Opening a
    /// connection is the supported way to make the system resolve one.
    static func resolve(_ printer: DiscoveredPrinter) async -> (host: String, port: Int)? {
        await BonjourResolver.resolve(
            name: printer.serviceName,
            type: printer.serviceType,
            domain: printer.domain
        )
    }
}
