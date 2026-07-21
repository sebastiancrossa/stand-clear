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

    public init(arrivals: [Arrival], fetchedAt: Date, failedFeedCount: Int) {
        self.arrivals = arrivals
        self.fetchedAt = fetchedAt
        self.failedFeedCount = failedFeedCount
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
