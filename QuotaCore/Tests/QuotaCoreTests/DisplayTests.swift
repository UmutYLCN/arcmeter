import XCTest
@testable import QuotaCore

final class DisplayTests: XCTestCase {
    private func fixture() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "quota-axi-v5", withExtension: "json", subdirectory: "Fixtures")))
    }

    private func snapshot() throws -> Snapshot { try QuotaDecoder.decode(fixture()) }

    func testTilesCarryFiveHourPrimaryAndWeeklySecondary() throws {
        let snapshot = try snapshot()
        let tiles = ProviderTile.tiles(for: snapshot, at: snapshot.generatedAt)
        XCTAssertEqual(tiles.map(\.name), ["Claude", "Codex", "agy Gemini", "agy Claude/GPT"])
        XCTAssertEqual(tiles.map(\.mark), [.claude, .codex, .gemini, .agy])
        XCTAssertEqual(tiles.map(\.fiveHour), [96, 100, 100, 100])
        XCTAssertEqual(tiles.map(\.weekly), [33, 84, 86, 100])
        XCTAssertNotNil(tiles[0].weeklyReset)
        XCTAssertTrue(tiles.allSatisfy { $0.fiveHourReset != nil })
        XCTAssertEqual(ResetCountdown.remaining(until: tiles[0].fiveHourReset, now: snapshot.generatedAt), "4h 45m")
        XCTAssertTrue(tiles.allSatisfy { $0.availability == .measured && !$0.isStale })
    }

    func testMediumRowDropsAgyClaudeGPT() throws {
        let snapshot = try snapshot()
        let tiles = ProviderTile.tiles(for: snapshot, at: snapshot.generatedAt)
        XCTAssertEqual(ProviderTile.withoutAgyClaudeGPT(tiles).map(\.name), ["Claude", "Codex", "agy Gemini"])
        let placeholders = ProviderTile.withoutAgyClaudeGPT(ProviderTile.tiles(for: nil, at: .now))
        XCTAssertEqual(placeholders.map(\.mark), [.claude, .codex, .gemini])
        XCTAssertEqual(tiles.count, 4, "the filter must not change what the other layouts receive")
    }

    func testStaleAuthorizationAndMissingSnapshotStates() throws {
        let snapshot = try snapshot()
        let late = snapshot.generatedAt.addingTimeInterval(Snapshot.staleInterval + 1)
        XCTAssertTrue(ProviderTile.tiles(for: snapshot, at: late).allSatisfy(\.isStale))

        let placeholders = ProviderTile.tiles(for: nil, at: .now)
        XCTAssertEqual(placeholders.count, 4)
        XCTAssertTrue(placeholders.allSatisfy { $0.fiveHour == nil && $0.fiveHourReset == nil && $0.weekly == nil && $0.availability == .unavailable })

        var report = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var providers = try XCTUnwrap(report["providers"] as? [[String: Any]])
        providers[0]["state"] = ["status": "auth_required", "stale": false]
        report["providers"] = providers
        let auth = try QuotaDecoder.decode(JSONSerialization.data(withJSONObject: report))
        let tiles = ProviderTile.tiles(for: auth, at: auth.generatedAt)
        XCTAssertEqual(tiles[0].availability, .authorizationNeeded)
        XCTAssertNil(tiles[0].fiveHour)
        XCTAssertEqual(tiles[1].availability, .measured)
    }

    func testRingFractionClampsAndTreatsUnknownAsEmpty() {
        XCTAssertEqual(RingGauge.fraction(96), 0.96, accuracy: 1e-9)
        XCTAssertEqual(RingGauge.fraction(100), 1)
        XCTAssertEqual(RingGauge.fraction(0), 0)
        XCTAssertEqual(RingGauge.fraction(nil), 0)
        XCTAssertEqual(RingGauge.fraction(140), 1)
        XCTAssertEqual(RingGauge.fraction(-5), 0)
        XCTAssertEqual(RingGauge.fraction(.nan), 0)
        XCTAssertEqual(PercentText.text(95.6), "96")
        XCTAssertEqual(PercentText.text(nil), "—")
    }

    func testQuotaLevelWarnsBelowTwentyAndAlertsBelowTen() {
        XCTAssertEqual([100.0, 50, 20, 19.9, 10, 9.9, 0].map { QuotaLevel(remaining: $0) },
                       [.normal, .normal, .normal, .warning, .warning, .critical, .critical])
        XCTAssertEqual(QuotaLevel(remaining: nil), .normal)
        XCTAssertEqual(QuotaLevel(remaining: .nan), .normal)
    }

    func testSegmentBarLightsTenthsOfRemainingQuota() {
        XCTAssertEqual([33.0, 84, 86, 100, 0].map { SegmentBar.filled($0, count: 10) }, [3, 8, 9, 10, 0])
        XCTAssertEqual(SegmentBar.filled(nil, count: 10), 0)
        XCTAssertEqual(SegmentBar.filled(250, count: 10), 10)
    }

    func testElapsedText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func text(_ seconds: Double) -> String { ElapsedText.text(since: now.addingTimeInterval(-seconds), now: now) }
        XCTAssertEqual(text(20), "<1 min")
        XCTAssertEqual(text(120), "2 min")
        XCTAssertEqual(text(1920), "32 min")
        XCTAssertEqual(text(3 * 3600 + 600), "3 hr")
        XCTAssertEqual(text(86400 * 2), "2 d")
        XCTAssertEqual(text(-30), "<1 min")
    }

    func testProviderCycleAdvancesAndWraps() {
        XCTAssertEqual((0..<5).reduce([0]) { $0 + [ProviderCycle.next(after: $1 == 0 ? 0 : $0.last!, count: 4)] }.dropFirst().prefix(5),
                       [1, 2, 3, 0, 1])
        XCTAssertEqual(ProviderCycle.next(after: 3, count: 4), 0)
        XCTAssertEqual(ProviderCycle.clamped(9, count: 4), 0)
        XCTAssertEqual(ProviderCycle.clamped(-1, count: 4), 0)
        XCTAssertEqual(ProviderCycle.next(after: 2, count: 0), 0)
    }

    func testResetCountdownFormats() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func text(_ seconds: Double?) -> String? { ResetCountdown.text(until: seconds.map { now.addingTimeInterval($0) }, now: now) }
        XCTAssertEqual(text(3 * 86400 + 4 * 3600 + 120), "3d 4h")
        XCTAssertEqual(text(2 * 86400), "2d")
        XCTAssertEqual(text(5 * 3600 + 12 * 60), "5h 12m")
        XCTAssertEqual(text(3600), "1h")
        XCTAssertEqual(text(42 * 60), "42m")
        XCTAssertEqual(text(30), "<1m")
        XCTAssertEqual(text(-5), "due")
        XCTAssertNil(text(nil))
    }

    func testTimelineEntriesTickEveryMinuteAndMergeStaleTransitions() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = [-10.0, 90, 120, 7200].map { now.addingTimeInterval($0) }
        let dates = TimelineDates.entries(now: now, staleTransitions: stale)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertFalse(dates.contains(stale[0]), "transitions already past are dropped")
        XCTAssertTrue(dates.contains(now.addingTimeInterval(60)))
        XCTAssertTrue(dates.contains(now.addingTimeInterval(3600)))
        XCTAssertTrue(dates.contains(stale[1]))
        XCTAssertTrue(dates.contains(stale[3]), "a transition past the hour still gets its entry")
        XCTAssertEqual(dates.count, 1 + 60 + 2, "the 120 s transition coincides with a minute tick and adds nothing")
    }

    func testFiveHourCountdownShowsNilWhenUnknownOrPassed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func text(_ seconds: Double?) -> String? { ResetCountdown.remaining(until: seconds.map { now.addingTimeInterval($0) }, now: now) }
        XCTAssertEqual(text(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(text(47 * 60), "47m")
        XCTAssertNil(text(nil))
        XCTAssertNil(text(0))
        XCTAssertNil(text(-5))
    }
}
