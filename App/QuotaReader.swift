import Darwin
import Foundation
import QuotaCore

/// A background actor keeps process I/O off SwiftUI's main actor. Output is
/// drained concurrently and the child has a deadline, including a kill fallback.
actor QuotaReader {
    enum ReadError: LocalizedError {
        case failed, timedOut
        var errorDescription: String? {
            switch self {
            case .failed: return "quota-axi failed. Check /usr/local/bin/quota-axi in Terminal, then refresh."
            case .timedOut: return "quota-axi did not finish within 90 seconds. Try Refresh again."
            }
        }
    }

    func read() async throws -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/quota-axi")
        process.arguments = ["--json", "--allow-keychain-prompt", "--provider", "claude,codex,agy"]
        var environment = ProcessInfo.processInfo.environment
        // getpwuid resolves the real home even inside the widget's sandbox container, as SnapshotStore does.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        environment["PATH"] = QuotaRunnerPath.make(home: home)
        environment.removeValue(forKey: "QUOTA_AXI_SNAPSHOT")
        environment.removeValue(forKey: "QUOTA_AXI_MAX_AGE")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        // Never retain or display raw diagnostic output, which can contain identity.
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        let forceStop = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let began = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
        DispatchQueue.global().asyncAfter(deadline: .now() + 95, execute: forceStop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        forceStop.cancel()
        guard Date().timeIntervalSince(began) < 90 else { throw ReadError.timedOut }
        guard process.terminationStatus == 0 else { throw ReadError.failed }
        return try QuotaDecoder.decode(data)
    }
}
