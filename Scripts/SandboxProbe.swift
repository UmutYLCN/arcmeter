import Darwin
import Foundation
import QuotaCore

/// Run in an ad-hoc signed sandbox to verify the widget's actual sharing path.
@main
struct SandboxProbe {
    static func main() throws {
        guard let snapshot = SnapshotStore.read() else {
            throw CocoaError(.fileReadNoPermission)
        }
        let providers = Set(snapshot.rows.map(\.provider))
        guard providers == ["claude", "codex", "agy"] else { throw SnapshotError.invalidSnapshot }
        for row in snapshot.rows {
            print("\(row.name): \(row.percentRemaining.map { String(Int($0)) + "%" } ?? row.status)")
        }
        let descriptor = Darwin.open(SnapshotStore.url.path, O_WRONLY)
        guard descriptor < 0 else {
            close(descriptor)
            fatalError("Snapshot unexpectedly writable from the sandbox")
        }
        guard errno == EPERM || errno == EACCES else { throw CocoaError(.fileWriteUnknown) }
        print("Sandbox: snapshot readable, writes denied.")
    }
}
