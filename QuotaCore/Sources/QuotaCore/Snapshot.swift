import Foundation

public enum QuotaPeriod: String, Codable, Sendable, CaseIterable {
    case fiveHour, weekly

    public var label: String { self == .fiveHour ? "5h" : "7d" }
}

public struct WindowQuota: Codable, Identifiable, Sendable, Equatable {
    public var id: QuotaPeriod { period }
    public let period: QuotaPeriod
    public let percentRemaining: Double?
    public let resetsAt: Date?
    public let status: String
    public let isLimiting: Bool
}

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
    // Optional storage keeps snapshots written by the first app version readable.
    private let windowQuotas: [WindowQuota]?
    public let runwayStatus: String?
    public let exhaustionResetAt: Date?

    public var windows: [WindowQuota] {
        windowQuotas ?? QuotaPeriod.allCases.map {
            WindowQuota(period: $0, percentRemaining: nil, resetsAt: nil,
                        status: "refresh needed", isLimiting: false)
        }
    }

    init(provider: String, scope: String, name: String, percentRemaining: Double?, status: String,
         limitingWindow: String?, resetsAt: Date?, projectedExhaustedAt: Date?, observedAt: Date,
         sourceStale: Bool, windowQuotas: [WindowQuota], runwayStatus: String?, exhaustionResetAt: Date?) {
        self.provider = provider
        self.scope = scope
        self.name = name
        self.percentRemaining = percentRemaining
        self.status = status
        self.limitingWindow = limitingWindow
        self.resetsAt = resetsAt
        self.projectedExhaustedAt = projectedExhaustedAt
        self.observedAt = observedAt
        self.sourceStale = sourceStale
        self.windowQuotas = windowQuotas
        self.runwayStatus = runwayStatus
        self.exhaustionResetAt = exhaustionResetAt
    }

    public func isStale(at date: Date) -> Bool {
        sourceStale || date.timeIntervalSince(observedAt) >= Snapshot.staleInterval
            || observedAt.timeIntervalSince(date) > 60
    }

    public var runsOutBeforeReset: Bool {
        guard let projectedExhaustedAt, let reset = exhaustionResetAt ?? resetsAt else { return false }
        return projectedExhaustedAt < reset
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
        guard [1, 2].contains(snapshot.version), !snapshot.rows.isEmpty else { throw SnapshotError.invalidSnapshot }
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
                let limiting = sorted(windows.filter { availability?.limitingWindowIds?.contains($0.id) == true })
                let window = limiting.first
                let canReadWindows = provider != nil && provider?.notSetUp != true
                    && ["fresh", "stale"].contains(state?.status ?? "")
                let scopeWindows = windows.filter { availability?.boundedBy?.contains($0.id) == true && $0.shareOf == nil }
                let windowQuotas = QuotaPeriod.allCases.map { period in
                    let candidates = sorted(scopeWindows.filter { matches($0, period: period) })
                    let chosen = candidates.first
                    let untrusted = candidates.contains { state?.untrustedWindowIds?.contains($0.id) == true }
                    let valid = !candidates.isEmpty && candidates.allSatisfy { validPercent($0.percentRemaining) }
                    let measured = canReadWindows && valid && !untrusted
                    return WindowQuota(period: period,
                        percentRemaining: measured ? chosen?.percentRemaining : nil,
                        resetsAt: canReadWindows ? timestamp(chosen?.resetsAt) : nil,
                        status: measured ? "measured" : (!canReadWindows ? status : (candidates.isEmpty ? "not reported" : "unmeasurable")),
                        isLimiting: measured && candidates.contains { availability?.limitingWindowIds?.contains($0.id) == true })
                }
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
                    sourceStale: state?.stale == true || state?.status == "stale",
                    windowQuotas: windowQuotas, runwayStatus: status == "measured" ? runway?.status : nil,
                    exhaustionResetAt: timestamp(sorted(windows.filter { $0.id == runway?.limitingWindowId }).first?.resetsAt)))
            }
        }
        return Snapshot(version: 2, generatedAt: generatedAt, rows: rows)
    }

    private static func validPercent(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...100).contains($0) } == true
    }

    private static func sorted(_ windows: [Window]) -> [Window] {
        windows.sorted {
            if $0.percentRemaining != $1.percentRemaining {
                return ($0.percentRemaining ?? 101) < ($1.percentRemaining ?? 101)
            }
            return (timestamp($0.resetsAt) ?? .distantFuture) < (timestamp($1.resetsAt) ?? .distantFuture)
        }
    }

    private static func matches(_ window: Window, period: QuotaPeriod) -> Bool {
        switch period {
        case .fiveHour:
            return window.kind == "session" && (window.windowSeconds == 18_000
                || window.id == "five_hour" || window.id.contains("5h"))
        case .weekly: return window.kind == "weekly"
        }
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
    let untrustedWindowIds: [String]?
}
private struct Semantics: Decodable { let effectiveAvailability: [Availability]? }
private struct Availability: Decodable {
    let scope: String
    let status: String?
    let effectivePercentRemaining: Double?
    let boundedBy: [String]?
    let limitingWindowIds: [String]?
    let runway: Runway?
}
private struct Runway: Decodable {
    let status: String?
    let projectedExhaustedAt: String?
    let limitingWindowId: String?
}
private struct Window: Decodable {
    let id: String
    let label: String?
    let kind: String?
    let percentRemaining: Double?
    let resetsAt: String?
    let windowSeconds: Double?
    let shareOf: String?
}
