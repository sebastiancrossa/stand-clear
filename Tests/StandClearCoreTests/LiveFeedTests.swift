@testable import StandClearCore
import XCTest

final class LiveFeedTests: XCTestCase {
    func testOfficialMTAFeedsProduceMappedArrivals() async throws {
        guard ProcessInfo.processInfo.environment["STAND_CLEAR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set STAND_CLEAR_LIVE_TEST=1 to call the live MTA feeds.")
        }

        let catalog = try StationCatalog.bundled()
        let snapshot = try await MTAClient().fetchSystemSnapshot(catalog: catalog)

        XCTAssertGreaterThan(snapshot.arrivals.count, 100)
        XCTAssertEqual(snapshot.failedFeedCount, 0)
        XCTAssertTrue(snapshot.failedRouteIDs.isEmpty)
        XCTAssertTrue(snapshot.arrivals.contains { $0.routeID == "7" })
        XCTAssertTrue(snapshot.arrivals.allSatisfy { catalog.station(id: $0.stationID) != nil })
        XCTAssertFalse(snapshot.trains.isEmpty)
        XCTAssertEqual(Set(snapshot.trains.map(\.id)).count, snapshot.trains.count)
        XCTAssertTrue(snapshot.trains.allSatisfy { $0.isAssigned || $0.vehicle != nil })
        XCTAssertTrue(snapshot.trains.contains { !$0.stops.isEmpty })
        XCTAssertTrue(snapshot.feedStatuses.allSatisfy { $0.feedTimestamp != nil })
    }
}
