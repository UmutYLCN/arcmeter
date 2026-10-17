import Foundation

public enum ProviderMark: String, Sendable, CaseIterable {
    case claude, codex, gemini, agy
}

/// The widget's per-provider reading: only what the Orbit layouts draw.
public struct ProviderTile: Equatable, Sendable, Identifiable {
    public enum Availability: Sendable, Equatable { case measured, authorizationNeeded, unavailable }

    public let id: String
    public let mark: ProviderMark
    public let name: String
    public let fiveHour: Double?
    public let weekly: Double?
    public let fiveHourLimiting: Bool
    public let weeklyLimiting: Bool
    public let fiveHourReset: Date?
    public let weeklyReset: Date?
    public let availability: Availability
    public let isStale: Bool

    public init(row: QuotaRow, at date: Date) {
        let five = row.windows.first { $0.period == .fiveHour }
        let week = row.windows.first { $0.period == .weekly }
        id = row.id
        name = row.name
        mark = Self.mark(provider: row.provider, scope: row.scope)
        fiveHour = five?.percentRemaining
        weekly = week?.percentRemaining
        fiveHourLimiting = five?.isLimiting ?? false
        weeklyLimiting = week?.isLimiting ?? false
        fiveHourReset = five?.resetsAt
        weeklyReset = week?.resetsAt
        availability = row.status == "authorization needed" ? .authorizationNeeded
            : (fiveHour == nil && weekly == nil ? .unavailable : .measured)
        isStale = row.isStale(at: date)
    }

    public init(name: String, mark: ProviderMark) {
        id = name
        self.name = name
        self.mark = mark
        fiveHour = nil
        weekly = nil
        fiveHourLimiting = false
        weeklyLimiting = false
        fiveHourReset = nil
        weeklyReset = nil
        availability = .unavailable
        isStale = false
    }

    /// Only a limiting window that is running low gets the `*` and amber emphasis.
    public static let lowThreshold = 50.0
    public var fiveHourIsLow: Bool { fiveHourLimiting && (fiveHour ?? 100) <= Self.lowThreshold }
    public var weeklyIsLow: Bool { weeklyLimiting && (weekly ?? 100) <= Self.lowThreshold }

    /// Shown while no snapshot exists, so the layout never invents percentages.
    public static let placeholders = [
        ProviderTile(name: "Claude", mark: .claude), ProviderTile(name: "Codex", mark: .codex),
        ProviderTile(name: "agy Gemini", mark: .gemini), ProviderTile(name: "agy Claude/GPT", mark: .agy),
    ]

    public static func tiles(for snapshot: Snapshot?, at date: Date) -> [ProviderTile] {
        guard let snapshot else { return placeholders }
        return snapshot.rows.map { ProviderTile(row: $0, at: date) }
    }

    /// The medium row has room for three rings, so the agy Claude/GPT tile is left out of it.
    public static func withoutAgyClaudeGPT(_ tiles: [ProviderTile]) -> [ProviderTile] {
        tiles.filter { $0.mark != .agy }
    }

    static func mark(provider: String, scope: String) -> ProviderMark {
        switch (provider, scope) {
        case ("claude", _): return .claude
        case ("codex", _): return .codex
        case ("agy", "gemini"): return .gemini
        default: return .agy
        }
    }
}

public enum RingGauge {
    /// Fraction of the ring to fill; unknown readings draw an empty ring.
    public static func fraction(_ percent: Double?) -> Double {
        guard let percent, percent.isFinite else { return 0 }
        return min(max(percent / 100, 0), 1)
    }
}

/// How alarming a remaining-quota reading is; each indicator is judged on its own value.
public enum QuotaLevel: Sendable, Equatable {
    case normal, warning, critical

    public static let warningBelow = 20.0
    public static let criticalBelow = 10.0

    public init(remaining percent: Double?) {
        guard let percent, percent.isFinite else { self = .normal; return }
        self = percent < Self.criticalBelow ? .critical : (percent < Self.warningBelow ? .warning : .normal)
    }
}

public enum SegmentBar {
    /// Lit segments out of `count` for a remaining-quota percentage.
    public static func filled(_ percent: Double?, count: Int) -> Int {
        Int((RingGauge.fraction(percent) * Double(count)).rounded())
    }
}

public enum PercentText {
    public static func text(_ percent: Double?) -> String {
        percent.map { "\(Int($0.rounded()))" } ?? "—"
    }
}

/// The small widget shows one provider at a time; a tap advances the index.
public enum ProviderCycle {
    public static func clamped(_ index: Int, count: Int) -> Int {
        count > 0 && (0..<count).contains(index) ? index : 0
    }

    public static func next(after index: Int, count: Int) -> Int {
        count > 0 ? (clamped(index, count: count) + 1) % count : 0
    }
}

public enum ResetCountdown {
    /// "3d 4h", "5h 12m" or "42m"; nil when no reset time is known.
    public static func text(until date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 60 else { return seconds > 0 ? "<1m" : "due" }
        let minutes = Int(seconds / 60)
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
        return "\(mins)m"
    }

    /// Time left in the 5-hour window, "2h 14m" or "47m"; nil when the reset is unknown or already passed.
    public static func remaining(until date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        return text(until: date, now: now)
    }
}

public enum TimelineDates {
    /// WidgetKit only redraws a widget at its entry dates, so the countdown gets one entry per minute for the next hour.
    public static let horizon: TimeInterval = 3600

    /// `now`, one entry per minute up to the horizon, and any stale transitions still ahead; sorted and unique.
    public static func entries(now: Date, staleTransitions: [Date]) -> [Date] {
        let minutes = stride(from: 60.0, through: horizon, by: 60).map { now.addingTimeInterval($0) }
        let future = staleTransitions.filter { $0 > now }
        return Array(Set([now] + minutes + future)).sorted()
    }
}

public enum ElapsedText {
    /// "2 min", "3 hr" or "1 d" since `date`.
    public static func text(since date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 1440 { return "\(minutes / 60) hr" }
        return "\(minutes / 1440) d"
    }
}
