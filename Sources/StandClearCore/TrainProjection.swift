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
    case expired
}

public enum TrainMovementState: String, Hashable, Sendable {
    case preDeparture
    case atStation
    case inTransit
    case stalled
    case unknown
}

public enum TrainProjectionReason: String, Hashable, Sendable {
    case inferredDeparture
    case localSegmentMatch
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
    public var routeID: String { id.routeID }
    public let direction: TravelDirection
    public let destination: String
    public let nextStopID: String?
    public let nextArrivalTime: Date?
    public let position: TrainPosition
    public let headingDegrees: Double?
    public let previousTopologyPosition: TrainPosition?
    public let topologyTransitionProgress: Double
    public let velocityMetersPerSecond: Double
    public let confidence: TrainConfidence
    public let health: TrainDataHealth
    public let movementState: TrainMovementState
    public let reasons: Set<TrainProjectionReason>
    public let feedTimestamp: Date

    public init(
        id: TrainRunID,
        direction: TravelDirection,
        destination: String,
        nextStopID: String?,
        nextArrivalTime: Date?,
        position: TrainPosition,
        headingDegrees: Double? = nil,
        previousTopologyPosition: TrainPosition?,
        topologyTransitionProgress: Double,
        velocityMetersPerSecond: Double,
        confidence: TrainConfidence,
        health: TrainDataHealth,
        movementState: TrainMovementState = .unknown,
        reasons: Set<TrainProjectionReason>,
        feedTimestamp: Date
    ) {
        self.id = id
        self.direction = direction
        self.destination = destination
        self.nextStopID = nextStopID
        self.nextArrivalTime = nextArrivalTime
        self.position = position
        self.headingDegrees = headingDegrees
        self.previousTopologyPosition = previousTopologyPosition
        self.topologyTransitionProgress = topologyTransitionProgress
        self.velocityMetersPerSecond = velocityMetersPerSecond
        self.confidence = confidence
        self.health = health
        self.movementState = movementState
        self.reasons = reasons
        self.feedTimestamp = feedTimestamp
    }
}

public struct TrainMotionPlan: Identifiable, Sendable {
    public let id: TrainRunID
    public var routeID: String { id.routeID }
    public let direction: TravelDirection
    public let destination: String
    public let shapeID: String?
    public let nextStopID: String?
    public let nextArrivalTime: Date?
    public let confidence: TrainConfidence
    public let reasons: Set<TrainProjectionReason>
    public let feedTimestamp: Date
    public let vehicleTimestamp: Date?
    public let movementState: TrainMovementState

    fileprivate let pathPoints: [TrackPoint]
    fileprivate let timeline: MotionTimeline
    fileprivate let topologyTransition: TopologyTransition?

    public func render(at date: Date) -> TrainRenderSnapshot? {
        let health = dataHealth(at: date)
        guard health != .expired else { return nil }

        let effectiveDate = effectiveEvaluationDate(at: date, health: health)
        let phase = timeline.phase(at: effectiveDate)
        let state = phase.curve.state(at: effectiveDate)
        let renderedMovementState = resolvedMovementState(at: effectiveDate)
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
            direction: direction,
            destination: destination,
            nextStopID: phase.nextStopID,
            nextArrivalTime: phase.nextArrivalTime,
            position: position,
            headingDegrees: Self.heading(at: state.distance, on: pathPoints),
            previousTopologyPosition: oldPosition,
            topologyTransitionProgress: transitionProgress,
            velocityMetersPerSecond: health == .aging || renderedMovementState != .inTransit ? 0 : state.velocity,
            confidence: confidence,
            health: health,
            movementState: renderedMovementState,
            reasons: reasons,
            feedTimestamp: feedTimestamp
        )
    }

    public func dataHealth(at date: Date) -> TrainDataHealth {
        let feedAge = date.timeIntervalSince(feedTimestamp)
        if feedAge >= 90 { return .expired }
        if feedAge >= 60 { return .aging }
        return .live
    }

    fileprivate func motionStateForRetarget(at date: Date) -> MotionState {
        let health = dataHealth(at: date)
        let effectiveDate = effectiveEvaluationDate(at: date, health: health)
        let phase = timeline.phase(at: effectiveDate)
        let state = phase.curve.state(at: effectiveDate)
        return MotionState(
            distance: state.distance,
            velocity: health == .live && phase.movementState == .inTransit ? state.velocity : 0
        )
    }

    fileprivate func projectedMovementState(at date: Date) -> TrainMovementState? {
        let health = dataHealth(at: date)
        guard health != .expired else { return nil }
        return resolvedMovementState(at: effectiveEvaluationDate(at: date, health: health))
    }

    private func resolvedMovementState(at date: Date) -> TrainMovementState {
        movementState == .stalled ? .stalled : timeline.phase(at: date).movementState
    }

    private func effectiveEvaluationDate(at date: Date, health: TrainDataHealth) -> Date {
        var effectiveDate = date
        if health == .aging || health == .expired {
            effectiveDate = min(effectiveDate, feedTimestamp.addingTimeInterval(60))
        }
        if movementState == .stalled, let vehicleTimestamp {
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

    private static func heading(at distance: Double, on points: [TrackPoint]) -> Double? {
        guard points.count >= 2 else { return nil }
        let upperIndex = points.firstIndex { $0.distanceMeters >= distance } ?? (points.count - 1)
        let lowerIndex = max(0, min(upperIndex - 1, points.count - 2))
        let start = points[lowerIndex]
        let end = points[lowerIndex + 1]
        let latitudeDelta = end.latitude - start.latitude
        let meanLatitude = (start.latitude + end.latitude) * .pi / 360
        let longitudeDelta = (end.longitude - start.longitude) * cos(meanLatitude)
        guard latitudeDelta != 0 || longitudeDelta != 0 else { return nil }
        let degrees = atan2(longitudeDelta, latitudeDelta) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }
}

public struct TrainProjectionCoverage: Equatable, Sendable {
    public let eligibleObservationCount: Int
    public let placedTrainCount: Int
    public let predepartureObservationCount: Int
    public let predepartureTrainCountsByRoute: [String: Int]
    public let unplacedTrainCountsByRoute: [String: Int]
    public let eligibleTrainCountsByRoute: [String: Int]
    public let placedTrainCountsByRoute: [String: Int]
    public let expiredTrainCountsByRoute: [String: Int]
    public let eligibleTrainCountsByFeed: [String: Int]
    public let placedTrainCountsByFeed: [String: Int]
    public let unplacedTrainCountsByFeed: [String: Int]
    public let expiredTrainCountsByFeed: [String: Int]
    public let predepartureTrainCountsByFeed: [String: Int]
    public let eligibleTrainCountsByFeedAndRoute: [String: [String: Int]]
    public let placedTrainCountsByFeedAndRoute: [String: [String: Int]]
    public let unplacedTrainCountsByFeedAndRoute: [String: [String: Int]]
    public let predepartureTrainCountsByFeedAndRoute: [String: [String: Int]]
    public let movementStateCounts: [TrainMovementState: Int]
    public let movementStateCountsByFeed: [String: [TrainMovementState: Int]]
    public let projectionReasonCountsByFeed: [String: [TrainProjectionReason: Int]]
    public let expiredObservationCount: Int

    public var unplacedRouteIDs: Set<String> {
        Set(unplacedTrainCountsByRoute.keys)
    }

    public var unplacedTrainCount: Int {
        max(0, eligibleObservationCount - placedTrainCount)
    }

    public static let empty = TrainProjectionCoverage(
        eligibleObservationCount: 0,
        placedTrainCount: 0,
        predepartureObservationCount: 0,
        predepartureTrainCountsByRoute: [:],
        unplacedTrainCountsByRoute: [:],
        eligibleTrainCountsByRoute: [:],
        placedTrainCountsByRoute: [:],
        expiredTrainCountsByRoute: [:],
        eligibleTrainCountsByFeed: [:],
        placedTrainCountsByFeed: [:],
        unplacedTrainCountsByFeed: [:],
        expiredTrainCountsByFeed: [:],
        predepartureTrainCountsByFeed: [:],
        eligibleTrainCountsByFeedAndRoute: [:],
        placedTrainCountsByFeedAndRoute: [:],
        unplacedTrainCountsByFeedAndRoute: [:],
        predepartureTrainCountsByFeedAndRoute: [:],
        movementStateCounts: [:],
        movementStateCountsByFeed: [:],
        projectionReasonCountsByFeed: [:],
        expiredObservationCount: 0
    )

    public init(
        eligibleObservationCount: Int,
        placedTrainCount: Int,
        predepartureObservationCount: Int = 0,
        predepartureTrainCountsByRoute: [String: Int] = [:],
        unplacedTrainCountsByRoute: [String: Int],
        eligibleTrainCountsByRoute: [String: Int] = [:],
        placedTrainCountsByRoute: [String: Int] = [:],
        expiredTrainCountsByRoute: [String: Int] = [:],
        eligibleTrainCountsByFeed: [String: Int] = [:],
        placedTrainCountsByFeed: [String: Int] = [:],
        unplacedTrainCountsByFeed: [String: Int] = [:],
        expiredTrainCountsByFeed: [String: Int] = [:],
        predepartureTrainCountsByFeed: [String: Int] = [:],
        eligibleTrainCountsByFeedAndRoute: [String: [String: Int]] = [:],
        placedTrainCountsByFeedAndRoute: [String: [String: Int]] = [:],
        unplacedTrainCountsByFeedAndRoute: [String: [String: Int]] = [:],
        predepartureTrainCountsByFeedAndRoute: [String: [String: Int]] = [:],
        movementStateCounts: [TrainMovementState: Int] = [:],
        movementStateCountsByFeed: [String: [TrainMovementState: Int]] = [:],
        projectionReasonCountsByFeed: [String: [TrainProjectionReason: Int]] = [:],
        expiredObservationCount: Int = 0
    ) {
        self.eligibleObservationCount = eligibleObservationCount
        self.placedTrainCount = placedTrainCount
        self.predepartureObservationCount = predepartureObservationCount
        self.predepartureTrainCountsByRoute = predepartureTrainCountsByRoute
        self.unplacedTrainCountsByRoute = unplacedTrainCountsByRoute
        self.eligibleTrainCountsByRoute = eligibleTrainCountsByRoute
        self.placedTrainCountsByRoute = placedTrainCountsByRoute
        self.expiredTrainCountsByRoute = expiredTrainCountsByRoute
        self.eligibleTrainCountsByFeed = eligibleTrainCountsByFeed
        self.placedTrainCountsByFeed = placedTrainCountsByFeed
        self.unplacedTrainCountsByFeed = unplacedTrainCountsByFeed
        self.expiredTrainCountsByFeed = expiredTrainCountsByFeed
        self.predepartureTrainCountsByFeed = predepartureTrainCountsByFeed
        self.eligibleTrainCountsByFeedAndRoute = eligibleTrainCountsByFeedAndRoute
        self.placedTrainCountsByFeedAndRoute = placedTrainCountsByFeedAndRoute
        self.unplacedTrainCountsByFeedAndRoute = unplacedTrainCountsByFeedAndRoute
        self.predepartureTrainCountsByFeedAndRoute = predepartureTrainCountsByFeedAndRoute
        self.movementStateCounts = movementStateCounts
        self.movementStateCountsByFeed = movementStateCountsByFeed
        self.projectionReasonCountsByFeed = projectionReasonCountsByFeed
        self.expiredObservationCount = expiredObservationCount
    }
}

public struct TrainProjectionEngine: Sendable {
    private let catalog: TrackGeometryCatalog
    private var plansByID: [TrainRunID: TrainMotionPlan] = [:]
    private var startedTrainIDs: Set<TrainRunID> = []
    public private(set) var coverage = TrainProjectionCoverage.empty

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
        startedTrainIDs.formIntersection(Set(entries.map(\.observation.id)))
        let freshEntries = entries.filter { date.timeIntervalSince($0.lastValidAt) < 90 }
        let expiredEntries = entries.filter { date.timeIntervalSince($0.lastValidAt) >= 90 }
        for entry in freshEntries where hasActiveEvidence(entry.observation, at: date) {
            startedTrainIDs.insert(entry.observation.id)
        }
        let predepartureEntries = freshEntries.filter {
            isPredeparture($0.observation, at: date) && !startedTrainIDs.contains($0.observation.id)
        }
        let predepartureIDs = Set(predepartureEntries.map(\.observation.id))
        let eligibleEntries = freshEntries.filter { !predepartureIDs.contains($0.observation.id) }
        var nextPlans: [TrainRunID: TrainMotionPlan] = [:]
        var unplacedTrainCountsByRoute: [String: Int] = [:]
        let eligibleTrainCountsByRoute = Dictionary(grouping: eligibleEntries) {
            $0.observation.routeID
        }.mapValues(\.count)
        let expiredTrainCountsByRoute = Dictionary(grouping: expiredEntries) {
            $0.observation.routeID
        }.mapValues(\.count)
        let eligibleTrainCountsByFeed = Dictionary(grouping: eligibleEntries) {
            $0.observation.id.feedID
        }.mapValues(\.count)
        let expiredTrainCountsByFeed = Dictionary(grouping: expiredEntries) {
            $0.observation.id.feedID
        }.mapValues(\.count)
        let predepartureTrainCountsByFeed = Dictionary(grouping: predepartureEntries) {
            $0.observation.id.feedID
        }.mapValues(\.count)
        let predepartureTrainCountsByRoute = Dictionary(grouping: predepartureEntries) {
            $0.observation.routeID
        }.mapValues(\.count)
        let eligibleTrainCountsByFeedAndRoute = Self.countsByFeedAndRoute(eligibleEntries)
        let predepartureTrainCountsByFeedAndRoute = Self.countsByFeedAndRoute(predepartureEntries)
        var placedTrainCountsByRoute: [String: Int] = [:]
        var placedTrainCountsByFeed: [String: Int] = [:]
        var unplacedTrainCountsByFeed: [String: Int] = [:]
        var placedTrainCountsByFeedAndRoute: [String: [String: Int]] = [:]
        var unplacedTrainCountsByFeedAndRoute: [String: [String: Int]] = [:]
        for entry in eligibleEntries {
            let observation = entry.observation
            guard let match = match(for: observation) else {
                unplacedTrainCountsByRoute[observation.routeID, default: 0] += 1
                unplacedTrainCountsByFeed[observation.id.feedID, default: 0] += 1
                unplacedTrainCountsByFeedAndRoute[observation.id.feedID, default: [:]][observation.routeID, default: 0] += 1
                continue
            }
            let prior = plansByID[observation.id]
            guard let plan = makePlan(
                observation: observation,
                lastValidAt: entry.lastValidAt,
                match: match,
                prior: prior,
                at: date
            ) else {
                unplacedTrainCountsByRoute[observation.routeID, default: 0] += 1
                unplacedTrainCountsByFeed[observation.id.feedID, default: 0] += 1
                unplacedTrainCountsByFeedAndRoute[observation.id.feedID, default: [:]][observation.routeID, default: 0] += 1
                continue
            }
            nextPlans[observation.id] = plan
            placedTrainCountsByRoute[observation.routeID, default: 0] += 1
            placedTrainCountsByFeed[observation.id.feedID, default: 0] += 1
            placedTrainCountsByFeedAndRoute[observation.id.feedID, default: [:]][observation.routeID, default: 0] += 1
        }
        plansByID = nextPlans
        var movementStateCounts: [TrainMovementState: Int] = [:]
        var movementStateCountsByFeed: [String: [TrainMovementState: Int]] = [:]
        var projectionReasonCountsByFeed: [String: [TrainProjectionReason: Int]] = [:]
        for plan in nextPlans.values {
            if let movementState = plan.projectedMovementState(at: date) {
                movementStateCounts[movementState, default: 0] += 1
                movementStateCountsByFeed[plan.id.feedID, default: [:]][movementState, default: 0] += 1
            }
            for reason in plan.reasons {
                projectionReasonCountsByFeed[plan.id.feedID, default: [:]][reason, default: 0] += 1
            }
        }
        coverage = TrainProjectionCoverage(
            eligibleObservationCount: eligibleEntries.count,
            placedTrainCount: nextPlans.count,
            predepartureObservationCount: predepartureEntries.count,
            predepartureTrainCountsByRoute: predepartureTrainCountsByRoute,
            unplacedTrainCountsByRoute: unplacedTrainCountsByRoute,
            eligibleTrainCountsByRoute: eligibleTrainCountsByRoute,
            placedTrainCountsByRoute: placedTrainCountsByRoute,
            expiredTrainCountsByRoute: expiredTrainCountsByRoute,
            eligibleTrainCountsByFeed: eligibleTrainCountsByFeed,
            placedTrainCountsByFeed: placedTrainCountsByFeed,
            unplacedTrainCountsByFeed: unplacedTrainCountsByFeed,
            expiredTrainCountsByFeed: expiredTrainCountsByFeed,
            predepartureTrainCountsByFeed: predepartureTrainCountsByFeed,
            eligibleTrainCountsByFeedAndRoute: eligibleTrainCountsByFeedAndRoute,
            placedTrainCountsByFeedAndRoute: placedTrainCountsByFeedAndRoute,
            unplacedTrainCountsByFeedAndRoute: unplacedTrainCountsByFeedAndRoute,
            predepartureTrainCountsByFeedAndRoute: predepartureTrainCountsByFeedAndRoute,
            movementStateCounts: movementStateCounts,
            movementStateCountsByFeed: movementStateCountsByFeed,
            projectionReasonCountsByFeed: projectionReasonCountsByFeed,
            expiredObservationCount: expiredEntries.count
        )
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

    private func hasActiveEvidence(_ observation: TrainObservation, at date: Date) -> Bool {
        if observation.vehicle?.status != nil || observation.vehicle?.stopSequence != nil {
            return true
        }
        guard let firstStop = observation.stops.first(where: { !$0.isSkipped }) else { return false }
        let firstEvent = firstStop.departureTime ?? firstStop.arrivalTime
        return firstEvent.map { $0 <= date } ?? false
    }

    private func isPredeparture(_ observation: TrainObservation, at date: Date) -> Bool {
        guard observation.isAssigned,
              observation.vehicle?.status == nil,
              observation.vehicle?.stopSequence == nil
        else { return false }
        let firstStop = observation.stops.first(where: { !$0.isSkipped })
        guard firstStop?.stopSequence == 1 else { return false }
        let firstEvent = firstStop?.departureTime ?? firstStop?.arrivalTime
        return firstEvent.map { $0 > date } ?? false
    }

    private static func countsByFeedAndRoute(
        _ entries: [TrainObservationCache.Entry]
    ) -> [String: [String: Int]] {
        entries.reduce(into: [:]) { counts, entry in
            let observation = entry.observation
            counts[observation.id.feedID, default: [:]][observation.routeID, default: 0] += 1
        }
    }

    private func match(for observation: TrainObservation) -> GeometryMatch? {
        let routePaths = catalog.paths(forRoute: observation.routeID)
            .filter { path in
                observation.directionID.map { path.directionIDs.contains($0) } ?? true
            }
        guard !routePaths.isEmpty else { return nil }
        let upcomingStopIDs = observation.stops.filter { !$0.isSkipped }.map(\.stopID)

        if let suffix = Self.shapeSuffix(in: observation.id.tripID) {
            let exactMatches = Self.locallyCompatiblePaths(
                routePaths.filter { $0.shapeID == suffix },
                upcomingStopIDs: upcomingStopIDs
            )
            if let path = exactMatches.first {
                return GeometryMatch(path: path, mode: .shape)
            }
            let prefixMatches = Self.locallyCompatiblePaths(
                routePaths.filter { $0.shapeID.hasPrefix(suffix) },
                upcomingStopIDs: upcomingStopIDs
            )
            if let path = Self.locallyUniquePath(in: prefixMatches, observation: observation) {
                return GeometryMatch(path: path, mode: .localSegment)
            }
        }

        if let priorPath = plansByID[observation.id]
            .flatMap({ plan in routePaths.first { $0.shapeID == plan.shapeID } }),
           Self.locallyCompatiblePaths([priorPath], upcomingStopIDs: upcomingStopIDs).first != nil
        {
            return GeometryMatch(path: priorPath, mode: .localSegment)
        }

        let compatible = Self.locallyCompatiblePaths(routePaths, upcomingStopIDs: upcomingStopIDs)
        if compatible.count == 1, let path = compatible.first {
            return GeometryMatch(path: path, mode: .localSegment)
        }
        if let path = Self.locallyUniquePath(in: compatible, observation: observation) {
            return GeometryMatch(path: path, mode: .localSegment)
        }

        let fallbackStopIDs = [observation.vehicle?.stopID, upcomingStopIDs.first].compactMap { $0 }
        for stopID in fallbackStopIDs {
            if let path = routePaths.sorted(by: { $0.shapeID < $1.shapeID }).first(where: {
                $0.anchors.contains { $0.stopID == stopID || $0.stationID == stopID }
            }) {
                return GeometryMatch(path: path, mode: .stationFallback(stopID: stopID))
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
        let movementState = Self.movementState(
            for: observation,
            feedTimestamp: observation.feedTimestamp ?? lastValidAt
        )
        let priorState = prior.flatMap { plan in
            plan.shapeID == path.shapeID ? plan.motionStateForRetarget(at: date) : nil
        }
        var liveStops = observation.stops.filter { !$0.isSkipped }
        if movementState == .inTransit, let priorState {
            liveStops.removeAll { stop in
                guard let anchor = path.anchors.first(where: {
                    $0.stopID == stop.stopID || $0.stationID == stop.stopID
                }) else { return false }
                return anchor.distanceMeters < priorState.distance - 0.5
            }
        }
        let nextStop = liveStops.first
        let nextAnchor = nextStop.flatMap { stop in
            path.anchors.first { $0.stopID == stop.stopID || $0.stationID == stop.stopID }
        }
        let vehicleAnchor = observation.vehicle?.stopID.flatMap { stopID in
            path.anchors.first { $0.stopID == stopID || $0.stationID == stopID }
        }
        var reasons: Set<TrainProjectionReason> = []
        var confidence: TrainConfidence = .high
        let timeline: MotionTimeline

        if match.mode == .localSegment {
            reasons.insert(.localSegmentMatch)
            confidence = .medium
        }

        if case let .stationFallback(stopID) = match.mode {
            guard
                  let anchor = path.anchors.first(where: { $0.stopID == stopID || $0.stationID == stopID })
            else { return nil }
            reasons.insert(.unmatchedGeometry)
            confidence = .low
            timeline = .stationary(
                distance: anchor.distanceMeters,
                at: date,
                movementState: .unknown,
                nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
                nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime
            )
        } else if observation.vehicle?.status == .stoppedAt,
                  observation.vehicle?.stopID == nextStop?.stopID,
                  let anchor = vehicleAnchor ?? nextAnchor
        {
            timeline = Self.dwellTimeline(
                at: anchor,
                stops: liveStops,
                path: path,
                date: date
            )
        } else if movementState == .unknown,
                  let prior,
                  prior.shapeID == path.shapeID
        {
            let priorState = prior.motionStateForRetarget(at: date)
            timeline = .stationary(
                distance: priorState.distance,
                at: date,
                movementState: .unknown,
                nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
                nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime
            )
            confidence = .low
        } else if movementState == .unknown, let anchor = vehicleAnchor ?? nextAnchor {
            timeline = .stationary(
                distance: anchor.distanceMeters,
                at: date,
                movementState: .unknown,
                nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
                nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime
            )
            confidence = .low
        } else if let nextStop, let nextAnchor {
            let targetDate = nextStop.arrivalTime ?? nextStop.departureTime ?? date
            let curve: MotionCurve
            if let prior, let previousState = priorState {
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
            } else if observation.vehicle?.status == .stoppedAt,
                      let vehicleAnchor,
                      vehicleAnchor.distanceMeters < nextAnchor.distanceMeters
            {
                let departure = min(observation.vehicle?.timestamp ?? date, targetDate)
                curve = MotionCurve(
                    startDistance: vehicleAnchor.distanceMeters,
                    endDistance: nextAnchor.distanceMeters,
                    startsAt: departure,
                    endsAt: max(departure, targetDate),
                    startVelocity: 0
                )
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
            timeline = Self.travelTimeline(
                initialCurve: curve,
                stops: liveStops,
                firstAnchor: nextAnchor,
                path: path,
                movementState: movementState
            )
        } else if let priorState {
            timeline = .stationary(
                distance: priorState.distance,
                at: date,
                movementState: .unknown,
                nextStopID: nil,
                nextArrivalTime: nil
            )
            reasons.insert(.unmatchedGeometry)
            confidence = .low
        } else if let anchor = vehicleAnchor ?? nextAnchor {
            timeline = .stationary(
                distance: anchor.distanceMeters,
                at: date,
                movementState: movementState,
                nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
                nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime
            )
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
            direction: observation.nyctDirection ?? Self.direction(from: observation.directionID),
            destination: observation.destination,
            shapeID: path.shapeID,
            nextStopID: nextStop?.stopID ?? observation.vehicle?.stopID,
            nextArrivalTime: nextStop?.arrivalTime ?? nextStop?.departureTime,
            confidence: confidence,
            reasons: reasons,
            feedTimestamp: observation.feedTimestamp ?? lastValidAt,
            vehicleTimestamp: observation.vehicle?.timestamp,
            movementState: movementState,
            pathPoints: path.points,
            timeline: timeline,
            topologyTransition: topologyTransition
        )
    }

    private static func dwellTimeline(
        at currentAnchor: TrackStopAnchor,
        stops: [TrainStopObservation],
        path: TrackPath,
        date: Date
    ) -> MotionTimeline {
        guard let currentStop = stops.first else {
            return .stationary(
                distance: currentAnchor.distanceMeters,
                at: date,
                movementState: .atStation,
                nextStopID: currentAnchor.stopID,
                nextArrivalTime: nil
            )
        }
        let dwellSeconds = max(TimeInterval(currentAnchor.medianDwellSeconds ?? 20), 1)
        let reportedDeparture = currentStop.departureTime
            ?? currentStop.arrivalTime?.addingTimeInterval(dwellSeconds)
            ?? date.addingTimeInterval(dwellSeconds)
        let departure = reportedDeparture > date
            ? reportedDeparture
            : date.addingTimeInterval(dwellSeconds)
        guard stops.count > 1,
              let nextAnchor = path.anchors.first(where: {
                  $0.stopID == stops[1].stopID || $0.stationID == stops[1].stopID
              }),
              nextAnchor.distanceMeters >= currentAnchor.distanceMeters
        else {
            return .stationary(
                distance: currentAnchor.distanceMeters,
                at: date,
                movementState: .atStation,
                nextStopID: currentStop.stopID,
                nextArrivalTime: currentStop.arrivalTime ?? currentStop.departureTime
            )
        }
        let nextStop = stops[1]
        let travelSeconds = TimeInterval(currentAnchor.medianTravelSecondsToNext ?? 0)
        let arrival = max(
            nextStop.arrivalTime ?? nextStop.departureTime ?? departure.addingTimeInterval(travelSeconds),
            departure
        )
        return MotionTimeline(phases: [
            MotionPhase(
                curve: .stationary(distance: currentAnchor.distanceMeters, at: date),
                validUntil: departure,
                movementState: .atStation,
                nextStopID: currentStop.stopID,
                nextArrivalTime: currentStop.arrivalTime ?? currentStop.departureTime
            ),
            MotionPhase(
                curve: MotionCurve(
                    startDistance: currentAnchor.distanceMeters,
                    endDistance: nextAnchor.distanceMeters,
                    startsAt: departure,
                    endsAt: arrival,
                    startVelocity: 0
                ),
                validUntil: arrival,
                movementState: .inTransit,
                nextStopID: nextStop.stopID,
                nextArrivalTime: arrival
            ),
            MotionPhase(
                curve: .stationary(distance: nextAnchor.distanceMeters, at: arrival),
                validUntil: nil,
                movementState: .atStation,
                nextStopID: nextStop.stopID,
                nextArrivalTime: arrival
            ),
        ])
    }

    private static func travelTimeline(
        initialCurve: MotionCurve,
        stops: [TrainStopObservation],
        firstAnchor: TrackStopAnchor,
        path: TrackPath,
        movementState: TrainMovementState
    ) -> MotionTimeline {
        guard let firstStop = stops.first, movementState == .inTransit else {
            return .single(
                curve: initialCurve,
                movementState: movementState,
                nextStopID: stops.first?.stopID,
                nextArrivalTime: stops.first?.arrivalTime ?? stops.first?.departureTime
            )
        }
        let arrival = initialCurve.endsAt
        let dwellSeconds = TimeInterval(firstAnchor.medianDwellSeconds ?? 0)
        let departure = max(
            firstStop.departureTime ?? arrival.addingTimeInterval(dwellSeconds),
            arrival
        )
        var phases = [
            MotionPhase(
                curve: initialCurve,
                validUntil: arrival,
                movementState: .inTransit,
                nextStopID: firstStop.stopID,
                nextArrivalTime: firstStop.arrivalTime ?? firstStop.departureTime ?? arrival
            ),
        ]
        if departure > arrival {
            phases.append(
                MotionPhase(
                    curve: .stationary(distance: firstAnchor.distanceMeters, at: arrival),
                    validUntil: departure,
                    movementState: .atStation,
                    nextStopID: firstStop.stopID,
                    nextArrivalTime: firstStop.arrivalTime ?? firstStop.departureTime ?? arrival
                )
            )
        }
        if stops.count > 1,
           let secondAnchor = path.anchors.first(where: {
               $0.stopID == stops[1].stopID || $0.stationID == stops[1].stopID
           }),
           secondAnchor.distanceMeters >= firstAnchor.distanceMeters
        {
            let secondStop = stops[1]
            let travelSeconds = TimeInterval(firstAnchor.medianTravelSecondsToNext ?? 0)
            let secondArrival = max(
                secondStop.arrivalTime
                    ?? secondStop.departureTime
                    ?? departure.addingTimeInterval(travelSeconds),
                departure
            )
            phases.append(
                MotionPhase(
                    curve: MotionCurve(
                        startDistance: firstAnchor.distanceMeters,
                        endDistance: secondAnchor.distanceMeters,
                        startsAt: departure,
                        endsAt: secondArrival,
                        startVelocity: 0
                    ),
                    validUntil: secondArrival,
                    movementState: .inTransit,
                    nextStopID: secondStop.stopID,
                    nextArrivalTime: secondArrival
                )
            )
            phases.append(
                MotionPhase(
                    curve: .stationary(distance: secondAnchor.distanceMeters, at: secondArrival),
                    validUntil: nil,
                    movementState: .atStation,
                    nextStopID: secondStop.stopID,
                    nextArrivalTime: secondArrival
                )
            )
        } else {
            phases.append(
                MotionPhase(
                    curve: .stationary(distance: firstAnchor.distanceMeters, at: departure),
                    validUntil: nil,
                    movementState: .atStation,
                    nextStopID: firstStop.stopID,
                    nextArrivalTime: firstStop.arrivalTime ?? firstStop.departureTime ?? arrival
                )
            )
        }
        return MotionTimeline(phases: phases)
    }

    private static func shapeSuffix(in tripID: String) -> String? {
        guard let underscore = tripID.firstIndex(of: "_") else { return nil }
        let suffix = String(tripID[tripID.index(after: underscore)...])
        return suffix.isEmpty ? nil : suffix
    }

    private static func movementState(
        for observation: TrainObservation,
        feedTimestamp: Date
    ) -> TrainMovementState {
        if let vehicleTimestamp = observation.vehicle?.timestamp,
           feedTimestamp.timeIntervalSince(vehicleTimestamp) > 90
        {
            return .stalled
        }
        switch observation.vehicle?.status {
        case .stoppedAt:
            let firstStopID = observation.stops.first(where: { !$0.isSkipped })?.stopID
            return observation.vehicle?.stopID == firstStopID ? .atStation : .inTransit
        case .incomingAt, .inTransitTo:
            return .inTransit
        case nil where observation.vehicle?.stopSequence != nil:
            return .inTransit
        case nil:
            return .unknown
        }
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

    private static func locallyCompatiblePaths(
        _ paths: [TrackPath],
        upcomingStopIDs: [String]
    ) -> [TrackPath] {
        guard !upcomingStopIDs.isEmpty else { return paths }
        let maximumWindow = min(3, upcomingStopIDs.count)
        let minimumWindow = min(2, upcomingStopIDs.count)
        for count in stride(from: maximumWindow, through: minimumWindow, by: -1) {
            let localStops = Array(upcomingStopIDs.prefix(count))
            let matches = paths.filter { containsInOrder(localStops, in: $0) }
            if !matches.isEmpty { return matches }
        }
        return []
    }

    private static func locallyUniquePath(
        in paths: [TrackPath],
        observation: TrainObservation
    ) -> TrackPath? {
        guard !paths.isEmpty else { return nil }
        if paths.count == 1 { return paths[0] }
        let segments = paths.compactMap { path in
            immediateSegment(in: path, observation: observation).map { (path, $0) }
        }
        guard segments.count == paths.count, let reference = segments.first?.1,
              segments.dropFirst().allSatisfy({ locallyEquivalent(reference, $0.1) })
        else { return nil }
        return paths.min { $0.shapeID < $1.shapeID }
    }

    private static func immediateSegment(
        in path: TrackPath,
        observation: TrainObservation
    ) -> ImmediateTrackSegment? {
        let liveStops = observation.stops.filter { !$0.isSkipped }
        guard let firstStop = liveStops.first,
              let firstIndex = anchorIndex(for: firstStop.stopID, in: path)
        else { return nil }

        let segment: (Int, Int)?
        if observation.vehicle?.status == .stoppedAt,
           let vehicleStopID = observation.vehicle?.stopID,
           let vehicleIndex = anchorIndex(for: vehicleStopID, in: path),
           vehicleIndex != firstIndex
        {
            segment = (vehicleIndex, firstIndex)
        } else if observation.vehicle?.status == .stoppedAt,
                  liveStops.count > 1,
                  let secondIndex = anchorIndex(for: liveStops[1].stopID, in: path)
        {
            segment = (firstIndex, secondIndex)
        } else if firstIndex > path.anchors.startIndex {
            segment = (path.anchors.index(before: firstIndex), firstIndex)
        } else if liveStops.count > 1,
                  let secondIndex = anchorIndex(for: liveStops[1].stopID, in: path)
        {
            segment = (firstIndex, secondIndex)
        } else {
            segment = nil
        }
        guard let (startIndex, endIndex) = segment, startIndex < endIndex else { return nil }
        let start = path.anchors[startIndex]
        let end = path.anchors[endIndex]
        guard start.pointIndex <= end.pointIndex,
              path.points.indices.contains(start.pointIndex),
              path.points.indices.contains(end.pointIndex)
        else { return nil }
        return ImmediateTrackSegment(
            startStopID: start.stopID,
            endStopID: end.stopID,
            points: Array(path.points[start.pointIndex...end.pointIndex])
        )
    }

    private static func locallyEquivalent(
        _ lhs: ImmediateTrackSegment,
        _ rhs: ImmediateTrackSegment
    ) -> Bool {
        guard lhs.startStopID == rhs.startStopID,
              lhs.endStopID == rhs.endStopID
        else { return false }
        let maximumDeviationMeters = max(
            polylineDeviation(from: lhs.points, to: rhs.points),
            polylineDeviation(from: rhs.points, to: lhs.points)
        )
        return maximumDeviationMeters <= 250
    }

    private static func polylineDeviation(from points: [TrackPoint], to polyline: [TrackPoint]) -> Double {
        guard polyline.count > 1 else { return .infinity }
        return points.map { point in
            zip(polyline, polyline.dropFirst()).map {
                distanceInMeters(from: point, toSegmentFrom: $0.0, to: $0.1)
            }.min() ?? .infinity
        }.max() ?? .infinity
    }

    private static func distanceInMeters(
        from point: TrackPoint,
        toSegmentFrom start: TrackPoint,
        to end: TrackPoint
    ) -> Double {
        let longitudeScale = 111_320 * cos(point.latitude * .pi / 180)
        let latitudeScale = 110_540.0
        let startX = (start.longitude - point.longitude) * longitudeScale
        let startY = (start.latitude - point.latitude) * latitudeScale
        let endX = (end.longitude - point.longitude) * longitudeScale
        let endY = (end.latitude - point.latitude) * latitudeScale
        let deltaX = endX - startX
        let deltaY = endY - startY
        let lengthSquared = (deltaX * deltaX) + (deltaY * deltaY)
        guard lengthSquared > 0 else { return hypot(startX, startY) }
        let projection = max(0, min(1, -((startX * deltaX) + (startY * deltaY)) / lengthSquared))
        return hypot(startX + (projection * deltaX), startY + (projection * deltaY))
    }

    private static func anchorIndex(for stopID: String, in path: TrackPath) -> Int? {
        path.anchors.firstIndex { $0.stopID == stopID || $0.stationID == stopID }
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
    enum Mode: Equatable {
        case shape
        case localSegment
        case stationFallback(stopID: String)
    }

    let path: TrackPath
    let mode: Mode
}

private struct ImmediateTrackSegment {
    let startStopID: String
    let endStopID: String
    let points: [TrackPoint]
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

private struct MotionPhase: Sendable {
    let curve: MotionCurve
    let validUntil: Date?
    let movementState: TrainMovementState
    let nextStopID: String?
    let nextArrivalTime: Date?
}

private struct MotionTimeline: Sendable {
    let phases: [MotionPhase]

    func phase(at date: Date) -> MotionPhase {
        phases.first { phase in
            phase.validUntil.map { date < $0 } ?? true
        } ?? phases[phases.count - 1]
    }

    static func single(
        curve: MotionCurve,
        movementState: TrainMovementState,
        nextStopID: String?,
        nextArrivalTime: Date?
    ) -> MotionTimeline {
        MotionTimeline(phases: [
            MotionPhase(
                curve: curve,
                validUntil: nil,
                movementState: movementState,
                nextStopID: nextStopID,
                nextArrivalTime: nextArrivalTime
            ),
        ])
    }

    static func stationary(
        distance: Double,
        at date: Date,
        movementState: TrainMovementState,
        nextStopID: String?,
        nextArrivalTime: Date?
    ) -> MotionTimeline {
        .single(
            curve: .stationary(distance: distance, at: date),
            movementState: movementState,
            nextStopID: nextStopID,
            nextArrivalTime: nextArrivalTime
        )
    }
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
    private var recentlyExpiredEntriesByID: [TrainRunID: Entry] = [:]

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

        for entries in entriesByFeedID.values {
            for (id, entry) in entries where date.timeIntervalSince(entry.lastValidAt) >= 90 {
                recentlyExpiredEntriesByID[id] = entry
            }
        }
        for feedID in entriesByFeedID.keys {
            entriesByFeedID[feedID] = entriesByFeedID[feedID]?.filter {
                date.timeIntervalSince($0.value.lastValidAt) < 90
            }
        }
        entriesByFeedID = entriesByFeedID.filter { !$0.value.isEmpty }
        let activeIDs = Set(entriesByFeedID.values.flatMap(\.keys))
        recentlyExpiredEntriesByID = recentlyExpiredEntriesByID.filter { id, entry in
            !activeIDs.contains(id) && date.timeIntervalSince(entry.lastValidAt) < 180
        }
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

    public func coverageEntries(at date: Date) -> [Entry] {
        (entries(at: date) + recentlyExpiredEntriesByID.values.filter {
            let age = date.timeIntervalSince($0.lastValidAt)
            return age >= 90 && age < 180
        })
        .sorted {
            if $0.observation.routeID != $1.observation.routeID {
                return $0.observation.routeID < $1.observation.routeID
            }
            return $0.observation.id.tripID < $1.observation.id.tripID
        }
    }
}
