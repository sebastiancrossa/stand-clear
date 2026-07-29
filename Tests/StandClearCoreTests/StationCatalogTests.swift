import CoreLocation
@testable import StandClearCore
import XCTest

final class StationCatalogTests: XCTestCase {
    private let fixture = """
    stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
    A1,"Alpha, Station",40.0000,-73.0000,1,
    A1N,"Alpha, Station",40.0000,-73.0000,,A1
    A1S,"Alpha, Station",40.0000,-73.0000,,A1
    B2,Beta Station,41.0000,-74.0000,1,
    B2N,Beta Station,41.0000,-74.0000,,B2
    """

    func testNearestStationUsesParentStationsAndCoordinates() throws {
        let catalog = try StationCatalog(csv: fixture)
        let result = try XCTUnwrap(
            catalog.nearest(to: CLLocation(latitude: 40.0001, longitude: -73.0001))
        )

        XCTAssertEqual(result.station.id, "A1")
        XCTAssertEqual(result.station.name, "Alpha, Station")
        XCTAssertLessThan(result.distance, 20)
    }

    func testPlatformStopResolvesToItsParentStation() throws {
        let catalog = try StationCatalog(csv: fixture)

        XCTAssertEqual(catalog.stationID(forStopID: "A1N"), "A1")
        XCTAssertEqual(catalog.stationName(forStopID: "A1S"), "Alpha, Station")
    }

    func testBundledCatalogContainsTheFullSubwayNetwork() throws {
        let catalog = try StationCatalog.bundled()
        let expectedRoutes: Set<String> = [
            "A", "C", "E", "B", "D", "F", "M", "G", "L", "J",
            "N", "Q", "R", "W", "1", "2", "3", "4", "5", "6", "6X",
            "7", "7X", "H", "FS", "GS",
        ]

        XCTAssertGreaterThan(catalog.stations.count, 450)
        XCTAssertNotNil(catalog.station(id: "127"))
        XCTAssertTrue(catalog.relatedStations(to: "R16").contains("127"))
        XCTAssertTrue(catalog.relatedStations(to: "R16").contains("A27"))
        XCTAssertTrue(catalog.routes(serving: "R16").isSuperset(of: ["1", "2", "3", "7", "A", "C", "E", "N", "Q", "R", "W"]))
        XCTAssertTrue(catalog.allRoutes.isSuperset(of: expectedRoutes))
    }

    func testNearestStationsFiltersByRouteOrdersByDistanceAndCapsCount() throws {
        let catalog = try StationCatalog(
            csv: multiStationFixture,
            stationRoutesCSV: multiStationRoutes,
            transfersCSV: multiStationTransfers
        )
        let location = CLLocation(latitude: 40.0000, longitude: -73.0000)

        let result = catalog.nearestStations(to: location, count: 2, servingAnyOf: ["Q"])

        XCTAssertEqual(result.map(\.station.id), ["A1", "C3"])
        XCTAssertLessThan(result[0].distance, result[1].distance)
    }

    func testNearestStationsDedupesTransferComplexToNearestMember() throws {
        let catalog = try StationCatalog(
            csv: multiStationFixture,
            stationRoutesCSV: multiStationRoutes,
            transfersCSV: multiStationTransfers
        )
        let location = CLLocation(latitude: 40.0000, longitude: -73.0000)

        let result = catalog.nearestStations(to: location, count: 5, servingAnyOf: ["Q", "N"])

        XCTAssertEqual(result.map(\.station.id), ["A1", "B2", "C3"])
        XCTAssertFalse(result.map(\.station.id).contains("A1b"))
    }

    func testNearestStationsReturnsEmptyForEmptyRoutesOrZeroCount() throws {
        let catalog = try StationCatalog(
            csv: multiStationFixture,
            stationRoutesCSV: multiStationRoutes,
            transfersCSV: multiStationTransfers
        )
        let location = CLLocation(latitude: 40.0000, longitude: -73.0000)

        XCTAssertTrue(catalog.nearestStations(to: location, count: 5, servingAnyOf: []).isEmpty)
        XCTAssertTrue(catalog.nearestStations(to: location, count: 0, servingAnyOf: ["Q"]).isEmpty)
        XCTAssertTrue(catalog.nearestStations(to: location, count: 5, servingAnyOf: ["G"]).isEmpty)
    }

    private let multiStationFixture = """
    stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
    A1,Alpha Station,40.0000,-73.0000,1,
    A1b,Alpha Annex,40.0002,-73.0002,1,
    B2,Beta Station,40.0100,-73.0000,1,
    C3,Gamma Station,40.0200,-73.0000,1,
    """

    private let multiStationRoutes = """
    station_id,route_id
    A1,Q
    A1b,N
    B2,N
    C3,Q
    """

    private let multiStationTransfers = """
    from_stop_id,to_stop_id,transfer_type,min_transfer_time
    A1,A1b,2,180
    """
}
