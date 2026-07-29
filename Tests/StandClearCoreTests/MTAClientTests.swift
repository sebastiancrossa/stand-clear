import Foundation
@testable import StandClearCore
import XCTest

final class MTAClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.responses = [:]
        super.tearDown()
    }

    func testSystemSnapshotReconcilesVehiclesFiltersUnassignedTripsAndReportsPartialFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let feedTimestamp: UInt64 = 1_799_999_990
        let assignedDescriptor = tripDescriptor(
            tripID: "123400_Q..N",
            routeID: "q",
            startDate: "20270115",
            startTime: "12:34:00",
            isAssigned: true
        )
        let unassignedDescriptor = tripDescriptor(
            tripID: "130000_Q..N",
            routeID: "Q",
            startDate: "20270115",
            startTime: "13:00:00",
            isAssigned: false
        )
        let movingDescriptor = tripDescriptor(
            tripID: "131000_Q..N",
            routeID: "Q",
            startDate: "20270115",
            startTime: "13:10:00",
            isAssigned: false
        )
        let assignedTrip = tripEntity(
            id: "assigned-trip",
            descriptor: assignedDescriptor,
            stopID: "R16N",
            arrival: 1_800_000_120
        )
        let assignedVehicle = vehicleEntity(
            id: "assigned-vehicle",
            descriptor: assignedDescriptor,
            stopID: "R16N",
            timestamp: 1_799_999_980
        )
        let unassignedTrip = tripEntity(
            id: "unassigned-trip",
            descriptor: unassignedDescriptor,
            stopID: "R14N",
            arrival: 1_800_000_240
        )
        let movingTrip = tripEntity(
            id: "moving-trip",
            descriptor: movingDescriptor,
            stopID: "R14N",
            arrival: 1_800_000_360
        )
        let movingVehicle = vehicleEntity(
            id: "moving-vehicle",
            descriptor: movingDescriptor,
            stopID: "R14N",
            timestamp: 1_799_999_985
        )
        let primaryFeed = feed(
            timestamp: feedTimestamp,
            entities: [assignedTrip, assignedVehicle, unassignedTrip, movingTrip, movingVehicle]
        )
        let emptyFeed = feed(timestamp: feedTimestamp, entities: [])

        var responses = Dictionary(
            uniqueKeysWithValues: MTAClient.feedURLs.map { ($0, MockURLProtocol.Response(status: 200, data: emptyFeed)) }
        )
        responses[MTAClient.feedURLs[0]] = .init(status: 200, data: primaryFeed)
        responses[MTAClient.feedURLs[3]] = .init(status: 503, data: Data())
        MockURLProtocol.responses = responses

        let snapshot = try await MTAClient(session: mockSession()).fetchSystemSnapshot(
            catalog: try fixtureCatalog(),
            now: now
        )

        XCTAssertEqual(snapshot.trains.count, 2)
        XCTAssertEqual(Set(snapshot.trains.map(\.id.tripID)), ["123400_Q..N", "131000_Q..N"])
        let assigned = try XCTUnwrap(snapshot.trains.first { $0.id.tripID == "123400_Q..N" })
        XCTAssertEqual(assigned.id.feedID, "gtfs")
        XCTAssertEqual(assigned.id.routeID, "Q")
        XCTAssertEqual(assigned.id.serviceDate, "20270115")
        XCTAssertEqual(assigned.destination, "Times Sq")
        XCTAssertEqual(assigned.vehicle?.status, .stoppedAt)
        XCTAssertEqual(assigned.vehicle?.timestamp?.timeIntervalSince1970, 1_799_999_980)
        XCTAssertEqual(assigned.feedTimestamp?.timeIntervalSince1970, TimeInterval(feedTimestamp))
        XCTAssertEqual(snapshot.arrivals.count, 3, "Unassigned future trips still contribute arrival predictions.")
        XCTAssertEqual(snapshot.failedFeedCount, 1)
        XCTAssertTrue(snapshot.failedRouteIDs.contains("G"))
        XCTAssertEqual(snapshot.feedStatuses.count, MTAClient.feedURLs.count)
    }

    func testTrainRunIDSeparatesServiceDaysAndNormalizesRoutes() {
        let firstDay = TrainRunID(
            feedID: "gtfs-ace",
            routeID: "a",
            tripID: "trip-1",
            serviceDate: "20270115",
            startTime: "25:10:00"
        )
        let nextDay = TrainRunID(
            feedID: "gtfs-ace",
            routeID: "A",
            tripID: "trip-1",
            serviceDate: "20270116",
            startTime: "25:10:00"
        )

        XCTAssertEqual(firstDay.routeID, "A")
        XCTAssertNotEqual(firstDay, nextDay)
        XCTAssertEqual(Set([firstDay, nextDay]).count, 2)
    }

    func testFetchArrivalsRemainsACompatibilityViewOfSystemSnapshot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let descriptor = tripDescriptor(
            tripID: "123400_Q..N",
            routeID: "Q",
            startDate: "20270115",
            startTime: "12:34:00",
            isAssigned: true
        )
        let primaryFeed = feed(
            timestamp: 1_799_999_990,
            entities: [
                tripEntity(
                    id: "trip",
                    descriptor: descriptor,
                    stopID: "R16N",
                    arrival: 1_800_000_120
                ),
            ]
        )
        let emptyFeed = feed(timestamp: 1_799_999_990, entities: [])
        MockURLProtocol.responses = Dictionary(
            uniqueKeysWithValues: MTAClient.feedURLs.map { url in
                (url, MockURLProtocol.Response(status: 200, data: url == MTAClient.feedURLs[0] ? primaryFeed : emptyFeed))
            }
        )
        let client = MTAClient(session: mockSession())
        let catalog = try fixtureCatalog()

        let system = try await client.fetchSystemSnapshot(catalog: catalog, now: now)
        let compatibility = try await client.fetchArrivals(catalog: catalog, now: now)

        XCTAssertEqual(compatibility.arrivals, system.arrivals)
        XCTAssertEqual(compatibility.fetchedAt, system.fetchedAt)
        XCTAssertEqual(compatibility.failedFeedCount, system.failedFeedCount)
        XCTAssertEqual(compatibility.failedRouteIDs, system.failedRouteIDs)
    }

    func testRouteFilterFetchesOnlyMatchingFeedsAndSkipsTrainObservationsWhenDisabled() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let descriptor = tripDescriptor(
            tripID: "123400_Q..N",
            routeID: "Q",
            startDate: "20270115",
            startTime: "12:34:00",
            isAssigned: true
        )
        let nqrwFeed = feed(
            timestamp: 1_799_999_990,
            entities: [
                tripEntity(
                    id: "trip",
                    descriptor: descriptor,
                    stopID: "R16N",
                    arrival: 1_800_000_120
                ),
                vehicleEntity(
                    id: "vehicle",
                    descriptor: descriptor,
                    stopID: "R16N",
                    timestamp: 1_799_999_980
                ),
            ]
        )
        // Only the NQRW feed should be requested. Leave every other URL unset so
        // an accidental fetch would fail the test.
        MockURLProtocol.responses = [
            MTAClient.feedURLs[6]: .init(status: 200, data: nqrwFeed),
        ]

        let snapshot = try await MTAClient(session: mockSession()).fetchSystemSnapshot(
            catalog: try fixtureCatalog(),
            now: now,
            routeIDs: ["Q"],
            includeTrains: false
        )

        XCTAssertEqual(snapshot.feedStatuses.map(\.feedID), ["gtfs-nqrw"])
        XCTAssertEqual(snapshot.arrivals.count, 1)
        XCTAssertEqual(snapshot.arrivals.first?.routeID, "Q")
        XCTAssertTrue(snapshot.trains.isEmpty)
    }

    func testEmptyRouteFilterReturnsWithoutFetching() async throws {
        MockURLProtocol.responses = [:]
        let snapshot = try await MTAClient(session: mockSession()).fetchSystemSnapshot(
            catalog: try fixtureCatalog(),
            now: Date(),
            routeIDs: [],
            includeTrains: false
        )
        XCTAssertTrue(snapshot.arrivals.isEmpty)
        XCTAssertTrue(snapshot.trains.isEmpty)
        XCTAssertTrue(snapshot.feedStatuses.isEmpty)
    }

    func testAllMalformedFeedsReportUnavailable() async throws {
        MockURLProtocol.responses = Dictionary(
            uniqueKeysWithValues: MTAClient.feedURLs.map { url in
                (url, MockURLProtocol.Response(status: 200, data: Data([0x80])))
            }
        )

        do {
            _ = try await MTAClient(session: mockSession()).fetchSystemSnapshot(
                catalog: try fixtureCatalog()
            )
            XCTFail("Expected malformed feeds to be treated as failed.")
        } catch MTAFeedError.allFeedsFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func fixtureCatalog() throws -> StationCatalog {
        try StationCatalog(csv: """
        stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
        R16,Times Sq,40.0,-73.0,1,
        R16N,Times Sq,40.0,-73.0,,R16
        R14,Union Sq,40.1,-73.1,1,
        R14N,Union Sq,40.1,-73.1,,R14
        """)
    }

    private func mockSession() -> URLSession {
        MockURLProtocol.session()
    }
}

private func tripDescriptor(
    tripID: String,
    routeID: String,
    startDate: String,
    startTime: String,
    isAssigned: Bool
) -> [UInt8] {
    message([
        stringField(1, tripID),
        stringField(2, startTime),
        stringField(3, startDate),
        stringField(5, routeID),
        varintField(6, 0),
        messageField(1001, message([
            stringField(1, "train-\(tripID)"),
            varintField(2, isAssigned ? 1 : 0),
            varintField(3, 1),
        ])),
    ])
}

private func tripEntity(
    id: String,
    descriptor: [UInt8],
    stopID: String,
    arrival: UInt64
) -> [UInt8] {
    let stop = message([
        varintField(1, 1),
        messageField(2, message([varintField(2, arrival)])),
        stringField(4, stopID),
    ])
    return message([
        stringField(1, id),
        messageField(3, message([
            messageField(1, descriptor),
            messageField(2, stop),
        ])),
    ])
}

private func vehicleEntity(
    id: String,
    descriptor: [UInt8],
    stopID: String,
    timestamp: UInt64
) -> [UInt8] {
    message([
        stringField(1, id),
        messageField(4, message([
            messageField(1, descriptor),
            varintField(3, 1),
            varintField(4, 1),
            varintField(5, timestamp),
            stringField(7, stopID),
        ])),
    ])
}

private func feed(timestamp: UInt64, entities: [[UInt8]]) -> Data {
    Data(message([
        messageField(1, message([
            stringField(1, "2.0"),
            varintField(3, timestamp),
        ])),
    ] + entities.map { messageField(2, $0) }))
}
