import CoreGraphics
@testable import StandClear
import StandClearCore
import XCTest

final class LiveMapPresentationTests: XCTestCase {
    func testVisibleSnapshotsFiltersRoutesHealthAndGeographicBounds() {
        let snapshots = [
            makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98),
            makeSnapshot(index: 2, route: "Q", latitude: 40.76, longitude: -73.97),
            makeSnapshot(index: 3, route: "A", latitude: 41.20, longitude: -73.98, health: .expired),
        ]

        let visible = LiveMapPresentation.visibleSnapshots(
            snapshots,
            selectedRoutes: ["A"],
            bounds: GeographicBounds(
                minimumLatitude: 40.70,
                maximumLatitude: 40.80,
                minimumLongitude: -74.05,
                maximumLongitude: -73.90
            )
        )

        XCTAssertEqual(visible.map(\.routeID), ["A"])
        XCTAssertEqual(visible.map(\.id.tripID), ["trip-1"])
    }

    func testHitTestChoosesNearestTrainWithinRadiusAndUsesStableTieBreak() {
        let first = makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98)
        let second = makeSnapshot(index: 2, route: "Q", latitude: 40.76, longitude: -73.97)
        let targets = [
            LiveMapHitTarget(snapshot: second, point: CGPoint(x: 103, y: 100)),
            LiveMapHitTarget(snapshot: first, point: CGPoint(x: 103, y: 100)),
        ]

        XCTAssertEqual(
            LiveMapPresentation.hitTest(targets, at: CGPoint(x: 100, y: 100), radius: 12)?.id,
            first.id
        )
        XCTAssertNil(LiveMapPresentation.hitTest(targets, at: CGPoint(x: 200, y: 200), radius: 12))
    }

    func testTrainGroupsClusterCollidingTargetsAndPreserveEveryTrain() {
        let first = makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98)
        let second = makeSnapshot(index: 2, route: "Q", latitude: 40.75, longitude: -73.98)
        let third = makeSnapshot(index: 3, route: "A", latitude: 40.75, longitude: -73.98)
        let groups = LiveMapPresentation.trainGroups(
            [
                LiveMapHitTarget(snapshot: third, point: CGPoint(x: 80, y: 20)),
                LiveMapHitTarget(snapshot: second, point: CGPoint(x: 27, y: 20)),
                LiveMapHitTarget(snapshot: first, point: CGPoint(x: 20, y: 20)),
            ],
            collisionDistance: 18
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.flatMap(\.snapshots).count, 3)
        XCTAssertEqual(groups[0].snapshots.map(\.id.tripID), ["trip-1", "trip-2"])
        XCTAssertEqual(groups[1].snapshots.map(\.id.tripID), ["trip-3"])
    }

    func testTrainGroupsBoundLongChainsWithoutLeavingOverlappingBadges() {
        let targets = (0..<4).map { index in
            LiveMapHitTarget(
                snapshot: makeSnapshot(
                    index: index,
                    route: "A",
                    latitude: 40.75,
                    longitude: -73.98
                ),
                point: CGPoint(x: CGFloat(index * 20), y: 20)
            )
        }

        let groups = LiveMapPresentation.trainGroups(targets, collisionDistance: 25)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.flatMap(\.snapshots).count, 4)

        let formerlyOverlapping = LiveMapPresentation.trainGroups(
            (0..<3).map { index in
                LiveMapHitTarget(
                    snapshot: makeSnapshot(
                        index: index,
                        route: "A",
                        latitude: 40.75,
                        longitude: -73.98
                    ),
                    point: CGPoint(x: [0, 28, 29][index], y: 20)
                )
            },
            collisionDistance: 28
        )
        XCTAssertEqual(formerlyOverlapping.count, 1)
    }

    func testActivitySummaryCountsVisibleClusterMembersInsteadOfGlyphs() {
        let active = (1...4).map {
            makeSnapshot(index: $0, route: "A", latitude: 40.75, longitude: -73.98)
        }
        let groups = [
            LiveMapTrainGroup(snapshots: Array(active.prefix(3)), point: .zero),
            LiveMapTrainGroup(snapshots: [active[3]], point: CGPoint(x: 80, y: 20)),
        ]

        let summary = LiveMapPresentation.activitySummary(
            activeSnapshots: active,
            visibleGroups: groups,
            unplacedTrainCount: 2
        )

        XCTAssertEqual(summary.activeTrainCount, 4)
        XCTAssertEqual(summary.visibleTrainCount, 4)
        XCTAssertEqual(summary.clusterCount, 1)
        XCTAssertEqual(summary.unplacedTrainCount, 2)
        XCTAssertEqual(summary.clusterTrainIDSets, [Set(active.prefix(3).map(\.id))])
    }

    func testGroupHitTestReturnsTheNearestCluster() {
        let first = makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98)
        let second = makeSnapshot(index: 2, route: "Q", latitude: 40.75, longitude: -73.98)
        let cluster = LiveMapTrainGroup(
            snapshots: [first, second],
            point: CGPoint(x: 25, y: 20)
        )
        let individual = LiveMapTrainGroup(
            snapshots: [first],
            point: CGPoint(x: 80, y: 20)
        )

        XCTAssertTrue(
            LiveMapPresentation.hitTest(
                [individual, cluster],
                at: CGPoint(x: 20, y: 20),
                radius: 15
            )?.isCluster == true
        )
    }

    func testStationDetailProgressesFromTransfersToNodesAndLabels() {
        XCTAssertEqual(LiveMapPresentation.stationDetail(longitudeDelta: 0.5), .overview)
        XCTAssertEqual(LiveMapPresentation.stationDetail(longitudeDelta: 0.12), .neighborhood)
        XCTAssertEqual(LiveMapPresentation.stationDetail(longitudeDelta: 0.03), .close)
    }

    func testStationVisibilityFiltersRoutesAndUsesOneTransferComplexAtOverview() {
        let stations = [
            LiveMapStation(
                id: "transfer-a",
                name: "Transfer",
                latitude: 40.75,
                longitude: -73.98,
                routeIDs: ["A", "Q"],
                isTransfer: true,
                showsInOverview: true
            ),
            LiveMapStation(
                id: "transfer-b",
                name: "Transfer",
                latitude: 40.751,
                longitude: -73.981,
                routeIDs: ["A", "Q"],
                isTransfer: true,
                showsInOverview: false
            ),
            LiveMapStation(
                id: "local",
                name: "Local",
                latitude: 40.752,
                longitude: -73.982,
                routeIDs: ["A"],
                isTransfer: false,
                showsInOverview: false
            ),
            LiveMapStation(
                id: "other-route",
                name: "Other",
                latitude: 40.753,
                longitude: -73.983,
                routeIDs: ["Q"],
                isTransfer: false,
                showsInOverview: false
            ),
        ]

        XCTAssertEqual(
            LiveMapPresentation.visibleStations(
                stations,
                selectedRoutes: ["A"],
                detail: .overview
            ).map(\.id),
            ["transfer-a"]
        )
        XCTAssertEqual(
            LiveMapPresentation.visibleStations(
                stations,
                selectedRoutes: ["A"],
                detail: .close
            ).map(\.id),
            ["transfer-a", "transfer-b", "local"]
        )
    }

    func testClusterSelectionZoomsUntilClosestUsefulLevelThenShowsChooser() {
        XCTAssertEqual(LiveMapPresentation.clusterSelectionAction(longitudeDelta: 0.20), .zoom)
        XCTAssertEqual(LiveMapPresentation.clusterSelectionAction(longitudeDelta: 0.014), .zoom)
        XCTAssertEqual(LiveMapPresentation.clusterSelectionAction(longitudeDelta: 0.012), .choose)
    }

    func testPendingClusterOnlySurvivesWhenTheExactGroupRemainsTogether() {
        let trains = (1...4).map {
            makeSnapshot(index: $0, route: "A", latitude: 40.75, longitude: -73.98)
        }
        let pending = Set(trains.prefix(2).map(\.id))
        let surviving = LiveMapPresentation.survivingCluster(
            trainIDs: pending,
            groups: [LiveMapTrainGroup(snapshots: Array(trains.prefix(2)), point: .zero)]
        )
        let split = LiveMapPresentation.survivingCluster(
            trainIDs: pending,
            groups: [
                LiveMapTrainGroup(snapshots: [trains[0], trains[2]], point: .zero),
                LiveMapTrainGroup(snapshots: [trains[1], trains[3]], point: .zero),
            ]
        )

        XCTAssertEqual(surviving?.snapshots.map(\.id), Array(trains.prefix(2)).map(\.id))
        XCTAssertNil(split)
    }

    func testMapObjectAccessibilityLabelsExplainMarkerTypeAndIdentity() {
        let station = LiveMapStation(
            id: "station",
            name: "Canal Street",
            latitude: 40.72,
            longitude: -74,
            routeIDs: ["A", "Q"],
            isTransfer: true,
            showsInOverview: true
        )
        let train = makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98)
        let cluster = LiveMapTrainGroup(
            snapshots: [train, makeSnapshot(index: 2, route: "Q", latitude: 40.75, longitude: -73.98)],
            point: .zero
        )

        XCTAssertEqual(
            LiveMapPresentation.stationAccessibilityLabel(station),
            "Canal Street station. A and Q trains. Transfer complex."
        )
        XCTAssertTrue(LiveMapPresentation.trainGroupAccessibilityLabel(
            LiveMapTrainGroup(snapshots: [train], point: .zero)
        ).contains("A live train to Manhattan"))
        XCTAssertEqual(
            LiveMapPresentation.trainGroupAccessibilityLabel(cluster),
            "2 live trains grouped here. Routes A and Q."
        )
    }

    func testFeedPresentationDistinguishesWaitingLivePartialAndStale() {
        let now = Date(timeIntervalSince1970: 1_000)
        let successful = RealtimeFeedStatus(
            feedID: "ace",
            routeIDs: ["A"],
            state: .succeeded,
            feedTimestamp: now.addingTimeInterval(-20)
        )
        let failed = RealtimeFeedStatus(
            feedID: "nqrw",
            routeIDs: ["N", "Q"],
            state: .failed
        )
        let staleSuccessful = RealtimeFeedStatus(
            feedID: "ace",
            routeIDs: ["A"],
            state: .succeeded,
            feedTimestamp: now.addingTimeInterval(-70)
        )

        XCTAssertEqual(LiveMapFeedPresentation.make(statuses: [], latestTimestamp: nil, now: now).state, .waiting)
        XCTAssertEqual(
            LiveMapFeedPresentation.make(statuses: [successful], latestTimestamp: successful.feedTimestamp, now: now).state,
            .live
        )
        XCTAssertEqual(
            LiveMapFeedPresentation.make(statuses: [successful, failed], latestTimestamp: successful.feedTimestamp, now: now).state,
            .partial
        )
        XCTAssertEqual(
            LiveMapFeedPresentation.make(
                statuses: [staleSuccessful],
                latestTimestamp: now.addingTimeInterval(-70),
                now: now
            ).state,
            .stale
        )
    }

    func testFeedPresentationReportsInitialFailureAndStaleGroupsWithinPartialData() {
        let now = Date(timeIntervalSince1970: 1_000)
        let stale = RealtimeFeedStatus(
            feedID: "ace",
            routeIDs: ["A"],
            state: .succeeded,
            feedTimestamp: now.addingTimeInterval(-70)
        )
        let fresh = RealtimeFeedStatus(
            feedID: "irt",
            routeIDs: ["1"],
            state: .succeeded,
            feedTimestamp: now.addingTimeInterval(-10)
        )
        let failed = RealtimeFeedStatus(
            feedID: "nqrw",
            routeIDs: ["N"],
            state: .failed
        )

        let unavailable = LiveMapFeedPresentation.make(
            statuses: [],
            latestTimestamp: nil,
            now: now,
            failureMessage: "The MTA feeds are unavailable."
        )
        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertEqual(unavailable.detail, "The MTA feeds are unavailable.")

        let partial = LiveMapFeedPresentation.make(
            statuses: [fresh, stale, failed],
            latestTimestamp: fresh.feedTimestamp,
            now: now
        )
        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.detail, "1 feed unavailable · 1 feed stale")
    }

    func testSixHundredTrainFixtureCullsDeterministicallyWithoutPerTrainState() {
        let snapshots = (0..<600).map { index in
            makeSnapshot(
                index: index,
                route: index.isMultiple(of: 2) ? "A" : "Q",
                latitude: index < 300 ? 40.75 : 41.25,
                longitude: -73.98
            )
        }

        let visible = LiveMapPresentation.visibleSnapshots(
            snapshots,
            selectedRoutes: ["A", "Q"],
            bounds: GeographicBounds(
                minimumLatitude: 40.70,
                maximumLatitude: 40.80,
                minimumLongitude: -74.05,
                maximumLongitude: -73.90
            )
        )

        XCTAssertEqual(visible.count, 300)
        XCTAssertEqual(Set(visible.map(\.id)).count, 300)

        let targets = visible.enumerated().map { index, snapshot in
            LiveMapHitTarget(
                snapshot: snapshot,
                point: CGPoint(x: CGFloat(index % 30) * 12, y: CGFloat(index / 30) * 12)
            )
        }
        let groups = LiveMapPresentation.trainGroups(targets, collisionDistance: 18)
        XCTAssertEqual(groups.flatMap(\.snapshots).count, 300)
        XCTAssertEqual(Set(groups.flatMap(\.snapshots).map(\.id)).count, 300)
    }

    func testAnimationPolicyRunsTheDisplayLinkOnlyForVisibleNonReducedMotionMaps() {
        XCTAssertTrue(
            LiveMapAnimationPolicy.shouldRunDisplayLink(reduceMotion: false, isWindowVisible: true)
        )
        XCTAssertFalse(
            LiveMapAnimationPolicy.shouldRunDisplayLink(reduceMotion: true, isWindowVisible: true)
        )
        XCTAssertFalse(
            LiveMapAnimationPolicy.shouldRunDisplayLink(reduceMotion: false, isWindowVisible: false)
        )
    }

    func testAnimationPolicyFreezesReducedMotionPositionsUntilPlansChange() {
        XCTAssertTrue(
            LiveMapAnimationPolicy.shouldAdvanceReducedMotionSnapshot(
                didReceiveNewPlans: false,
                didEnableReduceMotion: false,
                hasFrozenSnapshot: false
            )
        )
        XCTAssertFalse(
            LiveMapAnimationPolicy.shouldAdvanceReducedMotionSnapshot(
                didReceiveNewPlans: false,
                didEnableReduceMotion: false,
                hasFrozenSnapshot: true
            )
        )
        XCTAssertTrue(
            LiveMapAnimationPolicy.shouldAdvanceReducedMotionSnapshot(
                didReceiveNewPlans: true,
                didEnableReduceMotion: false,
                hasFrozenSnapshot: true
            )
        )
        XCTAssertTrue(
            LiveMapAnimationPolicy.shouldAdvanceReducedMotionSnapshot(
                didReceiveNewPlans: false,
                didEnableReduceMotion: true,
                hasFrozenSnapshot: true
            )
        )
    }

    private func makeSnapshot(
        index: Int,
        route: String,
        latitude: Double,
        longitude: Double,
        health: TrainDataHealth = .live
    ) -> TrainRenderSnapshot {
        let id = TrainRunID(
            feedID: "test",
            routeID: route,
            tripID: "trip-\(index)",
            serviceDate: "20260722",
            startTime: "12:00:00"
        )
        return TrainRenderSnapshot(
            id: id,
            direction: .northbound,
            destination: "Manhattan",
            nextStopID: "R16N",
            nextArrivalTime: Date(timeIntervalSince1970: 1_060),
            position: TrainPosition(latitude: latitude, longitude: longitude, distanceMeters: 1_000),
            previousTopologyPosition: nil,
            topologyTransitionProgress: 1,
            velocityMetersPerSecond: 8,
            confidence: .high,
            health: health,
            reasons: [],
            feedTimestamp: Date(timeIntervalSince1970: 1_000)
        )
    }
}
