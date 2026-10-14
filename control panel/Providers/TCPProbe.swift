import Foundation
import Network

enum TCPProbeError: LocalizedError {
    case invalidPort(String)
    case emptyHost
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidPort(let value): "\"\(value)\" is not a valid TCP port."
        case .emptyHost: "Enter a host name or IP address."
        case .timedOut: "No response in time."
        case .cancelled: "The connection closed before it was established."
        }
    }
}

/// Opens a TCP connection and reports how long the handshake took.
///
/// Shared by the port checker and by the printer tools' "Test connection",
/// because "can I open a socket to this host and port" is the same question in
/// both places.
enum TCPProbe {
    /// Resolves user-entered text into a Network endpoint.
    static func endpoint(host: String, portText: String) throws -> (NWEndpoint.Host, NWEndpoint.Port) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { throw TCPProbeError.emptyHost }

        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = NWEndpoint.Port(trimmedPort) else {
            throw TCPProbeError.invalidPort(trimmedPort)
        }

        return (NWEndpoint.Host(trimmedHost), port)
    }

    /// Connects and immediately disconnects, returning the elapsed time.
    /// Throws when the host refuses, is unreachable, or stays silent.
    static func connect(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: Duration = .seconds(5)
    ) async throws -> Duration {
        let connection = makeConnection(host: host, port: port, timeout: timeout)
        defer { connection.cancel() }

        let clock = ContinuousClock()
        let start = clock.now
        try await race(timeout) {
            try await waitUntilReady(connection)
        }
        return start.duration(to: clock.now)
    }

    /// Formats a `Duration` as whole milliseconds for display.
    static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: Shared plumbing

    static func makeConnection(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: Duration = .seconds(8)
    ) -> NWConnection {
        let options = NWProtocolTCP.Options()
        options.connectionTimeout = Int(max(1, timeout.components.seconds))
        options.noDelay = true
        return NWConnection(host: host, port: port, using: NWParameters(tls: nil, tcp: options))
    }

    static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Clearing the handler before resuming is what keeps a second state
            // change from resuming the continuation twice.
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: TCPProbeError.cancelled)
                case .waiting(let error):
                    // `waiting` means there is no viable route — host down,
                    // wrong subnet, port filtered. Fail fast rather than
                    // sitting here until the timeout fires.
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Races `operation` against a sleep so a silent host cannot hang the UI.
    static func race<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TCPProbeError.timedOut
            }

            guard let result = try await group.next() else {
                throw TCPProbeError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
