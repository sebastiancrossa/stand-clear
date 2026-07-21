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
        let seconds = max(0, arrivalTime.timeIntervalSince(now))
        if seconds < 15 {
            return "Due"
        }
        if seconds < 90 {
            return "\(Int(seconds.rounded())) sec"
        }
        return "\(Int(ceil(seconds / 60))) min"
    }
}

public struct FeedSnapshot: Sendable {
    public let arrivals: [Arrival]
    public let fetchedAt: Date
    public let failedFeedCount: Int

    public init(arrivals: [Arrival], fetchedAt: Date, failedFeedCount: Int) {
        self.arrivals = arrivals
        self.fetchedAt = fetchedAt
        self.failedFeedCount = failedFeedCount
    }
}

public enum RouteID {
    public static let displayOrder = [
        "A", "C", "E", "B", "D", "F", "M", "G", "L", "J", "Z",
        "N", "Q", "R", "W", "1", "2", "3", "4", "5", "5X", "6", "6X",
        "7", "7X", "FX", "H", "FS", "GS", "SI",
    ]

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
}

public enum ArrivalBoard {
    public static func arrivals(
        from allArrivals: [Arrival],
        at stationID: String,
        selectedRoutes: Set<String>,
        now: Date = Date(),
        limit: Int = 16
    ) -> [Arrival] {
        arrivals(
            from: allArrivals,
            atAny: [stationID],
            selectedRoutes: selectedRoutes,
            now: now,
            limit: limit
        )
    }

    public static func arrivals(
        from allArrivals: [Arrival],
        atAny stationIDs: Set<String>,
        selectedRoutes: Set<String>,
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
                }
                .sorted { $0.arrivalTime < $1.arrivalTime }
                .prefix(limit)
        )
    }
}
