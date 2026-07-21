@testable import SubwayBarCore
import XCTest

final class ArrivalBoardTests: XCTestCase {
    func testETAUsesFlooredMinutesAndMinutesSecondsCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let futureArrival = makeArrival(
            id: "future-q",
            route: "Q",
            station: "R16",
            time: now.addingTimeInterval(264.9)
        )
        let pastArrival = makeArrival(
            id: "past-q",
            route: "Q",
            station: "R16",
            time: now.addingTimeInterval(-5)
        )

        XCTAssertEqual(futureArrival.etaText(relativeTo: now), "4 min")
        XCTAssertEqual(futureArrival.etaMinutesSecondsText(relativeTo: now), "4:24")
        XCTAssertEqual(pastArrival.etaText(relativeTo: now), "0 min")
        XCTAssertEqual(pastArrival.etaMinutesSecondsText(relativeTo: now), "0:00")
    }

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

    func testNoSelectedDirectionsProducesAnEmptyBoard() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrival = makeArrival(id: "q", route: "Q", station: "R16", time: now.addingTimeInterval(60))

        XCTAssertTrue(
            ArrivalBoard.arrivals(
                from: [arrival],
                at: "R16",
                selectedRoutes: ["Q"],
                selectedDirections: [],
                now: now
            ).isEmpty
        )
    }

    func testBoardFiltersBySelectedDirection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrivals = [
            makeArrival(
                id: "uptown-q",
                route: "Q",
                station: "R16",
                direction: .northbound,
                time: now.addingTimeInterval(60)
            ),
            makeArrival(
                id: "downtown-q",
                route: "Q",
                station: "R16",
                direction: .southbound,
                time: now.addingTimeInterval(90)
            ),
        ]

        let result = ArrivalBoard.arrivals(
            from: arrivals,
            at: "R16",
            selectedRoutes: ["Q"],
            selectedDirections: [.southbound],
            now: now
        )

        XCTAssertEqual(result.map(\.id), ["downtown-q"])
    }

    func testExpressAndShuttleRouteIDsKeepTheirIdentity() {
        XCTAssertEqual(RouteID.normalized("6x"), "6X")
        XCTAssertEqual(RouteID.displayLabel("6X"), "6")
        XCTAssertTrue(RouteID.isExpress("6X"))
        XCTAssertEqual(RouteID.displayLabel("H"), "SR")
        XCTAssertEqual(RouteID.displayLabel("FS"), "SF")
        XCTAssertEqual(RouteID.displayLabel("GS"), "S")
    }

    func testRoutesAreGroupedInSubwayMapOrder() {
        let routes = [
            "A", "C", "E", "B", "D", "F", "M", "G", "L", "J", "Z",
            "N", "Q", "R", "W", "1", "2", "3", "4", "5", "6", "6X",
            "7", "7X", "H", "FS", "GS",
        ]

        XCTAssertEqual(
            RouteID.grouped(routes),
            [
                ["A", "C", "E"],
                ["B", "D", "F", "M"],
                ["G"],
                ["L"],
                ["J", "Z"],
                ["N", "Q", "R", "W"],
                ["1", "2", "3"],
                ["4", "5", "6", "6X"],
                ["7", "7X"],
                ["H", "FS", "GS"],
            ]
        )
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

    private func makeArrival(
        id: String,
        route: String,
        station: String,
        direction: TravelDirection = .northbound,
        time: Date
    ) -> Arrival {
        Arrival(
            id: id,
            routeID: route,
            stationID: station,
            stopID: "\(station)N",
            direction: direction,
            destination: "Test Terminal",
            arrivalTime: time
        )
    }
}
