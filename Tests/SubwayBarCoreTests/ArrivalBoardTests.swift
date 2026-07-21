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

    func testExpressAndShuttleRouteIDsKeepTheirIdentity() {
        XCTAssertEqual(RouteID.normalized("6x"), "6X")
        XCTAssertEqual(RouteID.displayLabel("6X"), "6")
        XCTAssertTrue(RouteID.isExpress("6X"))
        XCTAssertEqual(RouteID.displayLabel("H"), "SR")
        XCTAssertEqual(RouteID.displayLabel("FS"), "SF")
        XCTAssertEqual(RouteID.displayLabel("GS"), "S")
    }

    func testBoardCanIncludeAllPlatformsInAStationComplex() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrivals = [
            makeArrival(id: "q", route: "Q", station: "R16", time: now.addingTimeInterval(60)),
            makeArrival(id: "seven", route: "7", station: "725", time: now.addingTimeInterval(90)),
        ]

        let result = ArrivalBoard.arrivals(
            from: arrivals,
            atAny: ["R16", "725"],
            selectedRoutes: ["Q", "7"],
            now: now
        )

        XCTAssertEqual(result.map(\.id), ["q", "seven"])
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
