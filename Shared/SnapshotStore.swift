import Darwin
import Foundation
import QuotaCore

/// getpwuid resolves the real home even inside the widget's sandbox container.
enum SnapshotStore {
    static var url: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/AIQuotaWidget/snapshot.json")
    }

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Snapshot.decode(data)
    }

    static func write(_ snapshot: Snapshot) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try snapshot.encoded().write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
