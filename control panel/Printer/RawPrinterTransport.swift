import Foundation
import Network

/// Opens a plain TCP connection to a printer and pushes bytes at it.
///
/// This is the JetDirect / AppSocket path (usually port 9100). It needs no CUPS
/// queue and no driver, which is what makes it the right tool for ESC/POS
/// thermal printers and for verifying that a printer is reachable at all.
///
/// Connection setup lives in `TCPProbe`, since "open a socket to host:port" is
/// the same job the port checker does.
enum RawPrinterTransport {
    /// Resolves a user-entered host and port into a Network endpoint.
    static func endpoint(host: String, portText: String) throws -> (NWEndpoint.Host, NWEndpoint.Port) {
        try TCPProbe.endpoint(host: host, portText: portText)
    }

    /// Connects, writes, and disconnects.
    static func send(
        _ payload: Data,
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: Duration = .seconds(8)
    ) async throws {
        let connection = TCPProbe.makeConnection(host: host, port: port, timeout: timeout)
        defer { connection.cancel() }

        try await TCPProbe.race(timeout) {
            try await TCPProbe.waitUntilReady(connection)
            try await write(payload, to: connection)
        }
    }

    /// Connects, writes, reads one response, and disconnects.
    static func sendAndReceive(
        _ payload: Data,
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: Duration = .seconds(8)
    ) async throws -> Data {
        let connection = TCPProbe.makeConnection(host: host, port: port, timeout: timeout)
        defer { connection.cancel() }

        return try await TCPProbe.race(timeout) {
            try await TCPProbe.waitUntilReady(connection)
            try await write(payload, to: connection)
            return try await read(from: connection)
        }
    }

    /// Opens and immediately closes a connection, reporting how long it took.
    /// Used by "Test connection" in the add-printer flow.
    static func probe(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: Duration = .seconds(5)
    ) async throws -> Duration {
        try await TCPProbe.connect(host: host, port: port, timeout: timeout)
    }

    // MARK: I/O

    private static func write(_ payload: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func read(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }
}
