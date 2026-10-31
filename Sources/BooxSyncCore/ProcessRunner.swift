import Foundation

public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if cancelled { process.terminate() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

public struct ProcessDataResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let status: Int32
}

public enum ProcessRunner {
    /// Runs an executable to completion off the calling thread. Cancelling the task terminates the process.
    public static func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessResult {
        let result = try await runData(executable, arguments)
        return ProcessResult(
            stdout: String(decoding: result.stdout, as: UTF8.self),
            stderr: String(decoding: result.stderr, as: UTF8.self),
            status: result.status)
    }

    /// Same as `run` but keeps stdout as raw bytes (screenshots).
    public static func runData(_ executable: URL, _ arguments: [String]) async throws -> ProcessDataResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                try process.run()
                box.set(process)
                // Drain stderr on a side thread so a full pipe cannot block the child.
                var errData = Data()
                let errThread = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
                errThread.start()
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                while !errThread.isFinished { usleep(1000) }
                return ProcessDataResult(stdout: outData, stderr: errData, status: process.terminationStatus)
            }.value
        } onCancel: {
            box.cancel()
        }
    }
}
