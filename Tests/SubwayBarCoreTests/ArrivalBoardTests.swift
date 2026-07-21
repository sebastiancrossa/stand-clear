@testable import SubwayBarCore
import XCTest

final class ArrivalBoardTests: XCTestCase {
    func testBoardFiltersByStationAndSelectedRoutesThenSortsByTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrivals = [
            makeArrival(id: "later-q", route: "Q", station: "R16", time: now.addingTimeInterval(600)),
            makeArrival(id: "other-station", route: "Q", station: "R17", time: now.addingTimeInterval(60)),
            makeArrival(id: "other-route", route: "N", station: "R16", time: now.addingTimeInterval(90)),
            makeArrival(id: "next-q", route: "Q", station: "R16", time: now.addingTimeInterval(120)),
        ]

        let result = ArrivalBoard.arrivals(
            from: arrivals,
            at: "R16",
            selectedRoutes: ["Q"],
            now: now
        )

        XCTAssertEqual(result.map(\.id), ["next-q", "later-q"])
    }

    func testNoSelectedRoutesProducesAnEmptyBoard() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrival = makeArrival(id: "q", route: "Q", station: "R16", time: now.addingTimeInterval(60))

        XCTAssertTrue(
            ArrivalBoard.arrivals(
                from: [arrival],
                at: "R16",
                selectedRoutes: [],
                now: now
            ).isEmpty
        )
    }

    func testExpressRouteIDsAreNormalized() {
        XCTAssertEqual(RouteID.normalized("6X"), "6")
        XCTAssertEqual(RouteID.normalized("GS"), "S")
    }

    private func makeArrival(id: String, route: String, station: String, time: Date) -> Arrival {
        Arrival(
            id: id,
            routeID: route,
            stationID: station,
            stopID: "\(station)N",
            direction: .northbound,
            destination: "Test Terminal",
            arrivalTime: time
        )
    }
}

