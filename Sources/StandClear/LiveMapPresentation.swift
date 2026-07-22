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

struct LiveMapStation: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let routeIDs: Set<String>
    let isTransfer: Bool
    let showsInOverview: Bool
}

struct LiveMapTrainGroup {
    let snapshots: [TrainRenderSnapshot]
    let point: CGPoint

    var isCluster: Bool { snapshots.count > 1 }
}

struct LiveMapActivitySummary: Equatable {
    let activeTrainCount: Int
    let visibleTrainCount: Int
    let clusterCount: Int
    let unplacedTrainCount: Int
    let visibleTrainIDs: Set<TrainRunID>
    let clusterTrainIDSets: [Set<TrainRunID>]

    static let empty = LiveMapActivitySummary(
        activeTrainCount: 0,
        visibleTrainCount: 0,
        clusterCount: 0,
        unplacedTrainCount: 0,
        visibleTrainIDs: [],
        clusterTrainIDSets: []
    )
}

enum LiveMapStationDetail: Equatable {
    case overview
    case neighborhood
    case close
}

enum LiveMapClusterSelectionAction: Equatable {
    case zoom
    case choose
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

    static func visibleStations(
        _ stations: [LiveMapStation],
        selectedRoutes: Set<String>,
        detail: LiveMapStationDetail
    ) -> [LiveMapStation] {
        stations.filter { station in
            !station.routeIDs.isDisjoint(with: selectedRoutes)
                && (detail != .overview || station.showsInOverview)
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

    static func hitTest(
        _ groups: [LiveMapTrainGroup],
        at point: CGPoint,
        radius: CGFloat
    ) -> LiveMapTrainGroup? {
        let maximumSquaredDistance = radius * radius
        return groups
            .compactMap { group -> (LiveMapTrainGroup, CGFloat)? in
                let deltaX = group.point.x - point.x
                let deltaY = group.point.y - point.y
                let squaredDistance = (deltaX * deltaX) + (deltaY * deltaY)
                guard squaredDistance <= maximumSquaredDistance else { return nil }
                return (group, squaredDistance)
            }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                guard let left = lhs.0.snapshots.first, let right = rhs.0.snapshots.first else {
                    return lhs.0.snapshots.count < rhs.0.snapshots.count
                }
                return isOrderedBefore(left, right)
            }?
            .0
    }

    static func trainGroups(
        _ targets: [LiveMapHitTarget],
        collisionDistance: CGFloat
    ) -> [LiveMapTrainGroup] {
        guard !targets.isEmpty else { return [] }
        let sortedTargets = targets.sorted { isOrderedBefore($0.snapshot, $1.snapshot) }
        let cellSize = max(collisionDistance, 1)
        let maximumSquaredDistance = collisionDistance * collisionDistance
        let maximumClusterDiameter = collisionDistance * 2
        let maximumClusterSquaredDiameter = maximumClusterDiameter * maximumClusterDiameter
        var parents = Array(sortedTargets.indices)
        var cells: [GridCell: [Int]] = [:]

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        func cell(for point: CGPoint) -> GridCell {
            GridCell(
                x: Int(floor(point.x / cellSize)),
                y: Int(floor(point.y / cellSize))
            )
        }

        for index in sortedTargets.indices {
            let target = sortedTargets[index]
            let targetCell = cell(for: target.point)
            for deltaX in -1...1 {
                for deltaY in -1...1 {
                    let neighbor = GridCell(x: targetCell.x + deltaX, y: targetCell.y + deltaY)
                    for candidateIndex in cells[neighbor] ?? [] {
                        let candidate = sortedTargets[candidateIndex]
                        let deltaX = target.point.x - candidate.point.x
                        let deltaY = target.point.y - candidate.point.y
                        guard (deltaX * deltaX) + (deltaY * deltaY) <= maximumSquaredDistance else {
                            continue
                        }
                        let targetRoot = root(of: index)
                        let candidateRoot = root(of: candidateIndex)
                        if targetRoot != candidateRoot {
                            parents[max(targetRoot, candidateRoot)] = min(targetRoot, candidateRoot)
                        }
                    }
                }
            }
            cells[targetCell, default: []].append(index)
        }

        var indicesByRoot: [Int: [Int]] = [:]
        for index in sortedTargets.indices {
            indicesByRoot[root(of: index), default: []].append(index)
        }

        var boundedGroups = indicesByRoot.values
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
            .flatMap { indices -> [[Int]] in
                var groups: [[Int]] = []
                for index in indices {
                    if let groupIndex = groups.firstIndex(where: { group in
                        group.allSatisfy { memberIndex in
                            let deltaX = sortedTargets[index].point.x - sortedTargets[memberIndex].point.x
                            let deltaY = sortedTargets[index].point.y - sortedTargets[memberIndex].point.y
                            return (deltaX * deltaX) + (deltaY * deltaY) <= maximumClusterSquaredDiameter
                        }
                    }) {
                        groups[groupIndex].append(index)
                    } else {
                        groups.append([index])
                    }
                }
                return groups
            }

        func center(of indices: [Int]) -> CGPoint {
            let divisor = CGFloat(indices.count)
            return CGPoint(
                x: indices.reduce(0) { $0 + sortedTargets[$1].point.x } / divisor,
                y: indices.reduce(0) { $0 + sortedTargets[$1].point.y } / divisor
            )
        }

        var didMergeOverlappingGroups = true
        while didMergeOverlappingGroups {
            didMergeOverlappingGroups = false
            mergeSearch: for leftIndex in boundedGroups.indices {
                for rightIndex in boundedGroups.indices where rightIndex > leftIndex {
                    let leftCenter = center(of: boundedGroups[leftIndex])
                    let rightCenter = center(of: boundedGroups[rightIndex])
                    let deltaX = leftCenter.x - rightCenter.x
                    let deltaY = leftCenter.y - rightCenter.y
                    guard (deltaX * deltaX) + (deltaY * deltaY) < maximumSquaredDistance else {
                        continue
                    }
                    boundedGroups[leftIndex].append(contentsOf: boundedGroups[rightIndex])
                    boundedGroups.remove(at: rightIndex)
                    didMergeOverlappingGroups = true
                    break mergeSearch
                }
            }
        }

        return boundedGroups.map { indices in
            let members = indices.map { sortedTargets[$0] }
            let divisor = CGFloat(members.count)
            return LiveMapTrainGroup(
                snapshots: members.map(\.snapshot),
                point: CGPoint(
                    x: members.reduce(0) { $0 + $1.point.x } / divisor,
                    y: members.reduce(0) { $0 + $1.point.y } / divisor
                )
            )
        }
    }

    static func activitySummary(
        activeSnapshots: [TrainRenderSnapshot],
        visibleGroups: [LiveMapTrainGroup],
        unplacedTrainCount: Int
    ) -> LiveMapActivitySummary {
        LiveMapActivitySummary(
            activeTrainCount: activeSnapshots.count,
            visibleTrainCount: visibleGroups.reduce(0) { $0 + $1.snapshots.count },
            clusterCount: visibleGroups.count(where: \.isCluster),
            unplacedTrainCount: unplacedTrainCount,
            visibleTrainIDs: Set(visibleGroups.flatMap(\.snapshots).map(\.id)),
            clusterTrainIDSets: visibleGroups.filter(\.isCluster).map {
                Set($0.snapshots.map(\.id))
            }
        )
    }

    static func stationDetail(longitudeDelta: Double) -> LiveMapStationDetail {
        if longitudeDelta >= 0.18 { return .overview }
        if longitudeDelta >= 0.055 { return .neighborhood }
        return .close
    }

    static func clusterSelectionAction(longitudeDelta: Double) -> LiveMapClusterSelectionAction {
        longitudeDelta > 0.013 ? .zoom : .choose
    }

    static func survivingCluster(
        trainIDs: Set<TrainRunID>,
        groups: [LiveMapTrainGroup]
    ) -> LiveMapTrainGroup? {
        groups.first { group in
            group.isCluster && Set(group.snapshots.map(\.id)) == trainIDs
        }
    }

    static func stationAccessibilityLabel(_ station: LiveMapStation) -> String {
        let routes = joinedList(RouteID.sorted(station.routeIDs).map(RouteID.displayLabel))
        let routeDescription = routes.isEmpty ? "Routes unavailable." : "\(routes) trains."
        let transferDescription = station.isTransfer ? " Transfer complex." : ""
        return "\(station.name) station. \(routeDescription)\(transferDescription)"
    }

    static func trainGroupAccessibilityLabel(_ group: LiveMapTrainGroup) -> String {
        guard let snapshot = group.snapshots.first else { return "Live train marker." }
        if group.isCluster {
            let routes = joinedList(
                RouteID.sorted(Set(group.snapshots.map(\.routeID))).map(RouteID.displayLabel)
            )
            return "\(group.snapshots.count) live trains grouped here. Routes \(routes)."
        }
        let destination = snapshot.destination.isEmpty ? "an unavailable destination" : snapshot.destination
        return "\(RouteID.displayLabel(snapshot.routeID)) \(snapshot.health == .live ? "live" : "stale") train to \(destination)."
    }

    private static func isOrderedBefore(
        _ lhs: TrainRenderSnapshot,
        _ rhs: TrainRenderSnapshot
    ) -> Bool {
        if lhs.id.feedID != rhs.id.feedID { return lhs.id.feedID < rhs.id.feedID }
        if lhs.id.tripID != rhs.id.tripID { return lhs.id.tripID < rhs.id.tripID }
        return lhs.id.startTime < rhs.id.startTime
    }

    private static func joinedList(_ values: [String]) -> String {
        switch values.count {
        case 0: ""
        case 1: values[0]
        case 2: "\(values[0]) and \(values[1])"
        default: "\(values.dropLast().joined(separator: ", ")), and \(values.last ?? "")"
        }
    }
}

private struct GridCell: Hashable {
    let x: Int
    let y: Int
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
