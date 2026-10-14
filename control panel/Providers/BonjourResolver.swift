import Foundation
import Network

/// Turns a Bonjour service name into an address.
///
/// `NWBrowser` hands back service names, not addresses. Opening a connection
/// to the service endpoint is the supported way to make the system resolve
/// one, after which the connection's path reports the remote address. Shared
/// by printer discovery and the device scanner.
nonisolated enum BonjourResolver {
    /// Resolves preferring IPv4. Devices often answer Bonjour with an IPv6
    /// link-local address, which only works with its `%en0` zone attached and
    /// cannot be matched against the ARP table, so IPv4 is tried first.
    static func resolve(
        name: String,
        type: String,
        domain: String,
        timeout: Duration = .seconds(5)
    ) async -> (host: String, port: Int)? {
        if let ipv4 = await resolve(name: name, type: type, domain: domain, version: .v4, timeout: timeout) {
            return ipv4
        }
        return await resolve(name: name, type: type, domain: domain, version: .any, timeout: timeout)
    }

    /// IPv4 only. The device scanner wants addresses it can join to ARP
    /// entries, so an IPv6 answer is no use to it.
    static func resolveIPv4(
        name: String,
        type: String,
        domain: String,
        timeout: Duration = .seconds(3)
    ) async -> String? {
        await resolve(name: name, type: type, domain: domain, version: .v4, timeout: timeout)?.host
    }

    private static func resolve(
        name: String,
        type: String,
        domain: String,
        version: NWProtocolIP.Options.Version,
        timeout: Duration
    ) async -> (host: String, port: Int)? {
        // `type` and `domain` go in without surrounding dots, which is the form
        // NWEndpoint.service expects. Prefixing a dot silently produces an
        // endpoint that never resolves.
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)

        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = version
        }

        let connection = NWConnection(to: endpoint, using: parameters)
        defer { connection.cancel() }

        // Race the resolve against a sleep so an unreachable advertiser cannot
        // leave the caller waiting.
        let resolved: NWEndpoint? = await withTaskGroup(of: NWEndpoint?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    // Clearing the handler before resuming is what prevents a
                    // second state change from resuming twice.
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.stateUpdateHandler = nil
                            continuation.resume(returning: connection.currentPath?.remoteEndpoint)
                        case .failed, .cancelled, .waiting:
                            connection.stateUpdateHandler = nil
                            continuation.resume(returning: nil)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard case let .hostPort(host, port) = resolved else { return nil }
        return (describe(host), Int(port.rawValue))
    }

    /// IPv4 addresses sometimes carry a meaningless `%en0` scope, which is
    /// dropped. IPv6 link-local addresses genuinely need theirs, so it stays.
    static func describe(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            let text = "\(address)"
            return text.components(separatedBy: "%").first ?? text
        case .ipv6(let address):
            return "\(address)"
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
