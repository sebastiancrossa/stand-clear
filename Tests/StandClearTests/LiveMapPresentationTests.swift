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
