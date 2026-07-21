import Foundation
@testable import SubwayBarCore
import XCTest

final class GTFSRealtimeParserTests: XCTestCase {
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
        let feed = message([messageField(2, entity)])

        let trips = try GTFSRealtimeParser.parse(data: Data(feed))
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
        let feed = message([messageField(2, entity)])

        XCTAssertTrue(try GTFSRealtimeParser.parse(data: Data(feed)).isEmpty)
    }

    private func message(_ fields: [[UInt8]]) -> [UInt8] {
        fields.flatMap { $0 }
    }

    private func stringField(_ number: UInt64, _ value: String) -> [UInt8] {
        lengthDelimitedField(number, Array(value.utf8))
    }

    private func messageField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
        lengthDelimitedField(number, value)
    }

    private func lengthDelimitedField(_ number: UInt64, _ value: [UInt8]) -> [UInt8] {
        varint((number << 3) | 2) + varint(UInt64(value.count)) + value
    }

    private func varintField(_ number: UInt64, _ value: UInt64) -> [UInt8] {
        varint(number << 3) + varint(value)
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }
}
