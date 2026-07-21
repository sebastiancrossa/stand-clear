import CoreLocation
@testable import SubwayBarCore
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

        XCTAssertGreaterThan(catalog.stations.count, 450)
        XCTAssertNotNil(catalog.station(id: "127"))
    }
}

