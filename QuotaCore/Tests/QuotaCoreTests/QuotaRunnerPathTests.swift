import XCTest
@testable import QuotaCore

final class QuotaRunnerPathTests: XCTestCase {
    func testUserLocalBinLeadsTheFixedPath() {
        XCTAssertEqual(QuotaRunnerPath.make(home: "/Users/tester"),
                       "/Users/tester/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    func testSystemAndHomebrewEntriesAreKeptAfterTheUserBin() {
        let path = QuotaRunnerPath.make(home: "/Users/tester")
        let entries = path.split(separator: ":")
        XCTAssertEqual(entries.first, "/Users/tester/.local/bin")
        XCTAssertEqual(entries.dropFirst().joined(separator: ":"),
                       "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}
