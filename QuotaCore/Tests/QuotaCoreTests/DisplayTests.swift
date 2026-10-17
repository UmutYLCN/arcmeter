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
        XCTAssertEqual(tiles.map(\.weeklyIsLow), [true, false, false, false])
        XCTAssertTrue(tiles.allSatisfy { !$0.fiveHourIsLow })
        XCTAssertNotNil(tiles[0].weeklyReset)
        XCTAssertTrue(tiles.allSatisfy { $0.availability == .measured && !$0.isStale })
    }

    func testStaleAuthorizationAndMissingSnapshotStates() throws {
        let snapshot = try snapshot()
        let late = snapshot.generatedAt.addingTimeInterval(Snapshot.staleInterval + 1)
        XCTAssertTrue(ProviderTile.tiles(for: snapshot, at: late).allSatisfy(\.isStale))

        let placeholders = ProviderTile.tiles(for: nil, at: .now)
        XCTAssertEqual(placeholders.count, 4)
        XCTAssertTrue(placeholders.allSatisfy { $0.fiveHour == nil && $0.weekly == nil && $0.availability == .unavailable })

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
}
