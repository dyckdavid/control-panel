import Foundation

enum AdminCommandError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Cancelled — no changes were made."
        case .failed(let message):
            message.isEmpty ? "The command failed." : message
        }
    }
}

/// Runs a command as root through the standard macOS administrator prompt.
///
/// Some changes — writing `/etc/hosts`, reconfiguring a network service — need
/// root, and an unsandboxed app still runs as the logged-in user. Rather than
/// install a privileged helper, the command is handed to `osascript`'s
/// `do shell script … with administrator privileges`, which shows the system
/// authentication dialog and runs that one command as root. The user sees a
/// prompt for every change, which is the intended trade-off.
enum AdminCommand {
    /// Runs one or more commands in a single authorization, so a multi-step
    /// change only prompts once. Each command is an executable path plus its
    /// arguments; nothing is ever interpolated into a shell unquoted.
    @discardableResult
    static func run(_ commands: [[String]], prompt: String) async throws -> String {
        let shellLine = commands
            .map { $0.map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")

        let script = """
            do shell script "\(appleScriptEscape(shellLine))" \
            with prompt "\(appleScriptEscape(prompt))" \
            with administrator privileges
            """

        let result = try await ProcessRunner.run("/usr/bin/osascript", ["-e", script])

        guard result.succeeded else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            // -128 is AppleScript's "User canceled".
            if message.contains("-128") || message.localizedCaseInsensitiveContains("user canceled") {
                throw AdminCommandError.cancelled
            }
            throw AdminCommandError.failed(cleaned(message))
        }

        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Quoting

    /// Wraps a word in single quotes for `/bin/sh`. A single quote inside the
    /// word is closed, escaped, and reopened: `it's` → `'it'\''s'`.
    static func shellQuote(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes text for an AppleScript string literal.
    static func appleScriptEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// osascript prefixes errors with `0:123: execution error: … (1)`. Keep
    /// only the human part.
    private static func cleaned(_ message: String) -> String {
        var text = message
        if let range = text.range(of: "execution error: ") {
            text = String(text[range.upperBound...])
        }
        if let parenthesis = text.range(of: " (", options: .backwards), text.hasSuffix(")") {
            text = String(text[..<parenthesis.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
