import Foundation

public enum TrainConfidence: Int, Comparable, Hashable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: TrainConfidence, rhs: TrainConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    fileprivate var downgraded: TrainConfidence {
        switch self {
        case .high: .medium
        case .medium, .low: .low
        }
    }
}

public enum TrainDataHealth: String, Hashable, Sendable {
    case live
    case aging
    case stalled
    case expired
}

public enum TrainProjectionReason: String, Hashable, Sendable {
    case inferredDeparture
    case trackMismatch
    case topologyMismatch
    case unmatchedGeometry
}

public struct TrainPosition: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let distanceMeters: Double

    public init(latitude: Double, longitude: Double, distanceMeters: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
    }
}

public struct TrainRenderSnapshot: Identifiable, Equatable, Sendable {
    public let id: TrainRunID
    public let routeID: String
    public let direction: TravelDirection
    public let destination: String
    public let nextStopID: String?
    public let nextArrivalTime: Date?
    public let position: TrainPosition
    public let previousTopologyPosition: TrainPosition?
    public let topologyTransitionProgress: Double
    public let velocityMetersPerSecond: Double
    public let confidence: TrainConfidence
    public let health: TrainDataHealth
    public let reasons: Set<TrainProjectionReason>
    public let feedTimestamp: Date

    public init(
        id: TrainRunID,
        routeID: String,
        direction: TravelDirection,
        destination: String,
        nextStopID: String?,
        nextArrivalTime: Date?,
        position: TrainPosition,
        previousTopologyPosition: TrainPosition?,
        topologyTransitionProgress: Double,
        velocityMetersPerSecond: Double,
        confidence: TrainConfidence,
        health: TrainDataHealth,
        reasons: Set<TrainProjectionReason>,
        feedTimestamp: Date
    ) {
        self.id = id
        self.routeID = routeID
        self.direction = direction
        self.destination = destination
        self.nextStopID = nextStopID
        self.nextArrivalTime = nextArrivalTime
        self.position = position
        self.previousTopologyPosition = previousTopologyPosition
        self.topologyTransitionProgress = topologyTransitionProgress
        self.velocityMetersPerSecond = velocityMetersPerSecond
        self.confidence = confidence
        self.health = health
        self.reasons = reasons
        self.feedTimestamp = feedTimestamp
    }
}

public struct TrainMotionPlan: Identifiable, Sendable {
    public let id: TrainRunID
    public let routeID: String
    public let direction: TravelDirection
    public let destination: String
    public let shapeID: String?
    public let nextStopID: String?
    public let nextArrivalTime: Date?
    public let confidence: TrainConfidence
    public let reasons: Set<TrainProjectionReason>
    public let feedTimestamp: Date
    public let vehicleTimestamp: Date?

    fileprivate let pathPoints: [TrackPoint]
    fileprivate let curve: MotionCurve
    fileprivate let topologyTransition: TopologyTransition?

    public func render(at date: Date) -> TrainRenderSnapshot? {
        let health = dataHealth(at: date)
        guard health != .expired else { return nil }

        let effectiveDate = effectiveEvaluationDate(at: date, health: health)
        let state = curve.state(at: effectiveDate)
        let position = Self.position(at: state.distance, on: pathPoints)
        let transitionProgress: Double
        let oldPosition: TrainPosition?
        if let topologyTransition {
            let duration = topologyTransition.endsAt.timeIntervalSince(topologyTransition.beginsAt)
            transitionProgress = duration > 0
                ? min(1, max(0, date.timeIntervalSince(topologyTransition.beginsAt) / duration))
                : 1
            oldPosition = transitionProgress < 1 ? topologyTransition.previousPosition : nil
        } else {
            transitionProgress = 1
            oldPosition = nil
        }

        return TrainRenderSnapshot(
            id: id,
            routeID: routeID,
            direction: direction,
            destination: destination,
            nextStopID: nextStopID,
            nextArrivalTime: nextArrivalTime,
            position: position,
            previousTopologyPosition: oldPosition,
            topologyTransitionProgress: transitionProgress,
            velocityMetersPerSecond: health == .aging || health == .stalled ? 0 : state.velocity,
            confidence: confidence,
            health: health,
            reasons: reasons,
            feedTimestamp: feedTimestamp
        )
    }

    public func dataHealth(at date: Date) -> TrainDataHealth {
        let feedAge = date.timeIntervalSince(feedTimestamp)
        if feedAge >= 90 { return .expired }
        if let vehicleTimestamp, date.timeIntervalSince(vehicleTimestamp) > 90 { return .stalled }
        if feedAge >= 60 { return .aging }
        return .live
    }

    fileprivate func motionStateForRetarget(at date: Date) -> MotionState {
        let health = dataHealth(at: date)
        let state = curve.state(at: effectiveEvaluationDate(at: date, health: health))
        return MotionState(
            distance: state.distance,
            velocity: health == .live ? state.velocity : 0
        )
    }

    private func effectiveEvaluationDate(at date: Date, health: TrainDataHealth) -> Date {
        var effectiveDate = date
        if health == .aging || health == .expired {
            effectiveDate = min(effectiveDate, feedTimestamp.addingTimeInterval(60))
        }
        if health == .stalled, let vehicleTimestamp {
            effectiveDate = min(effectiveDate, vehicleTimestamp.addingTimeInterval(90))
        }
        return effectiveDate
    }

    private static func position(at distance: Double, on points: [TrackPoint]) -> TrainPosition {
        guard let first = points.first else {
            return TrainPosition(latitude: 0, longitude: 0, distanceMeters: distance)
        }
        guard distance > first.distanceMeters, let last = points.last else {
            return TrainPosition(latitude: first.latitude, longitude: first.longitude, distanceMeters: distance)
        }
        guard distance < last.distanceMeters else {
            return TrainPosition(latitude: last.latitude, longitude: last.longitude, distanceMeters: distance)
        }

        var lower = 0
        var upper = points.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if points[middle].distanceMeters <= distance {
                lower = middle
            } else {
                upper = middle
            }
        }
        let start = points[lower]
        let end = points[upper]
        let span = end.distanceMeters - start.distanceMeters
        let fraction = span > 0 ? (distance - start.distanceMeters) / span : 0
        return TrainPosition(
            latitude: start.latitude + ((end.latitude - start.latitude) * fraction),
            longitude: start.longitude + ((end.longitude - start.longitude) * fraction),
            distanceMeters: distance
        )
    }
}

public struct TrainProjectionEngine: Sendable {
    private let catalog: TrackGeometryCatalog
    private var plansByID: [TrainRunID: TrainMotionPlan] = [:]

    public init(catalog: TrackGeometryCatalog) {
        self.catalog = catalog
    }

    @discardableResult
    public mutating func update(
        observations: [TrainObservation],
        at date: Date
    ) -> [TrainMotionPlan] {
        update(
            entries: observations.map {
                TrainObservationCache.Entry(
                    observation: $0,
                    lastValidAt: $0.feedTimestamp ?? $0.tripUpdateTimestamp ?? $0.vehicle?.timestamp ?? date
                )
            },
            at: date
        )
    }

    @discardableResult
    public mutating func update(
        entries: [TrainObservationCache.Entry],
        at date: Date
    ) -> [TrainMotionPlan] {
        var nextPlans: [TrainRunID: TrainMotionPlan] = [:]
        for entry in entries where date.timeIntervalSince(entry.lastValidAt) < 90 {
            let observation = entry.observation
            guard let match = match(for: observation) else { continue }
            let prior = plansByID[observation.id]
            guard let plan = makePlan(
                observation: observation,
                lastValidAt: entry.lastValidAt,
                match: match,
                prior: prior,
                at: date
            ) else { continue }
            nextPlans[observation.id] = plan
        }
        plansByID = nextPlans
        return currentPlans
    }

    public var currentPlans: [TrainMotionPlan] {
        plansByID.values.sorted {
            if $0.routeID != $1.routeID { return $0.routeID < $1.routeID }
            return $0.id.tripID < $1.id.tripID
        }
    }

    public func render(at date: Date) -> [TrainRenderSnapshot] {
        currentPlans.compactMap { $0.render(at: date) }
    }

    private func match(for observation: TrainObservation) -> GeometryMatch? {
        let routePaths = catalog.paths(forRoute: observation.routeID)
            .filter { path in
                observation.directionID.map { path.directionIDs.contains($0) } ?? true
            }
        guard !routePaths.isEmpty else { return nil }
        let upcomingStopIDs = observation.stops.filter { !$0.isSkipped }.map(\.stopID)

        if let suffix = Self.shapeSuffix(in: observation.id.tripID) {
            let suffixMatches = routePaths.filter {
                ($0.shapeID == suffix || $0.shapeID.hasPrefix(suffix))
                    && Self.containsInOrder(upcomingStopIDs, in: $0)
            }
            if let path = Self.uniquelyBest(suffixMatches, stops: upcomingStopIDs) {
                return GeometryMatch(path: path, isStationFallback: false)
            }
        }

        let compatible = routePaths.filter { Self.containsInOrder(upcomingStopIDs, in: $0) }
        if let path = Self.uniqueCompatiblePath(compatible, stops: upcomingStopIDs) {
            return GeometryMatch(path: path, isStationFallback: false)
        }

        let fallbackStopIDs = [observation.vehicle?.stopID, upcomingStopIDs.first].compactMap { $0 }
        for stopID in fallbackStopIDs {
            if let path = routePaths.sorted(by: { $0.shapeID < $1.shapeID }).first(where: {
                $0.anchors.contains { $0.stopID == stopID || $0.stationID == stopID }
            }) {
                return GeometryMatch(path: path, isStationFallback: true, fallbackStopID: stopID)
            }
        }
        return nil
    }

    private func makePlan(
        observation: TrainObservation,
        lastValidAt: Date,
        match: GeometryMatch,
        prior: TrainMotionPlan?,
        at date: Date
    ) -> TrainMotionPlan? {
        let path = match.path
        let liveStops = observation.stops.filter { !$0.isSkipped }
        let nextStop = liveStops.first
        let nextAnchor = nextStop.flatMap { stop in
            path.anchors.first { $0.stopID == stop.stopID || $0.stationID == stop.stopID }
        }
        let vehicleAnchor = observation.vehicle?.stopID.flatMap { stopID in
            path.anchors.first { $0.stopID == stopID || $0.stationID == stopID }
        }
        var reasons: Set<TrainProjectionReason> = []
        var confidence: TrainConfidence = .high
        let curve: MotionCurve

        if match.isStationFallback {
            guard let stopID = match.fallbackStopID,
                  let anchor = path.anchors.first(where: { $0.stopID == stopID || $0.stationID == stopID })
            else { return nil }
            reasons.insert(.unmatchedGeometry)
            confidence = .low
            curve = MotionCurve.stationary(distance: anchor.distanceMeters, at: date)
        } else if observation.vehicle?.status == .stoppedAt, let anchor = vehicleAnchor ?? nextAnchor {
            curve = MotionCurve.stationary(distance: anchor.distanceMeters, at: date)
        } else if let nextStop, let nextAnchor {
            let targetDate = nextStop.arrivalTime ?? nextStop.departureTime ?? date
            if let prior, prior.shapeID == path.shapeID {
                let previousState = prior.motionStateForRetarget(at: date)
                let targetDistance = max(previousState.distance, nextAnchor.distanceMeters)
                curve = MotionCurve(
                    startDistance: previousState.distance,
                    endDistance: targetDistance,
                    startsAt: date,
                    endsAt: max(targetDate, date),
                    startVelocity: previousState.velocity
                )
                if prior.nextStopID != nextStop.stopID {
                    confidence = .high
                } else {
                    confidence = prior.confidence
                    reasons.formUnion(prior.reasons.filter { $0 != .topologyMismatch })
                }
            } else if let previousAnchor = Self.previousAnchor(before: nextAnchor, in: path) {
                let travel = TimeInterval(previousAnchor.medianTravelSecondsToNext ?? 0)
                let inferredDeparture = travel > 0 ? targetDate.addingTimeInterval(-travel) : date
                curve = MotionCurve(
                    startDistance: previousAnchor.distanceMeters,
                    endDistance: nextAnchor.distanceMeters,
                    startsAt: min(inferredDeparture, targetDate),
                    endsAt: max(inferredDeparture, targetDate),
                    startVelocity: 0
                )
                reasons.insert(.inferredDeparture)
                confidence = .medium
            } else {
                curve = MotionCurve.stationary(distance: nextAnchor.distanceMeters, at: date)
                reasons.insert(.unmatchedGeometry)
                confidence = .low
            }
        } else if let anchor = vehicleAnchor ?? nextAnchor {
            curve = MotionCurve.stationary(distance: anchor.distanceMeters, at: date)
            reasons.insert(.unmatchedGeometry)
            confidence = .low
        } else {
            return nil
        }

        if Self.hasTrackMismatch(observation) {
            reasons.insert(.trackMismatch)
            confidence = confidence.downgraded
        }

        var topologyTransition: TopologyTransition?
        if let prior, prior.shapeID != path.shapeID, let previous = prior.render(at: date)?.position {
            reasons.insert(.topologyMismatch)
            confidence = .low
            topologyTransition = TopologyTransition(
                previousPosition: previous,
                beginsAt: date,
                endsAt: date.addingTimeInterval(0.35)
            )
        }

        return TrainMotionPlan(
            id: observation.id,
            routeID: observation.routeID,
            direction: observation.nyctDirection ?? Self.direction(from: observation.directionID),
            destination: observation.destination,
            shapeID: path.shapeID,
            nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
            nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime,
            confidence: confidence,
            reasons: reasons,
            feedTimestamp: observation.feedTimestamp ?? lastValidAt,
            vehicleTimestamp: observation.vehicle?.timestamp,
            pathPoints: path.points,
            curve: curve,
            topologyTransition: topologyTransition
        )
    }

    private static func shapeSuffix(in tripID: String) -> String? {
        guard let underscore = tripID.firstIndex(of: "_") else { return nil }
        let suffix = String(tripID[tripID.index(after: underscore)...])
        return suffix.isEmpty ? nil : suffix
    }

    private static func containsInOrder(_ stopIDs: [String], in path: TrackPath) -> Bool {
        guard !stopIDs.isEmpty else { return false }
        var anchorIndex = path.anchors.startIndex
        for stopID in stopIDs {
            guard let found = path.anchors[anchorIndex...].firstIndex(where: {
                $0.stopID == stopID || $0.stationID == stopID
            }) else { return false }
            anchorIndex = path.anchors.index(after: found)
        }
        return true
    }

    private static func uniquelyBest(_ paths: [TrackPath], stops: [String]) -> TrackPath? {
        if paths.count == 1 { return paths[0] }
        return uniqueCompatiblePath(paths, stops: stops)
    }

    private static func uniqueCompatiblePath(_ paths: [TrackPath], stops: [String]) -> TrackPath? {
        guard !paths.isEmpty else { return nil }
        if paths.count == 1 { return paths[0] }
        let signatures = Dictionary(grouping: paths) { path in
            path.anchors.map(\.stopID).joined(separator: "|")
        }
        if signatures.count == 1 {
            return paths.min { $0.shapeID < $1.shapeID }
        }
        return nil
    }

    private static func previousAnchor(before anchor: TrackStopAnchor, in path: TrackPath) -> TrackStopAnchor? {
        guard let index = path.anchors.firstIndex(where: { $0.stopID == anchor.stopID }) else { return nil }
        guard index > path.anchors.startIndex else { return nil }
        return path.anchors[path.anchors.index(before: index)]
    }

    private static func hasTrackMismatch(_ observation: TrainObservation) -> Bool {
        observation.stops.contains { stop in
            guard let scheduled = stop.scheduledTrack, !scheduled.isEmpty,
                  let actual = stop.actualTrack, !actual.isEmpty
            else { return false }
            return scheduled != actual
        }
    }

    private static func direction(from directionID: Int?) -> TravelDirection {
        switch directionID {
        case 0: .northbound
        case 1: .southbound
        default: .unknown
        }
    }
}

private struct GeometryMatch {
    let path: TrackPath
    let isStationFallback: Bool
    let fallbackStopID: String?

    init(path: TrackPath, isStationFallback: Bool, fallbackStopID: String? = nil) {
        self.path = path
        self.isStationFallback = isStationFallback
        self.fallbackStopID = fallbackStopID
    }
}

private struct TopologyTransition: Sendable {
    let previousPosition: TrainPosition
    let beginsAt: Date
    let endsAt: Date
}

private struct MotionState: Sendable {
    let distance: Double
    let velocity: Double
}

private struct MotionCurve: Sendable {
    let startDistance: Double
    let endDistance: Double
    let startsAt: Date
    let endsAt: Date
    let startVelocity: Double

    init(
        startDistance: Double,
        endDistance: Double,
        startsAt: Date,
        endsAt: Date,
        startVelocity: Double
    ) {
        self.startDistance = startDistance
        self.endDistance = max(startDistance, endDistance)
        self.startsAt = startsAt
        self.endsAt = max(startsAt, endsAt)
        let duration = self.endsAt.timeIntervalSince(self.startsAt)
        let maximumMonotonicVelocity = duration > 0
            ? (3 * (self.endDistance - self.startDistance)) / duration
            : 0
        self.startVelocity = min(max(0, startVelocity), maximumMonotonicVelocity)
    }

    static func stationary(distance: Double, at date: Date) -> MotionCurve {
        MotionCurve(
            startDistance: distance,
            endDistance: distance,
            startsAt: date,
            endsAt: date,
            startVelocity: 0
        )
    }

    func state(at date: Date) -> MotionState {
        let duration = endsAt.timeIntervalSince(startsAt)
        guard duration > 0, endDistance > startDistance else {
            return MotionState(distance: endDistance, velocity: 0)
        }
        let elapsed = date.timeIntervalSince(startsAt)
        if elapsed <= 0 { return MotionState(distance: startDistance, velocity: startVelocity) }
        if elapsed >= duration { return MotionState(distance: endDistance, velocity: 0) }

        let t = elapsed / duration
        let t2 = t * t
        let t3 = t2 * t
        let tangent = startVelocity * duration
        let distance = ((2 * t3 - 3 * t2 + 1) * startDistance)
            + ((t3 - 2 * t2 + t) * tangent)
            + ((-2 * t3 + 3 * t2) * endDistance)
        let derivative = ((6 * t2 - 6 * t) * startDistance)
            + ((3 * t2 - 4 * t + 1) * tangent)
            + ((-6 * t2 + 6 * t) * endDistance)
        return MotionState(
            distance: min(endDistance, max(startDistance, distance)),
            velocity: max(0, derivative / duration)
        )
    }
}

public struct TrainObservationCache: Sendable {
    public struct Entry: Sendable {
        public let observation: TrainObservation
        public let lastValidAt: Date

        public init(observation: TrainObservation, lastValidAt: Date) {
            self.observation = observation
            self.lastValidAt = lastValidAt
        }
    }

    private var entriesByFeedID: [String: [TrainRunID: Entry]] = [:]

    public init() {}

    @discardableResult
    public mutating func merge(
        _ snapshot: SystemFeedSnapshot,
        at date: Date
    ) -> [Entry] {
        let statusesByFeed = Dictionary(uniqueKeysWithValues: snapshot.feedStatuses.map { ($0.feedID, $0) })
        let observationsByFeed = Dictionary(grouping: snapshot.trains, by: { $0.id.feedID })

        for (feedID, status) in statusesByFeed where status.state == .succeeded {
            var replacement: [TrainRunID: Entry] = [:]
            for observation in observationsByFeed[feedID] ?? [] {
                let lastValidAt = observation.feedTimestamp
                    ?? status.feedTimestamp
                    ?? observation.tripUpdateTimestamp
                    ?? observation.vehicle?.timestamp
                    ?? snapshot.fetchedAt
                replacement[observation.id] = Entry(observation: observation, lastValidAt: lastValidAt)
            }
            entriesByFeedID[feedID] = replacement
        }

        for (feedID, observations) in observationsByFeed where statusesByFeed[feedID] == nil {
            entriesByFeedID[feedID] = Dictionary(uniqueKeysWithValues: observations.map { observation in
                let lastValidAt = observation.feedTimestamp
                    ?? observation.tripUpdateTimestamp
                    ?? observation.vehicle?.timestamp
                    ?? snapshot.fetchedAt
                return (observation.id, Entry(observation: observation, lastValidAt: lastValidAt))
            })
        }

        for feedID in entriesByFeedID.keys {
            entriesByFeedID[feedID] = entriesByFeedID[feedID]?.filter {
                date.timeIntervalSince($0.value.lastValidAt) < 90
            }
        }
        entriesByFeedID = entriesByFeedID.filter { !$0.value.isEmpty }
        return entries(at: date)
    }

    public func entries(at date: Date) -> [Entry] {
        entriesByFeedID.values
            .flatMap(\.values)
            .filter { date.timeIntervalSince($0.lastValidAt) < 90 }
            .sorted {
                if $0.observation.routeID != $1.observation.routeID {
                    return $0.observation.routeID < $1.observation.routeID
                }
                return $0.observation.id.tripID < $1.observation.id.tripID
            }
    }
}
