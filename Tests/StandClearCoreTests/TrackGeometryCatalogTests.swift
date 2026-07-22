@testable import StandClearCore
import XCTest

final class TrackGeometryCatalogTests: XCTestCase {
    func testBundledCatalogContainsCompleteNetworkAndSIR() throws {
        let catalog = try TrackGeometryCatalog.bundled()

        XCTAssertGreaterThanOrEqual(catalog.resource.routes.count, 29)
        XCTAssertGreaterThan(catalog.resource.paths.count, 200)
        XCTAssertEqual(catalog.route("A")?.colorHex, "0062CF")
        XCTAssertEqual(catalog.route("SI")?.shortName, "SIR")
        XCTAssertFalse(catalog.paths(forRoute: "SI").isEmpty)
        XCTAssertTrue(catalog.resource.validationWarnings.isEmpty)
    }

    func testBundledPathsHaveSaneCoordinatesAndMonotonicDistances() throws {
        let catalog = try TrackGeometryCatalog.bundled()

        for path in catalog.resource.paths {
            XCTAssertGreaterThanOrEqual(path.points.count, 2, path.shapeID)
            XCTAssertFalse(path.anchors.isEmpty, path.shapeID)
            XCTAssertEqual(path.points.map(\.distanceMeters), path.points.map(\.distanceMeters).sorted(), path.shapeID)
            XCTAssertEqual(path.anchors.map(\.distanceMeters), path.anchors.map(\.distanceMeters).sorted(), path.shapeID)
            XCTAssertTrue(path.points.allSatisfy { (40.45 ... 41.0).contains($0.latitude) }, path.shapeID)
            XCTAssertTrue(path.points.allSatisfy { (-74.30 ... -73.65).contains($0.longitude) }, path.shapeID)
            XCTAssertGreaterThan(path.points.last?.distanceMeters ?? 0, 50, path.shapeID)
        }
    }
}
