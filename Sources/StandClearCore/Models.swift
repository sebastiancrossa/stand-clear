import CoreLocation
import Foundation

public struct Station: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

public enum TravelDirection: String, CaseIterable, Hashable, Sendable {
    case northbound
    case southbound
    case unknown

    public static let selectableCases: [TravelDirection] = [.northbound, .southbound]

    public var arrow: String {
        switch self {
        case .northbound: "↑"
        case .southbound: "↓"
        case .unknown: "→"
        }
    }

    public var title: String {
        switch self {
        case .northbound: "UPTOWN / NORTHBOUND"
        case .southbound: "DOWNTOWN / SOUTHBOUND"
        case .unknown: "OTHER TRAINS"
        }
    }

    public var pickerTitle: String {
        switch self {
        case .northbound: "UPTOWN / NORTHBOUND"
        case .southbound: "DOWNTOWN / SOUTHBOUND"
        case .unknown: "OTHER"
        }
    }
}

public struct Arrival: Identifiable, Hashable, Sendable {
    public let id: String
    public let routeID: String
    public let stationID: String
    public let stopID: String
    public let direction: TravelDirection
    public let destination: String
    public let arrivalTime: Date

    public init(
        id: String,
        routeID: String,
        stationID: String,
        stopID: String,
        direction: TravelDirection,
        destination: String,
        arrivalTime: Date
    ) {
        self.id = id
        self.routeID = RouteID.normalized(routeID)
        self.stationID = stationID
        self.stopID = stopID
        self.direction = direction
        self.destination = destination
        self.arrivalTime = arrivalTime
    }

    public func etaText(relativeTo now: Date = Date()) -> String {
        "\(remainingWholeSeconds(relativeTo: now) / 60) min"
    }

    public func etaMinutesSecondsText(relativeTo now: Date = Date()) -> String {
        let seconds = remainingWholeSeconds(relativeTo: now)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func remainingWholeSeconds(relativeTo now: Date) -> Int {
        max(0, Int(floor(arrivalTime.timeIntervalSince(now))))
    }
}

public struct FeedSnapshot: Sendable {
    public let arrivals: [Arrival]
    public let fetchedAt: Date
    public let failedFeedCount: Int
    public let failedRouteIDs: Set<String>

    public init(
        arrivals: [Arrival],
        fetchedAt: Date,
        failedFeedCount: Int,
        failedRouteIDs: Set<String> = []
    ) {
        self.arrivals = arrivals
        self.fetchedAt = fetchedAt
        self.failedFeedCount = failedFeedCount
        self.failedRouteIDs = failedRouteIDs
    }
}

public struct TrainRunID: Hashable, Sendable {
    public let feedID: String
    public let routeID: String
    public let tripID: String
    public let serviceDate: String
    public let startTime: String

    public init(
        feedID: String,
        routeID: String,
        tripID: String,
        serviceDate: String,
        startTime: String
    ) {
        self.feedID = feedID
        self.routeID = RouteID.normalized(routeID)
        self.tripID = tripID
        self.serviceDate = serviceDate
        self.startTime = startTime
    }
}

public struct TrainStopObservation: Hashable, Sendable {
    public let stopID: String
    public let stopSequence: Int?
    public let arrivalTime: Date?
    public let departureTime: Date?
    public let isSkipped: Bool
    public let scheduledTrack: String?
    public let actualTrack: String?

    public init(
        stopID: String,
        stopSequence: Int?,
        arrivalTime: Date?,
        departureTime: Date?,
        isSkipped: Bool,
        scheduledTrack: String?,
        actualTrack: String?
    ) {
        self.stopID = stopID
        self.stopSequence = stopSequence
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.isSkipped = isSkipped
        self.scheduledTrack = scheduledTrack
        self.actualTrack = actualTrack
    }
}

public enum TrainVehicleStatus: String, Hashable, Sendable {
    case incomingAt
    case stoppedAt
    case inTransitTo
}

public struct TrainVehicleObservation: Hashable, Sendable {
    public let entityID: String
    public let stopID: String?
    public let stopSequence: Int?
    public let status: TrainVehicleStatus?
    public let timestamp: Date?

    public init(
        entityID: String,
        stopID: String?,
        stopSequence: Int?,
        status: TrainVehicleStatus?,
        timestamp: Date?
    ) {
        self.entityID = entityID
        self.stopID = stopID
        self.stopSequence = stopSequence
        self.status = status
        self.timestamp = timestamp
    }
}

public struct TrainObservation: Identifiable, Hashable, Sendable {
    public let id: TrainRunID
    public let entityIDs: [String]
    public var routeID: String { id.routeID }
    public let directionID: Int?
    public let nyctDirection: TravelDirection?
    public let destination: String
    public let isAssigned: Bool
    public let nyctTrainID: String?
    public let feedTimestamp: Date?
    public let tripUpdateTimestamp: Date?
    public let stops: [TrainStopObservation]
    public let vehicle: TrainVehicleObservation?

    public init(
        id: TrainRunID,
        entityIDs: [String],
        directionID: Int?,
        nyctDirection: TravelDirection?,
        destination: String,
        isAssigned: Bool,
        nyctTrainID: String?,
        feedTimestamp: Date?,
        tripUpdateTimestamp: Date?,
        stops: [TrainStopObservation],
        vehicle: TrainVehicleObservation?
    ) {
        self.id = id
        self.entityIDs = entityIDs.sorted()
        self.directionID = directionID
        self.nyctDirection = nyctDirection
        self.destination = destination
        self.isAssigned = isAssigned
        self.nyctTrainID = nyctTrainID
        self.feedTimestamp = feedTimestamp
        self.tripUpdateTimestamp = tripUpdateTimestamp
        self.stops = stops
        self.vehicle = vehicle
    }
}

public enum RealtimeFeedState: String, Hashable, Sendable {
    case succeeded
    case failed
}

public struct RealtimeFeedStatus: Hashable, Sendable {
    public let feedID: String
    public let routeIDs: Set<String>
    public let state: RealtimeFeedState
    public let feedTimestamp: Date?
    public let deletedEntityIDs: Set<String>

    public init(
        feedID: String,
        routeIDs: Set<String>,
        state: RealtimeFeedState,
        feedTimestamp: Date? = nil,
        deletedEntityIDs: Set<String> = []
    ) {
        self.feedID = feedID
        self.routeIDs = Set(routeIDs.map(RouteID.normalized))
        self.state = state
        self.feedTimestamp = feedTimestamp
        self.deletedEntityIDs = deletedEntityIDs
    }
}

public struct SystemFeedSnapshot: Sendable {
    public let arrivals: [Arrival]
    public let trains: [TrainObservation]
    public let fetchedAt: Date
    public let feedStatuses: [RealtimeFeedStatus]

    public init(
        arrivals: [Arrival],
        trains: [TrainObservation],
        fetchedAt: Date,
        feedStatuses: [RealtimeFeedStatus]
    ) {
        self.arrivals = arrivals
        self.trains = trains
        self.fetchedAt = fetchedAt
        self.feedStatuses = feedStatuses
    }

    public var failedFeedCount: Int {
        feedStatuses.count { $0.state == .failed }
    }

    public var failedRouteIDs: Set<String> {
        feedStatuses.reduce(into: Set<String>()) { routeIDs, status in
            guard status.state == .failed else { return }
            routeIDs.formUnion(status.routeIDs)
        }
    }

    public var latestFeedTimestamp: Date? {
        feedStatuses.compactMap(\.feedTimestamp).max()
    }
}

public enum RouteID {
    public static let displayGroups = [
        ["A", "C", "E"],
        ["B", "D", "F", "FX", "M"],
        ["G"],
        ["L"],
        ["J", "Z"],
        ["N", "Q", "R", "W"],
        ["1", "2", "3"],
        ["4", "5", "5X", "6", "6X"],
        ["7", "7X"],
        ["H", "FS", "GS"],
        ["SI"],
    ]

    public static let displayOrder = displayGroups.flatMap { $0 }

    public static func normalized(_ routeID: String) -> String {
        routeID.uppercased()
    }

    public static func baseLine(_ routeID: String) -> String {
        let routeID = normalized(routeID)
        return isExpress(routeID) ? String(routeID.dropLast()) : routeID
    }

    public static func displayLabel(_ routeID: String) -> String {
        switch normalized(routeID) {
        case "H": "SR"
        case "FS": "SF"
        case "GS": "S"
        default: baseLine(routeID)
        }
    }

    public static func isExpress(_ routeID: String) -> Bool {
        normalized(routeID).hasSuffix("X")
    }

    public static func sorted(_ routeIDs: some Sequence<String>) -> [String] {
        let order = Dictionary(uniqueKeysWithValues: displayOrder.enumerated().map { ($1, $0) })
        return Set(routeIDs.map(normalized)).sorted {
            let lhs = order[$0] ?? Int.max
            let rhs = order[$1] ?? Int.max
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
    }

    public static func grouped(_ routeIDs: some Sequence<String>) -> [[String]] {
        let routeSet = Set(routeIDs.map(normalized))
        let knownRoutes = Set(displayOrder)
        var groups = displayGroups
            .map { group in group.filter(routeSet.contains) }
            .filter { !$0.isEmpty }
        let ungrouped = routeSet.subtracting(knownRoutes).sorted()
        if !ungrouped.isEmpty {
            groups.append(ungrouped)
        }
        return groups
    }
}

public enum ArrivalBoard {
    public static func nextArrival(
        from allArrivals: [Arrival],
        atAny stationIDs: Set<String>,
        routeID: String,
        direction: TravelDirection,
        now: Date = Date()
    ) -> Arrival? {
        let normalizedRouteID = RouteID.normalized(routeID)
        return allArrivals
            .filter {
                stationIDs.contains($0.stationID)
                    && $0.routeID == normalizedRouteID
                    && $0.direction == direction
                    && $0.arrivalTime > now
            }
            .min { $0.arrivalTime < $1.arrivalTime }
    }

    public static func arrivals(
        from allArrivals: [Arrival],
        at stationID: String,
        selectedRoutes: Set<String>,
        selectedDirections: Set<TravelDirection> = Set(TravelDirection.selectableCases),
        now: Date = Date(),
        limit: Int = 16
    ) -> [Arrival] {
        arrivals(
            from: allArrivals,
            atAny: [stationID],
            selectedRoutes: selectedRoutes,
            selectedDirections: selectedDirections,
            now: now,
            limit: limit
        )
    }

    public static func arrivals(
        from allArrivals: [Arrival],
        atAny stationIDs: Set<String>,
        selectedRoutes: Set<String>,
        selectedDirections: Set<TravelDirection> = Set(TravelDirection.selectableCases),
        now: Date = Date(),
        limit: Int = 16
    ) -> [Arrival] {
        let normalizedSelection = Set(selectedRoutes.map(RouteID.normalized))
        return Array(
            allArrivals
                .filter {
                    stationIDs.contains($0.stationID)
                        && $0.arrivalTime >= now.addingTimeInterval(-30)
                        && normalizedSelection.contains($0.routeID)
                        && selectedDirections.contains($0.direction)
                }
                .sorted { $0.arrivalTime < $1.arrivalTime }
                .prefix(limit)
        )
    }
}
