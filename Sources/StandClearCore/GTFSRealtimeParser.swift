import Foundation

struct ParsedRealtimeFeed: Sendable {
    let timestamp: Date?
    let entities: [ParsedRealtimeEntity]

    var tripUpdates: [RealtimeTrip] {
        entities.compactMap { entity in
            entity.isDeleted ? nil : entity.tripUpdate
        }
    }
}

struct ParsedRealtimeEntity: Sendable {
    let id: String
    let isDeleted: Bool
    let tripUpdate: RealtimeTrip?
    let vehiclePosition: RealtimeVehiclePosition?
}

struct RealtimeStopEvent: Sendable {
    let stopID: String
    let stopSequence: Int?
    let arrivalTime: Date?
    let departureTime: Date?
    let isSkipped: Bool
    let scheduledTrack: String?
    let actualTrack: String?

    var time: Date? { arrivalTime ?? departureTime }
}

struct RealtimeTrip: Sendable {
    let tripID: String
    let routeID: String
    let startDate: String
    let startTime: String
    let directionID: Int?
    let nyctTrainID: String?
    let isAssigned: Bool?
    let nyctDirection: TravelDirection?
    let timestamp: Date?
    let stops: [RealtimeStopEvent]
}

struct RealtimeVehiclePosition: Sendable {
    let tripID: String
    let routeID: String
    let startDate: String
    let startTime: String
    let directionID: Int?
    let nyctTrainID: String?
    let isAssigned: Bool?
    let nyctDirection: TravelDirection?
    let stopID: String?
    let stopSequence: Int?
    let status: TrainVehicleStatus?
    let timestamp: Date?
}

public enum GTFSRealtimeParser {
    static func parse(data: Data) throws -> ParsedRealtimeFeed {
        let feed = try TransitRealtime_FeedMessage(
            serializedBytes: data,
            extensions: TransitRealtime_Gtfs_u45Realtime_u45Nyct_Extensions
        )

        return ParsedRealtimeFeed(
            timestamp: feed.header.hasTimestamp
                ? Date(timeIntervalSince1970: TimeInterval(feed.header.timestamp))
                : nil,
            entities: feed.entity.map(parseEntity)
        )
    }

    private static func parseEntity(_ entity: TransitRealtime_FeedEntity) -> ParsedRealtimeEntity {
        ParsedRealtimeEntity(
            id: entity.id,
            isDeleted: entity.isDeleted,
            tripUpdate: entity.hasTripUpdate ? parseTripUpdate(entity.tripUpdate) : nil,
            vehiclePosition: entity.hasVehicle ? parseVehiclePosition(entity.vehicle) : nil
        )
    }

    private static func parseTripUpdate(_ update: TransitRealtime_TripUpdate) -> RealtimeTrip? {
        let descriptor = update.trip
        guard !descriptor.routeID.isEmpty else { return nil }

        return RealtimeTrip(
            tripID: descriptor.tripID,
            routeID: descriptor.routeID,
            startDate: descriptor.startDate,
            startTime: descriptor.startTime,
            directionID: descriptor.hasDirectionID ? Int(descriptor.directionID) : nil,
            nyctTrainID: nyctDescriptor(for: descriptor)?.trainID,
            isAssigned: nyctDescriptor(for: descriptor)?.isAssigned,
            nyctDirection: nyctDirection(for: descriptor),
            timestamp: update.hasTimestamp
                ? Date(timeIntervalSince1970: TimeInterval(update.timestamp))
                : nil,
            stops: update.stopTimeUpdate.compactMap(parseStopTimeUpdate)
        )
    }

    private static func parseStopTimeUpdate(
        _ update: TransitRealtime_TripUpdate.StopTimeUpdate
    ) -> RealtimeStopEvent? {
        guard !update.stopID.isEmpty else { return nil }

        let arrival = update.hasArrival && update.arrival.hasTime
            ? Date(timeIntervalSince1970: TimeInterval(update.arrival.time))
            : nil
        let departure = update.hasDeparture && update.departure.hasTime
            ? Date(timeIntervalSince1970: TimeInterval(update.departure.time))
            : nil
        let tracks = update.hasTransitRealtime_nyctStopTimeUpdate
            ? update.TransitRealtime_nyctStopTimeUpdate
            : nil

        return RealtimeStopEvent(
            stopID: update.stopID,
            stopSequence: update.hasStopSequence ? Int(update.stopSequence) : nil,
            arrivalTime: arrival,
            departureTime: departure,
            isSkipped: update.scheduleRelationship == .skipped,
            scheduledTrack: tracks?.hasScheduledTrack == true ? tracks?.scheduledTrack : nil,
            actualTrack: tracks?.hasActualTrack == true ? tracks?.actualTrack : nil
        )
    }

    private static func parseVehiclePosition(
        _ position: TransitRealtime_VehiclePosition
    ) -> RealtimeVehiclePosition? {
        guard position.hasTrip else { return nil }
        let descriptor = position.trip
        guard !descriptor.tripID.isEmpty else { return nil }

        let status: TrainVehicleStatus?
        if position.hasCurrentStatus {
            status = switch position.currentStatus {
            case .incomingAt: .incomingAt
            case .stoppedAt: .stoppedAt
            case .inTransitTo: .inTransitTo
            }
        } else {
            status = nil
        }

        return RealtimeVehiclePosition(
            tripID: descriptor.tripID,
            routeID: descriptor.routeID,
            startDate: descriptor.startDate,
            startTime: descriptor.startTime,
            directionID: descriptor.hasDirectionID ? Int(descriptor.directionID) : nil,
            nyctTrainID: nyctDescriptor(for: descriptor)?.trainID,
            isAssigned: nyctDescriptor(for: descriptor)?.isAssigned,
            nyctDirection: nyctDirection(for: descriptor),
            stopID: position.hasStopID ? position.stopID : nil,
            stopSequence: position.hasCurrentStopSequence ? Int(position.currentStopSequence) : nil,
            status: status,
            timestamp: position.hasTimestamp
                ? Date(timeIntervalSince1970: TimeInterval(position.timestamp))
                : nil
        )
    }

    private static func nyctDescriptor(
        for descriptor: TransitRealtime_TripDescriptor
    ) -> TransitRealtime_NyctTripDescriptor? {
        descriptor.hasTransitRealtime_nyctTripDescriptor
            ? descriptor.TransitRealtime_nyctTripDescriptor
            : nil
    }

    private static func nyctDirection(
        for descriptor: TransitRealtime_TripDescriptor
    ) -> TravelDirection? {
        guard let nyct = nyctDescriptor(for: descriptor), nyct.hasDirection else { return nil }
        return switch nyct.direction {
        case .north: .northbound
        case .south: .southbound
        case .east, .west: .unknown
        }
    }
}
