import XCTest
@testable import QuotaCore

final class QuotaDecoderTests: XCTestCase {
    private func fixture() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "quota-axi-v5", withExtension: "json", subdirectory: "Fixtures")))
    }

    private func modified(_ change: (inout [String: Any]) -> Void) throws -> Snapshot {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        change(&json)
        return try QuotaDecoder.decode(JSONSerialization.data(withJSONObject: json))
    }

    func testRealReadingAndDuplicateWindowIDs() throws {
        let snapshot = try QuotaDecoder.decode(fixture())
        XCTAssertEqual(snapshot.rows.map(\.name), ["Claude", "Codex", "agy Gemini", "agy Claude/GPT"])
        XCTAssertEqual(snapshot.rows.map(\.percentRemaining), [33, 84, 86, 100])
        XCTAssertEqual(snapshot.rows.map(\.limitingWindow), ["7d", "7d", "7d", "5h"])
        let gemini = snapshot.rows[2]
        XCTAssertEqual(gemini.resetsAt?.timeIntervalSince1970, 1792833199)
        XCTAssertTrue(snapshot.rows[0].runsOutBeforeReset)
        XCTAssertNotNil(snapshot.rows[0].projectedExhaustedAt)
        XCTAssertNil(snapshot.rows[1].projectedExhaustedAt)
        XCTAssertEqual(snapshot.rows.map { $0.windows.map(\.period) }, Array(repeating: [.fiveHour, .weekly], count: 4))
        XCTAssertEqual(snapshot.rows.map { $0.windows.map(\.percentRemaining) }, [[96, 33], [100, 84], [100, 86], [100, 100]])
        XCTAssertEqual(snapshot.rows[2].windows[1].resetsAt, gemini.resetsAt)
        XCTAssertEqual(snapshot.rows[0].windows.map(\.isLimiting), [false, true])
        XCTAssertEqual(snapshot.rows[1].runwayStatus, "through_reset")
        XCTAssertEqual(snapshot.rows[2].runwayStatus, "unknown")
    }

    func testMissingProvidersStayVisibleWithoutInventedPercentages() throws {
        let snapshot = try modified { $0["providers"] = [] }
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.percentRemaining == nil && $0.status == "not reported" })
        XCTAssertTrue(snapshot.rows.flatMap(\.windows).allSatisfy { $0.percentRemaining == nil && $0.resetsAt == nil })
    }

    func testAuthorizationOverridesOldQuota() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            providers[0]["state"] = ["status": "auth_required", "stale": false]
            json["providers"] = providers
        }
        XCTAssertEqual(snapshot.rows[0].status, "authorization needed")
        XCTAssertNil(snapshot.rows[0].percentRemaining)
        XCTAssertNil(snapshot.rows[0].projectedExhaustedAt)
        XCTAssertTrue(snapshot.rows[0].windows.allSatisfy { $0.percentRemaining == nil && $0.resetsAt == nil })
    }

    func testUnmeasurableAndOutOfRangeDoNotBecomeFullOrEmpty() throws {
        for value: Any in [NSNull(), -1, 101] {
            let snapshot = try modified { json in
                var providers = json["providers"] as! [[String: Any]]
                var semantics = providers[0]["quotaSemantics"] as! [String: Any]
                var availability = semantics["effectiveAvailability"] as! [[String: Any]]
                availability[0]["effectivePercentRemaining"] = value
                semantics["effectiveAvailability"] = availability
                providers[0]["quotaSemantics"] = semantics
                json["providers"] = providers
            }
            XCTAssertNil(snapshot.rows[0].percentRemaining)
            XCTAssertEqual(snapshot.rows[0].status, "unmeasurable")
        }
    }

    func testConflictingScopeDoesNotAssertPercentage() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var semantics = providers[0]["quotaSemantics"] as! [String: Any]
            var availability = semantics["effectiveAvailability"] as! [[String: Any]]
            availability[0]["status"] = "bound_conflict"
            semantics["effectiveAvailability"] = availability
            providers[0]["quotaSemantics"] = semantics
            json["providers"] = providers
        }
        XCTAssertNil(snapshot.rows[0].percentRemaining)
    }

    func testMissingAgyScopeStaysVisible() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var semantics = providers[2]["quotaSemantics"] as! [String: Any]
            var availability = semantics["effectiveAvailability"] as! [[String: Any]]
            availability.removeLast()
            semantics["effectiveAvailability"] = availability
            providers[2]["quotaSemantics"] = semantics
            json["providers"] = providers
        }
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertEqual(snapshot.rows[3].name, "agy Claude/GPT")
        XCTAssertNil(snapshot.rows[3].percentRemaining)
        XCTAssertEqual(snapshot.rows[3].status, "unmeasurable")
    }

    func testGenuineExhaustionRemainsZero() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var semantics = providers[0]["quotaSemantics"] as! [String: Any]
            var availability = semantics["effectiveAvailability"] as! [[String: Any]]
            availability[0]["effectivePercentRemaining"] = 0
            availability[0]["runway"] = ["status": "exhausted_now", "projectedExhaustedAt": json["generatedAt"]!]
            semantics["effectiveAvailability"] = availability
            providers[0]["quotaSemantics"] = semantics
            json["providers"] = providers
        }
        XCTAssertEqual(snapshot.rows[0].percentRemaining, 0)
        XCTAssertEqual(snapshot.rows[0].projectedExhaustedAt, snapshot.generatedAt)
    }

    func testSnapshotAgeAndRoundTrip() throws {
        let snapshot = try QuotaDecoder.decode(fixture())
        XCTAssertFalse(snapshot.isStale(at: snapshot.generatedAt.addingTimeInterval(1799)))
        XCTAssertTrue(snapshot.isStale(at: snapshot.generatedAt.addingTimeInterval(1800)))
        XCTAssertTrue(snapshot.isStale(at: snapshot.generatedAt.addingTimeInterval(-61)))
        XCTAssertEqual(try Snapshot.decode(snapshot.encoded()), snapshot)
        let text = String(decoding: try snapshot.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("accountKeys"))
        XCTAssertFalse(text.contains("plan"))
    }

    func testCachedAndVendorStaleReadingsRemainStale() throws {
        for state: [String: Any] in [
            ["status": "stale", "stale": true],
            ["status": "fresh", "stale": false, "refreshedAt": "2026-10-17T10:00:00Z"]
        ] {
            let snapshot = try modified { json in
                var providers = json["providers"] as! [[String: Any]]
                providers[0]["state"] = state
                json["providers"] = providers
            }
            XCTAssertTrue(snapshot.isStale(at: snapshot.generatedAt))
            XCTAssertEqual(snapshot.rows[0].percentRemaining, 33)
        }
    }

    func testUnsupportedOrMalformedReportsFail() throws {
        XCTAssertThrowsError(try modified { $0["schemaVersion"] = 999 })
        XCTAssertThrowsError(try modified { $0["generatedAt"] = "invalid" })
        XCTAssertThrowsError(try QuotaDecoder.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try Snapshot.decode(Data("{}".utf8)))
    }

    func testMissingWeeklyWindowDoesNotBorrowTheSessionQuota() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var windows = providers[0]["windows"] as! [[String: Any]]
            windows.removeLast()
            providers[0]["windows"] = windows
            json["providers"] = providers
        }
        XCTAssertEqual(snapshot.rows[0].windows[0].percentRemaining, 96)
        XCTAssertNil(snapshot.rows[0].windows[1].percentRemaining)
        XCTAssertEqual(snapshot.rows[0].windows[1].status, "not reported")
    }

    func testExhaustionUsesItsOwnWindowResetEvenWhenAnotherWindowLimitsCurrentPercentage() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var semantics = providers[0]["quotaSemantics"] as! [String: Any]
            var availability = semantics["effectiveAvailability"] as! [[String: Any]]
            availability[0]["limitingWindowIds"] = ["five_hour"]
            semantics["effectiveAvailability"] = availability
            providers[0]["quotaSemantics"] = semantics
            json["providers"] = providers
        }
        let row = snapshot.rows[0]
        XCTAssertEqual(row.limitingWindow, "5h")
        XCTAssertGreaterThan(try XCTUnwrap(row.projectedExhaustedAt), try XCTUnwrap(row.resetsAt))
        XCTAssertTrue(row.runsOutBeforeReset)
        XCTAssertEqual(row.exhaustionResetAt, row.windows[1].resetsAt)
    }

    func testAgyWindowsStayWithinTheirOwnScope() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var windows = providers[2]["windows"] as! [[String: Any]]
            windows[0]["percentRemaining"] = 17
            windows[3]["percentRemaining"] = 91
            providers[2]["windows"] = windows
            json["providers"] = providers
        }
        XCTAssertEqual(snapshot.rows[2].windows.map(\.percentRemaining), [17, 86])
        XCTAssertEqual(snapshot.rows[3].windows.map(\.percentRemaining), [91, 100])
    }

    func testUntrustedWindowDoesNotPublishOldPercentages() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            providers[0]["state"] = ["status": "fresh", "stale": false, "untrustedWindowIds": ["five_hour"]]
            json["providers"] = providers
        }
        XCTAssertNil(snapshot.rows[0].windows[0].percentRemaining)
        XCTAssertEqual(snapshot.rows[0].windows[0].status, "unmeasurable")
        XCTAssertEqual(snapshot.rows[0].windows[1].percentRemaining, 33)
    }

    func testInvalidWindowPercentageIsUnmeasurable() throws {
        let snapshot = try modified { json in
            var providers = json["providers"] as! [[String: Any]]
            var windows = providers[0]["windows"] as! [[String: Any]]
            windows[0]["percentRemaining"] = 101
            providers[0]["windows"] = windows
            json["providers"] = providers
        }
        XCTAssertNil(snapshot.rows[0].windows[0].percentRemaining)
        XCTAssertEqual(snapshot.rows[0].windows[0].status, "unmeasurable")
    }

    func testVersionOneSnapshotRemainsReadableUntilRefresh() throws {
        let snapshot = try QuotaDecoder.decode(fixture())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        json["version"] = 1
        var rows = json["rows"] as! [[String: Any]]
        for index in rows.indices {
            rows[index].removeValue(forKey: "windowQuotas")
            rows[index].removeValue(forKey: "runwayStatus")
        }
        json["rows"] = rows
        let previous = try Snapshot.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(previous.rows[0].percentRemaining, 33)
        XCTAssertTrue(previous.rows[0].windows.allSatisfy { $0.percentRemaining == nil && $0.status == "refresh needed" })
    }
}
