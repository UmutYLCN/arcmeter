import Foundation

public struct QuotaRow: Codable, Identifiable, Sendable, Equatable {
    public var id: String { provider + ":" + scope }
    public let provider: String
    public let scope: String
    public let name: String
    public let percentRemaining: Double?
    public let status: String
    public let limitingWindow: String?
    public let resetsAt: Date?
    public let projectedExhaustedAt: Date?
    public let observedAt: Date
    public let sourceStale: Bool

    public func isStale(at date: Date) -> Bool {
        sourceStale || date.timeIntervalSince(observedAt) >= Snapshot.staleInterval
            || observedAt.timeIntervalSince(date) > 60
    }

    public var runsOutBeforeReset: Bool {
        guard let projectedExhaustedAt, let resetsAt else { return false }
        return projectedExhaustedAt < resetsAt
    }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public static let staleInterval: TimeInterval = 30 * 60
    public let version: Int
    public let generatedAt: Date
    public let rows: [QuotaRow]

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) >= Self.staleInterval
            || generatedAt.timeIntervalSince(date) > 60 || rows.contains { $0.isStale(at: date) }
    }

    public static func decode(_ data: Data) throws -> Snapshot {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1, !snapshot.rows.isEmpty else { throw SnapshotError.invalidSnapshot }
        return snapshot
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

public enum SnapshotError: Error { case unsupportedSchema, invalidTimestamp, invalidSnapshot }

public enum QuotaDecoder {
    public static func decode(_ data: Data) throws -> Snapshot {
        let report = try JSONDecoder().decode(Report.self, from: data)
        guard report.schemaVersion == 5 else { throw SnapshotError.unsupportedSchema }
        guard let generatedAt = timestamp(report.generatedAt) else { throw SnapshotError.invalidTimestamp }
        var rows: [QuotaRow] = []
        for id in ["claude", "codex", "agy"] {
            let provider = report.providers.first { $0.provider == id }
            let scopes = provider?.quotaSemantics?.effectiveAvailability ?? []
            var names = scopes.map(\.scope)
            if id == "agy" {
                for scope in ["gemini", "claude_gpt"] where !names.contains(scope) { names.append(scope) }
            } else if names.isEmpty { names = ["all_models"] }
            for scope in names {
                let availability = scopes.first { $0.scope == scope }
                let state = provider?.state
                let value = availability?.effectivePercentRemaining
                let known = availability?.status == "known"
                    && value.map { $0.isFinite && (0...100).contains($0) } == true
                let status: String
                if state?.status == "auth_required" { status = "authorization needed" }
                else if provider == nil { status = "not reported" }
                else if provider?.notSetUp == true { status = "not set up" }
                else if let s = state?.status, !["fresh", "stale"].contains(s) {
                    status = s.replacingOccurrences(of: "_", with: " ")
                } else { status = known ? "measured" : "unmeasurable" }
                let windows = provider?.windows ?? []
                // Duplicate IDs occur in real agy output; choose the tightest reading,
                // then the earliest reset, rather than the first occurrence.
                let limiting = windows.filter { availability?.limitingWindowIds?.contains($0.id) == true }
                    .sorted {
                        if $0.percentRemaining != $1.percentRemaining {
                            return ($0.percentRemaining ?? 101) < ($1.percentRemaining ?? 101)
                        }
                        return (timestamp($0.resetsAt) ?? .distantFuture) < (timestamp($1.resetsAt) ?? .distantFuture)
                    }
                let window = limiting.first
                let runway = availability?.runway
                let projection = ["projected_exhaustion", "exhausted_now"].contains(runway?.status ?? "")
                    ? timestamp(runway?.projectedExhaustedAt) : nil
                let base = ["claude": "Claude", "codex": "Codex", "agy": "agy"][id]!
                let suffix = ["gemini": "Gemini", "claude_gpt": "Claude/GPT"][scope]
                    ?? (scope == "all_models" ? "" : scope.replacingOccurrences(of: "_", with: " "))
                rows.append(QuotaRow(
                    provider: id, scope: scope, name: base + (suffix.isEmpty ? "" : " " + suffix),
                    percentRemaining: status == "measured" ? value : nil, status: status,
                    limitingWindow: window.map { label($0) }, resetsAt: timestamp(window?.resetsAt),
                    projectedExhaustedAt: status == "measured" ? projection : nil,
                    observedAt: timestamp(state?.refreshedAt) ?? generatedAt,
                    sourceStale: state?.stale == true || state?.status == "stale"))
            }
        }
        return Snapshot(version: 1, generatedAt: generatedAt, rows: rows)
    }

    private static func label(_ window: Window) -> String {
        switch window.kind {
        case "weekly": return "7d"
        case "session" where window.id.contains("5h") || window.id == "five_hour": return "5h"
        default: return window.label ?? window.id.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func timestamp(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// Decode only quota evidence. Account identity, credentials, and raw errors never
// reach the shared snapshot, even if future CLI output includes more fields.
private struct Report: Decodable {
    let schemaVersion: Int
    let generatedAt: String
    let providers: [Provider]
}
private struct Provider: Decodable {
    let provider: String
    let windows: [Window]?
    let state: State?
    let quotaSemantics: Semantics?
    let notSetUp: Bool?
}
private struct State: Decodable {
    let status: String?
    let stale: Bool?
    let refreshedAt: String?
}
private struct Semantics: Decodable { let effectiveAvailability: [Availability]? }
private struct Availability: Decodable {
    let scope: String
    let status: String?
    let effectivePercentRemaining: Double?
    let limitingWindowIds: [String]?
    let runway: Runway?
}
private struct Runway: Decodable {
    let status: String?
    let projectedExhaustedAt: String?
}
private struct Window: Decodable {
    let id: String
    let label: String?
    let kind: String?
    let percentRemaining: Double?
    let resetsAt: String?
}
