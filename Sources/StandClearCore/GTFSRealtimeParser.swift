import Foundation

enum ProtobufError: Error {
    case malformedVarint
    case truncatedMessage
    case unsupportedWireType(Int)
}

private struct ProtobufReader {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func readKey() throws -> (field: Int, wire: Int) {
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x07))
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw ProtobufError.malformedVarint
    }

    mutating func readLengthDelimited() throws -> [UInt8] {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else {
            throw ProtobufError.truncatedMessage
        }
        let value = Array(bytes[index ..< index + length])
        index += length
        return value
    }

    mutating func readString() throws -> String {
        String(decoding: try readLengthDelimited(), as: UTF8.self)
    }

    mutating func skip(wire: Int) throws {
        switch wire {
        case 0:
            _ = try readVarint()
        case 1:
            try advance(by: 8)
        case 2:
            _ = try readLengthDelimited()
        case 5:
            try advance(by: 4)
        default:
            throw ProtobufError.unsupportedWireType(wire)
        }
    }

    private mutating func advance(by count: Int) throws {
        guard index + count <= bytes.count else {
            throw ProtobufError.truncatedMessage
        }
        index += count
    }
}

struct RealtimeStopEvent: Sendable {
    let stopID: String
    let time: Date?
    let isSkipped: Bool
}

struct RealtimeTrip: Sendable {
    let tripID: String
    let routeID: String
    let directionID: Int?
    let stops: [RealtimeStopEvent]
}

public enum GTFSRealtimeParser {
    static func parse(data: Data) throws -> [RealtimeTrip] {
        var reader = ProtobufReader(data: data)
        var trips: [RealtimeTrip] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.field == 2, key.wire == 2 {
                if let trip = try parseEntity(bytes: reader.readLengthDelimited()) {
                    trips.append(trip)
                }
            } else {
                try reader.skip(wire: key.wire)
            }
        }
        return trips
    }

    private static func parseEntity(bytes: [UInt8]) throws -> RealtimeTrip? {
        var reader = ProtobufReader(bytes: bytes)
        var isDeleted = false
        var trip: RealtimeTrip?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (2, 0): isDeleted = try reader.readVarint() != 0
            case (3, 2): trip = try parseTripUpdate(bytes: reader.readLengthDelimited())
            default: try reader.skip(wire: key.wire)
            }
        }
        return isDeleted ? nil : trip
    }

    private static func parseTripUpdate(bytes: [UInt8]) throws -> RealtimeTrip? {
        var reader = ProtobufReader(bytes: bytes)
        var tripID = ""
        var routeID = ""
        var directionID: Int?
        var stops: [RealtimeStopEvent] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, 2):
                (tripID, routeID, directionID) = try parseTripDescriptor(bytes: reader.readLengthDelimited())
            case (2, 2):
                if let stop = try parseStopTimeUpdate(bytes: reader.readLengthDelimited()) {
                    stops.append(stop)
                }
            default:
                try reader.skip(wire: key.wire)
            }
        }

        guard !routeID.isEmpty, !stops.isEmpty else { return nil }
        return RealtimeTrip(tripID: tripID, routeID: routeID, directionID: directionID, stops: stops)
    }

    private static func parseTripDescriptor(bytes: [UInt8]) throws -> (String, String, Int?) {
        var reader = ProtobufReader(bytes: bytes)
        var tripID = ""
        var routeID = ""
        var directionID: Int?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, 2): tripID = try reader.readString()
            case (5, 2): routeID = try reader.readString()
            case (6, 0): directionID = Int(try reader.readVarint())
            default: try reader.skip(wire: key.wire)
            }
        }
        return (tripID, routeID, directionID)
    }

    private static func parseStopTimeUpdate(bytes: [UInt8]) throws -> RealtimeStopEvent? {
        var reader = ProtobufReader(bytes: bytes)
        var stopID = ""
        var arrivalTime: Date?
        var departureTime: Date?
        var scheduleRelationship = 0

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (2, 2): arrivalTime = try parseStopTimeEvent(bytes: reader.readLengthDelimited())
            case (3, 2): departureTime = try parseStopTimeEvent(bytes: reader.readLengthDelimited())
            case (4, 2): stopID = try reader.readString()
            case (5, 0): scheduleRelationship = Int(try reader.readVarint())
            default: try reader.skip(wire: key.wire)
            }
        }

        guard !stopID.isEmpty else { return nil }
        return RealtimeStopEvent(
            stopID: stopID,
            time: arrivalTime ?? departureTime,
            isSkipped: scheduleRelationship == 1
        )
    }

    private static func parseStopTimeEvent(bytes: [UInt8]) throws -> Date? {
        var reader = ProtobufReader(bytes: bytes)
        var timestamp: UInt64?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.field == 2, key.wire == 0 {
                timestamp = try reader.readVarint()
            } else {
                try reader.skip(wire: key.wire)
            }
        }
        return timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
