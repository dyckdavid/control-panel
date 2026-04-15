import Foundation
import Combine

enum ProcessRunnerError: Error {
    case executableNotFound
    case failedToLaunch
}

struct ProcessExecutionResult {
    let standardOutput: String
    let standardError: String
    let terminationStatus: Int32

    var combinedOutput: String {
        let parts = [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }
}

struct ProcessRunner {
    static func findExecutable(_ candidates: [String]) -> String? {
        let fileManager = FileManager.default
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
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

        var fullEnvironment = ProcessInfo.processInfo.environment
        if let environment {
            for (key, value) in environment {
                fullEnvironment[key] = value
            }
        }
        fullEnvironment["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:" + (fullEnvironment["PATH"] ?? "")
        process.environment = fullEnvironment

        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        return ProcessExecutionResult(
            standardOutput: stdout,
            standardError: stderr,
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
        try runSync(launchPath, arguments, environment: environment, currentDirectory: currentDirectory).combinedOutput
    }

    static func runCapture(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try runCaptureSync(launchPath, arguments, environment: environment, currentDirectory: currentDirectory)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

final class ProcessTask: ObservableObject {
    @Published var output = ""
    @Published var isRunning = false

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

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

        var fullEnvironment = ProcessInfo.processInfo.environment
        if let environment {
            for (key, value) in environment {
                fullEnvironment[key] = value
            }
        }
        fullEnvironment["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:" + (fullEnvironment["PATH"] ?? "")
        process.environment = fullEnvironment

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

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.output += text
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                self?.output += text
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stdoutPipe = nil
                self?.stderrPipe = nil
                self?.process = nil
            }
        }

        try process.run()
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        isRunning = false
    }

    func showMessage(_ message: String) {
        stop()
        output = message
    }

    deinit {
        stop()
    }
}
