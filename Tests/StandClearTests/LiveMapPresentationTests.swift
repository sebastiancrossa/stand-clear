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
            makeSnapshot(
                index: 4,
                route: "A",
                latitude: 40.75,
                longitude: -73.98,
                movementState: .preDeparture
            ),
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

    func testActivitySummarySeparatesMovementStatesAndExcludesPredeparture() {
        let snapshots = [
            makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98, movementState: .inTransit),
            makeSnapshot(index: 2, route: "A", latitude: 40.75, longitude: -73.98, movementState: .atStation),
            makeSnapshot(index: 3, route: "A", latitude: 40.75, longitude: -73.98, movementState: .stalled),
            makeSnapshot(index: 4, route: "A", latitude: 40.75, longitude: -73.98, movementState: .unknown),
            makeSnapshot(index: 5, route: "A", latitude: 40.75, longitude: -73.98, movementState: .preDeparture),
        ]
        let visible = Array(snapshots.prefix(4))

        let summary = LiveMapPresentation.activitySummary(
            activeSnapshots: snapshots,
            visibleGroups: visible.map { LiveMapTrainGroup(snapshots: [$0], point: .zero) },
            unplacedTrainCount: 2
        )

        XCTAssertEqual(summary.activeTrainCount, 4)
        XCTAssertEqual(summary.inTransitTrainCount, 1)
        XCTAssertEqual(summary.atStationTrainCount, 1)
        XCTAssertEqual(summary.stalledTrainCount, 1)
        XCTAssertEqual(summary.unknownTrainCount, 1)
    }

    func testProjectionCountsScopeSharedFeedDiagnosticsToSelectedRoutes() {
        let coverage = TrainProjectionCoverage(
            eligibleObservationCount: 5,
            placedTrainCount: 3,
            predepartureObservationCount: 3,
            predepartureTrainCountsByRoute: ["N": 2, "Q": 1],
            unplacedTrainCountsByRoute: ["N": 2, "Q": 1],
            eligibleTrainCountsByRoute: ["N": 3, "Q": 2],
            placedTrainCountsByRoute: ["N": 1, "Q": 2],
            eligibleTrainCountsByFeedAndRoute: ["gtfs-nqrw": ["N": 3, "Q": 2]],
            placedTrainCountsByFeedAndRoute: ["gtfs-nqrw": ["N": 1, "Q": 2]],
            unplacedTrainCountsByFeedAndRoute: ["gtfs-nqrw": ["N": 2, "Q": 1]],
            predepartureTrainCountsByFeedAndRoute: ["gtfs-nqrw": ["N": 2, "Q": 1]]
        )

        let selected = LiveMapPresentation.projectionCountSummary(
            coverage,
            selectedRoutes: ["Q"],
            feedID: "gtfs-nqrw"
        )

        XCTAssertEqual(selected.eligibleTrainCount, 2)
        XCTAssertEqual(selected.placedTrainCount, 2)
        XCTAssertEqual(selected.waitingTrainCount, 1)
        XCTAssertEqual(selected.unplacedTrainCount, 1)
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
        let train = makeSnapshot(
            index: 1,
            route: "A",
            latitude: 40.75,
            longitude: -73.98,
            health: .aging,
            movementState: .atStation
        )
        let cluster = LiveMapTrainGroup(
            snapshots: [
                train,
                makeSnapshot(
                    index: 2,
                    route: "Q",
                    latitude: 40.75,
                    longitude: -73.98,
                    movementState: .stalled
                ),
            ],
            point: .zero
        )

        XCTAssertEqual(
            LiveMapPresentation.stationAccessibilityLabel(station),
            "Canal Street station. A and Q trains. Transfer complex."
        )
        let trainLabel = LiveMapPresentation.trainGroupAccessibilityLabel(
            LiveMapTrainGroup(snapshots: [train], point: .zero)
        )
        XCTAssertTrue(trainLabel.contains("A train to Manhattan. At station."))
        XCTAssertTrue(trainLabel.contains("Feed aging."))
        let clusterLabel = LiveMapPresentation.trainGroupAccessibilityLabel(cluster)
        XCTAssertTrue(clusterLabel.contains("2 trains grouped here. Routes A and Q."))
        XCTAssertTrue(clusterLabel.contains("1 at station and 1 stalled."))
    }

    func testMovementAndFeedDescriptionsUseSeparateVocabularies() {
        XCTAssertEqual(LiveMapPresentation.movementDescription(.inTransit), "In transit")
        XCTAssertEqual(LiveMapPresentation.movementDescription(.atStation), "At station")
        XCTAssertEqual(LiveMapPresentation.movementDescription(.stalled), "Stalled")
        XCTAssertEqual(LiveMapPresentation.movementDescription(.unknown), "Position uncertain")
        XCTAssertEqual(LiveMapPresentation.dataHealthDescription(.live), "Feed live")
        XCTAssertEqual(LiveMapPresentation.dataHealthDescription(.aging), "Feed aging")
        XCTAssertEqual(LiveMapPresentation.dataHealthDescription(.expired), "Feed expired")
    }

    func testMarkerPresentationMakesStationaryAndUncertainStatesLegible() {
        let inTransit = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98, movementState: .inTransit)
        )
        let atStation = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(index: 2, route: "A", latitude: 40.75, longitude: -73.98, movementState: .atStation)
        )
        let stalled = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(index: 3, route: "A", latitude: 40.75, longitude: -73.98, movementState: .stalled)
        )
        let unknown = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(index: 4, route: "A", latitude: 40.75, longitude: -73.98, movementState: .unknown)
        )

        XCTAssertEqual(inTransit.indicator, .none)
        XCTAssertFalse(inTransit.usesDashedRing)
        XCTAssertTrue(inTransit.showsRouteGlyph)
        XCTAssertEqual(inTransit.markerRadiusPoints, 10)
        XCTAssertEqual(atStation.indicator, .atStation)
        XCTAssertFalse(atStation.usesDashedRing)
        XCTAssertEqual(stalled.indicator, .stalled)
        XCTAssertTrue(stalled.usesDashedRing)
        XCTAssertLessThan(stalled.opacity, inTransit.opacity)
        XCTAssertEqual(unknown.indicator, .none)
        XCTAssertTrue(unknown.usesDashedRing)
        XCTAssertLessThan(unknown.opacity, stalled.opacity)
    }

    func testMarkerTierProgressFromDotsToLettersToFullDetail() {
        XCTAssertEqual(LiveMapPresentation.markerTier(longitudeDelta: 0.5), .overview)
        XCTAssertEqual(LiveMapPresentation.markerTier(longitudeDelta: 0.12), .neighborhood)
        XCTAssertEqual(LiveMapPresentation.markerTier(longitudeDelta: 0.03), .close)
        XCTAssertNil(LiveMapPresentation.collisionDistance(for: .overview))
        XCTAssertEqual(LiveMapPresentation.collisionDistance(for: .neighborhood), 12)
        XCTAssertEqual(LiveMapPresentation.collisionDistance(for: .close), 28)

        let snapshot = makeSnapshot(
            index: 1,
            route: "A",
            latitude: 40.75,
            longitude: -73.98,
            movementState: .atStation,
            headingDegrees: 90
        )
        let overview = LiveMapPresentation.markerPresentation(for: snapshot, tier: .overview)
        let neighborhood = LiveMapPresentation.markerPresentation(for: snapshot, tier: .neighborhood)
        let close = LiveMapPresentation.markerPresentation(for: snapshot, tier: .close)

        XCTAssertFalse(overview.showsRouteGlyph)
        XCTAssertFalse(overview.showsDirectionArrow)
        XCTAssertFalse(overview.usesDashedRing)
        XCTAssertEqual(overview.indicator, .none)
        XCTAssertEqual(overview.markerRadiusPoints, 3.5)

        XCTAssertTrue(neighborhood.showsRouteGlyph)
        XCTAssertTrue(neighborhood.showsDirectionArrow)
        XCTAssertFalse(neighborhood.usesDashedRing)
        XCTAssertEqual(neighborhood.indicator, .none)
        XCTAssertEqual(neighborhood.markerRadiusPoints, 7)

        XCTAssertTrue(close.showsRouteGlyph)
        XCTAssertTrue(close.showsDirectionArrow)
        XCTAssertEqual(close.indicator, .atStation)
        XCTAssertEqual(close.markerRadiusPoints, 10)
    }

    func testOverviewTierDisablesClustering() {
        let targets = (0..<5).map { index in
            LiveMapHitTarget(
                snapshot: makeSnapshot(index: index, route: "A", latitude: 40.75, longitude: -73.98),
                point: CGPoint(x: CGFloat(index), y: 20)
            )
        }
        let groups = LiveMapPresentation.trainGroups(targets, collisionDistance: nil)
        XCTAssertEqual(groups.count, 5)
        XCTAssertTrue(groups.allSatisfy { !$0.isCluster })
    }

    func testNeighborhoodClusteringOnlyMergesTrulyCoincidentTrains() {
        let closeTargets = [
            LiveMapHitTarget(
                snapshot: makeSnapshot(index: 1, route: "A", latitude: 40.75, longitude: -73.98),
                point: CGPoint(x: 20, y: 20)
            ),
            LiveMapHitTarget(
                snapshot: makeSnapshot(index: 2, route: "Q", latitude: 40.75, longitude: -73.98),
                point: CGPoint(x: 28, y: 20)
            ),
            LiveMapHitTarget(
                snapshot: makeSnapshot(index: 3, route: "A", latitude: 40.75, longitude: -73.98),
                point: CGPoint(x: 80, y: 20)
            ),
        ]
        let groups = LiveMapPresentation.trainGroups(closeTargets, collisionDistance: 12)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.flatMap(\.snapshots).count, 3)
    }

    func testClusterAnchorUsesRepresentativeMemberNotGeographicMean() throws {
        let first = makeSnapshot(index: 1, route: "A", latitude: 40.70, longitude: -74.10)
        let second = makeSnapshot(index: 2, route: "A", latitude: 40.80, longitude: -73.90)
        let third = makeSnapshot(index: 3, route: "A", latitude: 40.71, longitude: -74.09)
        let targets = [
            LiveMapHitTarget(snapshot: first, point: CGPoint(x: 0, y: 0)),
            LiveMapHitTarget(snapshot: second, point: CGPoint(x: 100, y: 100)),
            LiveMapHitTarget(snapshot: third, point: CGPoint(x: 10, y: 10)),
        ]
        let groups = LiveMapPresentation.trainGroups(targets, collisionDistance: 150)
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        let sitsOnMember = targets.contains { $0.point == group.point }
        XCTAssertTrue(sitsOnMember, "Cluster anchor must sit on a member, never the mean")
        XCTAssertEqual(group.point, CGPoint(x: 10, y: 10))
        XCTAssertEqual(group.anchorSnapshot?.id, third.id)
        let mean = CGPoint(x: 110 / 3, y: 110 / 3)
        XCTAssertNotEqual(group.point, mean)
    }

    func testClusterCountLabelCapsAtNinetyNinePlus() {
        XCTAssertEqual(LiveMapPresentation.clusterCountLabel(12), "12")
        XCTAssertEqual(LiveMapPresentation.clusterCountLabel(99), "99")
        XCTAssertEqual(LiveMapPresentation.clusterCountLabel(100), "99+")
        XCTAssertEqual(LiveMapPresentation.clusterCountLabel(440), "99+")
        XCTAssertGreaterThan(
            LiveMapPresentation.clusterRadiusPoints(count: 20),
            LiveMapPresentation.clusterRadiusPoints(count: 2)
        )
    }

    func testStructuralPassPolicyRunsImmediatelyOnChangeAndOtherwiseThrottles() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now,
                lastStructuralPass: nil,
                didReceiveNewPlans: false,
                didChangeRoutes: false,
                didChangeTier: false
            )
        )
        XCTAssertFalse(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now.addingTimeInterval(0.2),
                lastStructuralPass: now,
                didReceiveNewPlans: false,
                didChangeRoutes: false,
                didChangeTier: false
            )
        )
        XCTAssertTrue(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now.addingTimeInterval(0.6),
                lastStructuralPass: now,
                didReceiveNewPlans: false,
                didChangeRoutes: false,
                didChangeTier: false
            )
        )
        XCTAssertTrue(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now.addingTimeInterval(0.1),
                lastStructuralPass: now,
                didReceiveNewPlans: true,
                didChangeRoutes: false,
                didChangeTier: false
            )
        )
        XCTAssertTrue(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now.addingTimeInterval(0.1),
                lastStructuralPass: now,
                didReceiveNewPlans: false,
                didChangeRoutes: true,
                didChangeTier: false
            )
        )
        XCTAssertTrue(
            LiveMapStructuralPassPolicy.shouldRun(
                now: now.addingTimeInterval(0.1),
                lastStructuralPass: now,
                didReceiveNewPlans: false,
                didChangeRoutes: false,
                didChangeTier: true
            )
        )
    }

    func testMarkerDirectionArrowCommunicatesHeadingNotMotion() {
        let atStation = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(
                index: 1,
                route: "A",
                latitude: 40.75,
                longitude: -73.98,
                movementState: .atStation,
                headingDegrees: 90
            )
        )
        let stalled = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(
                index: 2,
                route: "A",
                latitude: 40.75,
                longitude: -73.98,
                movementState: .stalled,
                headingDegrees: 180
            )
        )
        let missingHeading = LiveMapPresentation.markerPresentation(
            for: makeSnapshot(index: 3, route: "A", latitude: 40.75, longitude: -73.98)
        )

        XCTAssertTrue(atStation.showsDirectionArrow)
        XCTAssertTrue(stalled.showsDirectionArrow)
        XCTAssertFalse(missingHeading.showsDirectionArrow)
    }

    func testMarkerLegendClarifiesThatTheArrowShowsDirection() {
        XCTAssertEqual(
            LiveMapPresentation.markerLegend,
            "● Station  ▰ Train  ↑ Arrow = travel direction"
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
        health: TrainDataHealth = .live,
        movementState: TrainMovementState = .inTransit,
        headingDegrees: Double? = nil
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
            headingDegrees: headingDegrees,
            previousTopologyPosition: nil,
            topologyTransitionProgress: 1,
            velocityMetersPerSecond: 8,
            confidence: .high,
            health: health,
            movementState: movementState,
            reasons: [],
            feedTimestamp: Date(timeIntervalSince1970: 1_000)
        )
    }
}
