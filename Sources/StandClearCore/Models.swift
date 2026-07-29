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

    /// Fallback glyph when no vocabulary is in scope. Prefer
    /// `DirectionVocabulary.glyph(for:)`.
    public var arrow: String {
        DirectionVocabulary.uptownDowntown.glyph(for: self)
    }

    /// Fallback title when no vocabulary is in scope. Prefer
    /// `DirectionVocabulary.title(for:)`.
    public var title: String {
        DirectionVocabulary.uptownDowntown.title(for: self)
    }

    public var pickerTitle: String {
        switch self {
        case .northbound: "UPTOWN / NORTHBOUND"
        case .southbound: "DOWNTOWN / SOUTHBOUND"
        case .unknown: "OTHER"
        }
    }
}

/// Rider-facing names for the northbound/southbound toggle.
///
/// Every NYC subway route still maps to GTFS N/S stop suffixes; this enum only
/// changes what those two poles are called, and which lines may share one toggle.
public enum DirectionVocabulary: String, CaseIterable, Hashable, Sendable {
    case uptownDowntown
    case queensManhattan
    case manhattanBrooklyn
    case queensBrooklyn
    case timesSqGrandCentral
    case franklinProspect
    case broadChannelRockaway
    case stGeorgeTottenville

    public func title(for direction: TravelDirection) -> String {
        switch (self, direction) {
        case (.uptownDowntown, .northbound): "UPTOWN"
        case (.uptownDowntown, .southbound): "DOWNTOWN"
        case (.queensManhattan, .northbound): "QUEENS"
        case (.queensManhattan, .southbound): "MANHATTAN"
        case (.manhattanBrooklyn, .northbound): "MANHATTAN"
        case (.manhattanBrooklyn, .southbound): "BROOKLYN"
        case (.queensBrooklyn, .northbound): "QUEENS"
        case (.queensBrooklyn, .southbound): "BROOKLYN"
        case (.timesSqGrandCentral, .northbound): "TIMES SQ"
        case (.timesSqGrandCentral, .southbound): "GRAND CENTRAL"
        case (.franklinProspect, .northbound): "FRANKLIN AV"
        case (.franklinProspect, .southbound): "PROSPECT PARK"
        case (.broadChannelRockaway, .northbound): "BROAD CHANNEL"
        case (.broadChannelRockaway, .southbound): "ROCKAWAY PARK"
        case (.stGeorgeTottenville, .northbound): "ST GEORGE"
        case (.stGeorgeTottenville, .southbound): "TOTTENVILLE"
        case (_, .unknown): "OTHER"
        }
    }

    public func glyph(for direction: TravelDirection) -> String {
        switch (self, direction) {
        case (.uptownDowntown, .northbound),
             (.queensBrooklyn, .northbound),
             (.franklinProspect, .northbound),
             (.broadChannelRockaway, .northbound),
             (.stGeorgeTottenville, .northbound):
            "↑"
        case (.uptownDowntown, .southbound),
             (.queensBrooklyn, .southbound),
             (.franklinProspect, .southbound),
             (.broadChannelRockaway, .southbound),
             (.stGeorgeTottenville, .southbound):
            "↓"
        case (.queensManhattan, .northbound),
             (.manhattanBrooklyn, .southbound),
             (.timesSqGrandCentral, .southbound):
            "→"
        case (.queensManhattan, .southbound),
             (.manhattanBrooklyn, .northbound),
             (.timesSqGrandCentral, .northbound):
            "←"
        case (_, .unknown):
            "→"
        }
    }

    public func accessibilityName(for direction: TravelDirection) -> String {
        switch (self, direction) {
        case (.uptownDowntown, .northbound): "uptown"
        case (.uptownDowntown, .southbound): "downtown"
        case (.queensManhattan, .northbound),
             (.queensBrooklyn, .northbound):
            "toward Queens"
        case (.queensManhattan, .southbound),
             (.manhattanBrooklyn, .northbound):
            "toward Manhattan"
        case (.manhattanBrooklyn, .southbound),
             (.queensBrooklyn, .southbound):
            "toward Brooklyn"
        case (.timesSqGrandCentral, .northbound): "toward Times Square"
        case (.timesSqGrandCentral, .southbound): "toward Grand Central"
        case (.franklinProspect, .northbound): "toward Franklin Avenue"
        case (.franklinProspect, .southbound): "toward Prospect Park"
        case (.broadChannelRockaway, .northbound): "toward Broad Channel"
        case (.broadChannelRockaway, .southbound): "toward Rockaway Park"
        case (.stGeorgeTottenville, .northbound): "toward St George"
        case (.stGeorgeTottenville, .southbound): "toward Tottenville"
        case (_, .unknown): "unknown direction"
        }
    }

    /// Vocabulary shared by a selection. Empty selections default to uptown/downtown.
    /// Mixed selections (should not occur after auto-switch / migration) resolve to the
    /// majority vocabulary, with uptown/downtown winning ties.
    public static func forSelection(_ routes: some Sequence<String>) -> DirectionVocabulary {
        let routes = Array(routes)
        guard !routes.isEmpty else { return .uptownDowntown }
        return majorityVocabulary(in: routes)
    }

    /// Keeps only routes belonging to the majority vocabulary. Tie-breaks toward
    /// `.uptownDowntown` so a mixed legacy save like `{Q, 7}` keeps the Q.
    public static func compatibleSubset(of routes: Set<String>) -> Set<String> {
        let normalized = Set(routes.map(RouteID.normalized))
        guard !normalized.isEmpty else { return [] }
        let vocabulary = majorityVocabulary(in: Array(normalized))
        return Set(normalized.filter { RouteID.vocabulary($0) == vocabulary })
    }

    private static func majorityVocabulary(in routes: [String]) -> DirectionVocabulary {
        var counts: [DirectionVocabulary: Int] = [:]
        for routeID in routes {
            counts[RouteID.vocabulary(routeID), default: 0] += 1
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            if lhs.key == .uptownDowntown { return false }
            if rhs.key == .uptownDowntown { return true }
            return lhs.key.rawValue > rhs.key.rawValue
        }?.key ?? .uptownDowntown
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

    /// Direction labels for this route. Express variants inherit their base line
    /// (`7X` → 7 → Queens/Manhattan).
    public static func vocabulary(_ routeID: String) -> DirectionVocabulary {
        switch baseLine(routeID) {
        case "7": .queensManhattan
        case "L": .manhattanBrooklyn
        case "G": .queensBrooklyn
        case "GS": .timesSqGrandCentral
        case "FS": .franklinProspect
        case "H": .broadChannelRockaway
        case "SI": .stGeorgeTottenville
        default: .uptownDowntown
        }
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

public struct NearbyStation: Identifiable, Hashable, Sendable {
    public let station: Station
    public let distance: CLLocationDistance

    public var id: String { station.id }

    public init(station: Station, distance: CLLocationDistance) {
        self.station = station
        self.distance = distance
    }
}

public struct StationSection: Identifiable, Hashable, Sendable {
    public let station: Station
    public let distance: CLLocationDistance
    public let relatedStationIDs: Set<String>
    public let arrivals: [Arrival]
    public let isExpanded: Bool

    public var id: String { station.id }

    public init(
        station: Station,
        distance: CLLocationDistance,
        relatedStationIDs: Set<String>,
        arrivals: [Arrival],
        isExpanded: Bool
    ) {
        self.station = station
        self.distance = distance
        self.relatedStationIDs = relatedStationIDs
        self.arrivals = arrivals
        self.isExpanded = isExpanded
    }
}

public enum StationBoard {
    public static let nearbyStationCount = 5
    public static let collapsedArrivalLimit = 2
    public static let expandedArrivalLimit = 8

    public static func sections(
        nearby: [NearbyStation],
        catalog: StationCatalog,
        arrivals: [Arrival],
        selectedRoutes: Set<String>,
        selectedDirection: TravelDirection,
        expandedStationID: String?,
        now: Date = Date()
    ) -> [StationSection] {
        nearby.map { nearbyStation in
            let related = catalog.relatedStations(to: nearbyStation.station.id)
            let isExpanded = nearbyStation.station.id == expandedStationID
            let limit = isExpanded ? expandedArrivalLimit : collapsedArrivalLimit
            return StationSection(
                station: nearbyStation.station,
                distance: nearbyStation.distance,
                relatedStationIDs: related,
                arrivals: ArrivalBoard.arrivals(
                    from: arrivals,
                    atAny: related,
                    selectedRoutes: selectedRoutes,
                    selectedDirections: [selectedDirection],
                    now: now,
                    limit: limit
                ),
                isExpanded: isExpanded
            )
        }
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
