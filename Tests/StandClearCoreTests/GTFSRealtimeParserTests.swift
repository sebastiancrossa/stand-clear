import Foundation
@testable import StandClearCore
import XCTest

final class GTFSRealtimeParserTests: XCTestCase {
    func testParserPreservesFeedTimestampAndDeletedEntityID() throws {
        let timestamp: UInt64 = 1_800_000_000
        let header = message([
            stringField(1, "2.0"),
            varintField(3, timestamp),
        ])
        let entity = message([
            stringField(1, "deleted-entity"),
            varintField(2, 1),
        ])
        let feed = message([
            messageField(1, header),
            messageField(2, entity),
        ])

        let parsed = try GTFSRealtimeParser.parse(data: Data(feed))

        XCTAssertEqual(parsed.timestamp?.timeIntervalSince1970, TimeInterval(timestamp))
        XCTAssertEqual(parsed.entities.first?.id, "deleted-entity")
        XCTAssertEqual(parsed.entities.first?.isDeleted, true)
    }

    func testParserReadsTripRouteStopAndArrivalTime() throws {
        let timestamp: UInt64 = 1_800_000_120
        let descriptor = message([
            stringField(1, "trip-1"),
            stringField(5, "Q"),
        ])
        let arrivalEvent = message([varintField(2, timestamp)])
        let stopUpdate = message([
            messageField(2, arrivalEvent),
            stringField(4, "R16S"),
        ])
        let tripUpdate = message([
            messageField(1, descriptor),
            messageField(2, stopUpdate),
        ])
        let entity = message([
            stringField(1, "entity-1"),
            messageField(3, tripUpdate),
        ])
        let feed = message([
            messageField(1, message([stringField(1, "2.0")])),
            messageField(2, entity),
        ])

        let trips = try GTFSRealtimeParser.parse(data: Data(feed)).tripUpdates
        let trip = try XCTUnwrap(trips.first)
        let stop = try XCTUnwrap(trip.stops.first)

        XCTAssertEqual(trip.tripID, "trip-1")
        XCTAssertEqual(trip.routeID, "Q")
        XCTAssertEqual(stop.stopID, "R16S")
        XCTAssertEqual(stop.time?.timeIntervalSince1970, TimeInterval(timestamp))
    }

    func testDeletedEntitiesAreIgnored() throws {
        let entity = message([
            stringField(1, "entity-1"),
            varintField(2, 1),
        ])
        let feed = message([
            messageField(1, message([stringField(1, "2.0")])),
            messageField(2, entity),
        ])

        XCTAssertTrue(try GTFSRealtimeParser.parse(data: Data(feed)).tripUpdates.isEmpty)
    }

    func testParserReadsTripVehicleAndNYCTFieldsWithoutCollapsingThem() throws {
        let arrivalTimestamp: UInt64 = 1_800_000_120
        let departureTimestamp: UInt64 = 1_800_000_150
        let movementTimestamp: UInt64 = 1_800_000_090
        let nyctDescriptor = message([
            stringField(1, "01 1234 QNS/STL"),
            varintField(2, 1),
            varintField(3, 1),
        ])
        let descriptor = message([
            stringField(1, "123400_Q..N"),
            stringField(2, "12:34:00"),
            stringField(3, "20270115"),
            stringField(5, "q"),
            varintField(6, 1),
            messageField(1001, nyctDescriptor),
        ])
        let tracks = message([
            stringField(1, "4"),
            stringField(2, "3"),
        ])
        let stopUpdate = message([
            varintField(1, 12),
            messageField(2, message([varintField(2, arrivalTimestamp)])),
            messageField(3, message([varintField(2, departureTimestamp)])),
            stringField(4, "R16N"),
            messageField(1001, tracks),
        ])
        let skippedStop = message([
            varintField(1, 13),
            stringField(4, "R14N"),
            varintField(5, 1),
        ])
        let tripEntity = message([
            stringField(1, "trip-entity"),
            messageField(3, message([
                messageField(1, descriptor),
                messageField(2, stopUpdate),
                messageField(2, skippedStop),
            ])),
        ])
        let vehicleEntity = message([
            stringField(1, "vehicle-entity"),
            messageField(4, message([
                messageField(1, descriptor),
                varintField(3, 12),
                varintField(4, 1),
                varintField(5, movementTimestamp),
                stringField(7, "R16N"),
            ])),
        ])
        let feed = message([
            messageField(1, message([stringField(1, "2.0")])),
            messageField(2, tripEntity),
            messageField(2, vehicleEntity),
        ])

        let parsed = try GTFSRealtimeParser.parse(data: Data(feed))
        let trip = try XCTUnwrap(parsed.entities.first { $0.id == "trip-entity" }?.tripUpdate)
        let vehicle = try XCTUnwrap(parsed.entities.first { $0.id == "vehicle-entity" }?.vehiclePosition)
        let firstStop = try XCTUnwrap(trip.stops.first)

        XCTAssertEqual(trip.tripID, "123400_Q..N")
        XCTAssertEqual(trip.routeID, "q")
        XCTAssertEqual(trip.startDate, "20270115")
        XCTAssertEqual(trip.startTime, "12:34:00")
        XCTAssertEqual(trip.directionID, 1)
        XCTAssertEqual(trip.nyctTrainID, "01 1234 QNS/STL")
        XCTAssertEqual(trip.isAssigned, true)
        XCTAssertEqual(trip.nyctDirection, .northbound)
        XCTAssertEqual(firstStop.stopSequence, 12)
        XCTAssertEqual(firstStop.arrivalTime?.timeIntervalSince1970, TimeInterval(arrivalTimestamp))
        XCTAssertEqual(firstStop.departureTime?.timeIntervalSince1970, TimeInterval(departureTimestamp))
        XCTAssertEqual(firstStop.scheduledTrack, "4")
        XCTAssertEqual(firstStop.actualTrack, "3")
        XCTAssertTrue(trip.stops[1].isSkipped)
        XCTAssertEqual(vehicle.tripID, trip.tripID)
        XCTAssertEqual(vehicle.stopID, "R16N")
        XCTAssertEqual(vehicle.stopSequence, 12)
        XCTAssertEqual(vehicle.status, .stoppedAt)
        XCTAssertEqual(vehicle.timestamp?.timeIntervalSince1970, TimeInterval(movementTimestamp))
    }

    func testMalformedFeedThrows() {
        XCTAssertThrowsError(try GTFSRealtimeParser.parse(data: Data([0x80])))
    }

}
