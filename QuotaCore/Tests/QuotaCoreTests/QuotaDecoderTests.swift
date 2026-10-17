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
    }

    func testMissingProvidersStayVisibleWithoutInventedPercentages() throws {
        let snapshot = try modified { $0["providers"] = [] }
        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.percentRemaining == nil && $0.status == "not reported" })
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
}
