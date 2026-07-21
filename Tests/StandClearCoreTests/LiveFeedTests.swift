@testable import StandClearCore
import XCTest

final class LiveFeedTests: XCTestCase {
    func testOfficialMTAFeedsProduceMappedArrivals() async throws {
        guard ProcessInfo.processInfo.environment["STAND_CLEAR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set STAND_CLEAR_LIVE_TEST=1 to call the live MTA feeds.")
        }

        let catalog = try StationCatalog.bundled()
        let snapshot = try await MTAClient().fetchArrivals(catalog: catalog)

        XCTAssertGreaterThan(snapshot.arrivals.count, 100)
        XCTAssertEqual(snapshot.failedFeedCount, 0)
        XCTAssertTrue(snapshot.arrivals.contains { $0.routeID == "7" })
        XCTAssertTrue(snapshot.arrivals.allSatisfy { catalog.station(id: $0.stationID) != nil })
    }
}
