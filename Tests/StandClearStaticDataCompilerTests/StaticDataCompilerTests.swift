import Foundation
@testable import StandClearStaticDataCompiler
@testable import StandClearCore
import XCTest

final class StaticDataCompilerTests: XCTestCase {
    private let input = StaticGTFSInput(
        routesCSV: """
        route_id,agency_id,route_short_name,route_long_name,route_desc,route_type,route_url,route_color,route_text_color,route_sort_order
        A,MTA NYCT,A,Alpha Express,,1,,0039A6,FFFFFF,1
        SI,MTA NYCT,SIR,Staten Island Railway,,2,,08179C,FFFFFF,2
        """,
        tripsCSV: """
        route_id,trip_id,service_id,trip_headsign,direction_id,shape_id
        A,trip-a-1,WKD,Downtown,1,A.shape
        A,trip-a-2,WKD,Downtown,1,A.shape
        SI,trip-si,WKD,Tottenville,1,SI.shape
        """,
        stopTimesCSV: """
        trip_id,stop_id,arrival_time,departure_time,stop_sequence
        trip-a-1,A1N,08:00:00,08:00:30,1
        trip-a-1,A2N,08:02:30,08:02:45,2
        trip-a-2,A1N,09:00:00,09:00:10,1
        trip-a-2,A2N,09:03:10,09:03:20,2
        trip-si,S1S,10:00:00,10:00:20,1
        trip-si,S2S,10:04:20,10:04:40,2
        """,
        stopsCSV: """
        stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
        A1,Alpha,40.000000,-74.000000,1,
        A1N,Alpha,40.000000,-74.000000,0,A1
        A2,Beta,40.010000,-74.010000,1,
        A2N,Beta,40.010000,-74.010000,0,A2
        S1,St George,40.643700,-74.073600,1,
        S1S,St George,40.643700,-74.073600,0,S1
        S2,Tompkinsville,40.636900,-74.074800,1,
        S2S,Tompkinsville,40.636900,-74.074800,0,S2
        """,
        transfersCSV: """
        from_stop_id,to_stop_id,transfer_type,min_transfer_time
        A1,A2,2,0
        """,
        shapesCSV: """
        shape_id,shape_pt_sequence,shape_pt_lat,shape_pt_lon
        A.shape,0,40.000000,-74.000000
        A.shape,1,40.005000,-74.005000
        A.shape,2,40.010000,-74.010000
        SI.shape,0,40.643700,-74.073600
        SI.shape,1,40.640000,-74.074200
        SI.shape,2,40.636900,-74.074800
        """,
        feedInfoCSV: """
        feed_publisher_name,feed_publisher_url,feed_lang,feed_start_date,feed_end_date,feed_version
        MTA New York City Transit,https://www.mta.info/,EN,20260101,20261231,test-version
        """
    )

    func testCompilationIsDeterministicAndDeduplicatesTripsIntoShapePaths() throws {
        let compiler = StaticGTFSCompiler()
        let first = try compiler.compile(input)
        let second = try compiler.compile(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.paths.count, 2)
        XCTAssertEqual(first.paths.first(where: { $0.shapeID == "A.shape" })?.routeIDs, ["A"])
        XCTAssertEqual(first.feedVersion, "test-version")
        XCTAssertEqual(first.transferGroups, [StationTransferGroup(stationIDs: ["A1", "A2"])])
    }

    func testAnchorsAreMonotonicAndContainMedianTimings() throws {
        let resource = try StaticGTFSCompiler().compile(input)
        let path = try XCTUnwrap(resource.paths.first { $0.shapeID == "A.shape" })

        XCTAssertEqual(path.anchors.map(\.stationID), ["A1", "A2"])
        XCTAssertEqual(path.anchors.map(\.distanceMeters), path.anchors.map(\.distanceMeters).sorted())
        XCTAssertEqual(path.anchors[0].medianDwellSeconds, 20)
        XCTAssertEqual(path.anchors[0].medianTravelSecondsToNext, 150)
        XCTAssertGreaterThan(path.points.last?.distanceMeters ?? 0, 1_000)
    }

    func testCorridorsPreserveSharedMiddleStationSegmentAcrossDifferentShapes() throws {
        let sharedInput = StaticGTFSInput(
            routesCSV: input.routesCSV + "\n        B,MTA NYCT,B,Bravo Local,,1,,FF6319,FFFFFF,3",
            tripsCSV: input.tripsCSV + "\n        B,trip-b,WKD,Bravo,1,B.shape",
            stopTimesCSV: input.stopTimesCSV + "\n        trip-b,A0N,10:00:00,10:00:20,1\n        trip-b,A1N,10:02:00,10:02:20,2\n        trip-b,A2N,10:04:00,10:04:20,3\n        trip-b,B3N,10:06:00,10:06:20,4",
            stopsCSV: input.stopsCSV + "\n        A0,Approach,39.990000,-74.010000,1,\n        A0N,Approach,39.990000,-74.010000,0,A0\n        B3,Branch,40.020000,-74.000000,1,\n        B3N,Branch,40.020000,-74.000000,0,B3",
            transfersCSV: input.transfersCSV,
            shapesCSV: input.shapesCSV + "\n        B.shape,0,39.990000,-74.010000\n        B.shape,1,40.000000,-74.000000\n        B.shape,2,40.005000,-74.005000\n        B.shape,3,40.010000,-74.010000\n        B.shape,4,40.020000,-74.000000",
            feedInfoCSV: input.feedInfoCSV
        )

        let resource = try StaticGTFSCompiler().compile(sharedInput)
        let sharedCorridor = try XCTUnwrap(resource.corridors.first { corridor in
            corridor.routeIDs == ["A", "B"]
        })
        XCTAssertEqual(sharedCorridor.points.map(\.latitude), [40.0, 40.005, 40.01])
        XCTAssertEqual(sharedCorridor.points.map(\.longitude), [-74.0, -74.005, -74.01])
        XCTAssertEqual(Set(sharedCorridor.shapeIDs), Set(["A.shape", "B.shape"]))
    }

    func testCompilerRejectsADeclaredRouteWithoutGeometry() {
        let broken = StaticGTFSInput(
            routesCSV: input.routesCSV + "\nQ,MTA NYCT,Q,Missing,,1,,FCCC0A,000000,3",
            tripsCSV: input.tripsCSV,
            stopTimesCSV: input.stopTimesCSV,
            stopsCSV: input.stopsCSV,
            transfersCSV: input.transfersCSV,
            shapesCSV: input.shapesCSV,
            feedInfoCSV: input.feedInfoCSV
        )

        XCTAssertThrowsError(try StaticGTFSCompiler().compile(broken)) { error in
            XCTAssertEqual(error as? StaticGTFSCompilerError, .routesWithoutGeometry(["Q"]))
        }
    }

    func testCompilerRejectsMissingRequiredColumns() {
        let broken = StaticGTFSInput(
            routesCSV: "route_id,route_short_name\nA,A",
            tripsCSV: input.tripsCSV,
            stopTimesCSV: input.stopTimesCSV,
            stopsCSV: input.stopsCSV,
            transfersCSV: input.transfersCSV,
            shapesCSV: input.shapesCSV
        )

        XCTAssertThrowsError(try StaticGTFSCompiler().compile(broken)) { error in
            XCTAssertEqual(
                error as? StaticGTFSCompilerError,
                .invalidCSV(
                    file: "routes.txt",
                    missingColumns: ["route_long_name", "route_color", "route_text_color"]
                )
            )
        }
    }

    func testEncodedResourceLoadsThroughRuntimeCatalogIncludingSIR() throws {
        let resource = try StaticGTFSCompiler().compile(input)
        let data = try StaticGTFSCompiler.encode(resource)
        let catalog = try TrackGeometryCatalog(data: data)

        XCTAssertEqual(catalog.route("A")?.colorHex, "0039A6")
        XCTAssertEqual(catalog.route("SI")?.shortName, "SIR")
        XCTAssertEqual(catalog.paths(forRoute: "SI").map(\.shapeID), ["SI.shape"])
        XCTAssertEqual(catalog.path(shapeID: "A.shape")?.points.count, 3)
    }
}
