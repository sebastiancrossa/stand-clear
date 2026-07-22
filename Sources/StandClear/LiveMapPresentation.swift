import CoreGraphics
import Foundation
import StandClearCore

struct GeographicBounds: Equatable {
    let minimumLatitude: Double
    let maximumLatitude: Double
    let minimumLongitude: Double
    let maximumLongitude: Double

    func contains(_ position: TrainPosition) -> Bool {
        (minimumLatitude...maximumLatitude).contains(position.latitude)
            && (minimumLongitude...maximumLongitude).contains(position.longitude)
    }
}

struct LiveMapHitTarget {
    let snapshot: TrainRenderSnapshot
    let point: CGPoint
}

enum LiveMapPresentation {
    static func visibleSnapshots(
        _ snapshots: [TrainRenderSnapshot],
        selectedRoutes: Set<String>,
        bounds: GeographicBounds
    ) -> [TrainRenderSnapshot] {
        snapshots.filter { snapshot in
            snapshot.health != .expired
                && selectedRoutes.contains(RouteID.normalized(snapshot.routeID))
                && bounds.contains(snapshot.position)
        }
    }

    static func hitTest(
        _ targets: [LiveMapHitTarget],
        at point: CGPoint,
        radius: CGFloat
    ) -> TrainRenderSnapshot? {
        let maximumSquaredDistance = radius * radius
        return targets
            .compactMap { target -> (TrainRenderSnapshot, CGFloat)? in
                let deltaX = target.point.x - point.x
                let deltaY = target.point.y - point.y
                let squaredDistance = (deltaX * deltaX) + (deltaY * deltaY)
                guard squaredDistance <= maximumSquaredDistance else { return nil }
                return (target.snapshot, squaredDistance)
            }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.id.feedID != rhs.0.id.feedID {
                    return lhs.0.id.feedID < rhs.0.id.feedID
                }
                return lhs.0.id.tripID < rhs.0.id.tripID
            }?
            .0
    }
}

enum LiveMapAnimationPolicy {
    static func shouldRunDisplayLink(
        reduceMotion: Bool,
        isWindowVisible: Bool
    ) -> Bool {
        !reduceMotion && isWindowVisible
    }

    static func shouldAdvanceReducedMotionSnapshot(
        didReceiveNewPlans: Bool,
        didEnableReduceMotion: Bool,
        hasFrozenSnapshot: Bool
    ) -> Bool {
        didReceiveNewPlans || didEnableReduceMotion || !hasFrozenSnapshot
    }
}

struct LiveMapFeedPresentation: Equatable {
    enum State: Equatable {
        case waiting
        case live
        case partial
        case stale
        case unavailable
    }

    let state: State
    let title: String
    let detail: String?
    let timestamp: Date?

    static func make(
        statuses: [RealtimeFeedStatus],
        latestTimestamp: Date?,
        now: Date,
        failureMessage: String? = nil
    ) -> LiveMapFeedPresentation {
        guard !statuses.isEmpty else {
            if let failureMessage {
                return LiveMapFeedPresentation(
                    state: .unavailable,
                    title: "MTA data unavailable",
                    detail: failureMessage,
                    timestamp: nil
                )
            }
            return LiveMapFeedPresentation(
                state: .waiting,
                title: "Waiting for MTA data",
                detail: nil,
                timestamp: nil
            )
        }

        let failedCount = statuses.count { $0.state == .failed }
        let staleCount = statuses.count { status in
            guard status.state == .succeeded else { return false }
            guard let timestamp = status.feedTimestamp else { return true }
            return now.timeIntervalSince(timestamp) >= 60
        }

        if failedCount == statuses.count {
            return LiveMapFeedPresentation(
                state: .unavailable,
                title: "MTA data unavailable",
                detail: failureMessage ?? "All MTA feeds are unavailable",
                timestamp: latestTimestamp
            )
        }

        if failedCount > 0 {
            var details = ["\(failedCount) feed\(failedCount == 1 ? "" : "s") unavailable"]
            if staleCount > 0 {
                details.append("\(staleCount) feed\(staleCount == 1 ? "" : "s") stale")
            }
            return LiveMapFeedPresentation(
                state: .partial,
                title: "Partial MTA data",
                detail: details.joined(separator: " · "),
                timestamp: latestTimestamp
            )
        }

        if staleCount > 0 {
            return LiveMapFeedPresentation(
                state: .stale,
                title: "MTA data is stale",
                detail: "\(staleCount) feed\(staleCount == 1 ? "" : "s") paused until fresh data arrives",
                timestamp: latestTimestamp
            )
        }

        return LiveMapFeedPresentation(
            state: .live,
            title: "Live estimates",
            detail: nil,
            timestamp: latestTimestamp
        )
    }
}
