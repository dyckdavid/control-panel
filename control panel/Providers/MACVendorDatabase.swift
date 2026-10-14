import Foundation

/// A normalised hardware address.
nonisolated struct MACAddress: Hashable, Sendable {
    /// Six octets as lowercase two-digit hex, colon separated.
    let canonical: String
    private let firstOctet: UInt8

    /// Accepts the forms macOS tools print, including `arp`'s habit of
    /// dropping leading zeros (`0:11:32:a:b:c`).
    init?(_ text: String) {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }

        var octets: [UInt8] = []
        for part in parts {
            guard part.count <= 2, let value = UInt8(part, radix: 16) else { return nil }
            octets.append(value)
        }

        // All-zero and broadcast entries are not devices.
        guard octets.contains(where: { $0 != 0 }), octets.contains(where: { $0 != 0xFF }) else { return nil }

        firstOctet = octets[0]
        canonical = octets.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// The vendor prefix (OUI) as six uppercase hex digits, e.g. `286FB9`.
    var oui: String {
        canonical.replacingOccurrences(of: ":", with: "").prefix(6).uppercased()
    }

    /// Set when the address is locally administered rather than burned in.
    /// iPhones, iPads, Android phones, and Macs use randomised "private"
    /// addresses like this per network, so they have no vendor to look up.
    var isLocallyAdministered: Bool {
        firstOctet & 0b0000_0010 != 0
    }

    var isMulticast: Bool {
        firstOctet & 0b0000_0001 != 0
    }
}

/// Maps MAC prefixes to manufacturers using the IEEE public OUI registry.
///
/// The registry is a 4 MB CSV that takes several seconds to download, so it is
/// fetched once, reduced to a compact prefix→name table in Application
/// Support, and refreshed every 90 days. Downloading the public registry sends
/// nothing about the devices being looked up. Lookups before the table is
/// ready simply return nil; nothing blocks on the download.
actor MACVendorDatabase {
    static let shared = MACVendorDatabase()

    private static let source = URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!
    private static let maxAge: TimeInterval = 90 * 24 * 60 * 60

    private var table: [String: String] = [:]
    private var loadTask: Task<Void, Never>?

    var isLoaded: Bool { !table.isEmpty }

    func vendor(for address: MACAddress) -> String? {
        table[address.oui]
    }

    /// Loads the cache, downloading or refreshing it when needed. Safe to call
    /// repeatedly; concurrent callers share one load.
    func prepare() async {
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { await self.load() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func load() async {
        let cache = Self.cacheURL

        if table.isEmpty, let cached = try? String(contentsOf: cache, encoding: .utf8) {
            table = Self.parseCache(cached)
        }

        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
            .map { Date.now.timeIntervalSince($0) } ?? .infinity

        guard table.isEmpty || age > Self.maxAge else { return }

        do {
            var request = URLRequest(url: Self.source)
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

            let fresh = Self.parseRegistry(String(decoding: data, as: UTF8.self))
            guard fresh.count > 1_000 else { return }   // a truncated download

            table = fresh
            try? FileManager.default.createDirectory(
                at: cache.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let serialized = fresh
                .map { "\($0.key)\t\($0.value)" }
                .sorted()
                .joined(separator: "\n")
            try? Data(serialized.utf8).write(to: cache, options: .atomic)
        } catch {
            // Offline, or IEEE is slow: keep whatever cache we have and try
            // again on the next scan.
        }
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier ?? "ControlPanel"
        return base.appending(path: folder).appending(path: "oui-vendors.tsv")
    }

    // MARK: Parsing

    private static func parseCache(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }
        return result
    }

    /// Parses `Registry,Assignment,Organization Name,Organization Address`.
    ///
    /// The file uses CRLF line endings, and Swift treats `\r\n` as one
    /// character — splitting on `"\n"` finds no lines at all — so lines are
    /// split on any newline. Organisation names may be quoted and contain
    /// commas, so fields are read with a small quote-aware scanner.
    static func parseRegistry(_ text: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = csvFields(line, limit: 3)
            guard fields.count >= 3 else { continue }
            let assignment = fields[1].uppercased()
            guard assignment.count == 6 else { continue }
            result[assignment] = tidy(fields[2])
        }

        return result
    }

    private static func csvFields(_ line: Substring, limit: Int) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
                if fields.count == limit { return fields }
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    /// Registry names are often shouty or carry legal suffixes. Trim the noise
    /// so a row reads "Apple" or "Cisco Systems", not "Cisco Systems, Inc".
    private static func tidy(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespaces)
        for suffix in [", Inc.", ", Inc", " Inc.", " Inc", ", Ltd.", " Co., Ltd.", " Co.,Ltd.", " Co.,LTD",
                       " Corporation", " Corp.", " GmbH", " LLC", " Limited", " Ltd."] {
            if text.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count))
            }
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }
}
