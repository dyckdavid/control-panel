import Foundation
import Observation

enum ProcessRunnerError: LocalizedError {
    case executableNotFound(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "\(path) is not available on this Mac."
        }
    }
}

nonisolated struct ProcessExecutionResult: Sendable {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32

    var succeeded: Bool { terminationStatus == 0 }

    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated struct ProcessRunner: Sendable {
    /// The PATH handed to child processes, so tools that shell out themselves
    /// can still find their helpers.
    private static let searchPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    static func findExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func runSync(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws -> ProcessExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = makeEnvironment(overrides: environment)

        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain both pipes before waiting. A child that fills the 64 KB pipe
        // buffer blocks forever if we wait for exit first.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessExecutionResult(
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }

    @discardableResult
    static func runCaptureSync(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws -> String {
        try runSync(
            launchPath,
            arguments,
            environment: environment,
            currentDirectory: currentDirectory
        ).combinedOutput
    }

    /// Runs a tool off the caller's actor and returns its combined output.
    static func runCapture(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runCaptureSync(
                launchPath,
                arguments,
                environment: environment,
                currentDirectory: currentDirectory
            )
        }.value
    }

    /// Runs a tool off the caller's actor and returns the full result, including
    /// the exit status.
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async throws -> ProcessExecutionResult {
        try await Task.detached(priority: .userInitiated) {
            try runSync(
                launchPath,
                arguments,
                environment: environment,
                currentDirectory: currentDirectory
            )
        }.value
    }

    private static func makeEnvironment(overrides: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides ?? [:] {
            environment[key] = value
        }
        environment["PATH"] = searchPath + ":" + (environment["PATH"] ?? "")
        return environment
    }
}

/// A long-running child process whose output streams into the UI as it arrives.
/// Used by the screens that watch a command rather than waiting for it.
@MainActor
@Observable
final class ProcessTask {
    var output = ""
    var isRunning = false

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdoutPipe: Pipe?
    @ObservationIgnored private var stderrPipe: Pipe?

    func start(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) throws {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = Self.makeEnvironment(overrides: environment)

        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        output = ""
        isRunning = true

        let appendHandler: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.output += text
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = appendHandler
        stderrPipe.fileHandleForReading.readabilityHandler = appendHandler

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish()
            }
        }

        try process.run()
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        finish()
    }

    /// Replaces the output with a message and stops any running process. Used
    /// to report why a command could not be launched.
    func showMessage(_ message: String) {
        stop()
        output = message
    }

    private func finish() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        isRunning = false
    }

    private static func makeEnvironment(overrides: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in overrides ?? [:] {
            environment[key] = value
        }
        environment["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:"
            + (environment["PATH"] ?? "")
        return environment
    }
}
