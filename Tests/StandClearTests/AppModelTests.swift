@testable import StandClear
import CoreLocation
import StandClearCore
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
    func testCompositeRefreshPreservesArrivalMergeAndRetainsFailedFeedTrainPlans() async throws {
        let now = Date()
        let geometry = try TrackGeometryCatalog.bundled()
        let path = try XCTUnwrap(geometry.resource.paths.first(where: { $0.anchors.count >= 2 }))
        let routeID = try XCTUnwrap(path.routeIDs.first)
        let observation = makeTrainObservation(routeID: routeID, path: path, now: now)
        let cachedArrival = makeArrival(id: "cached", route: routeID, time: now.addingTimeInterval(120))
        let freshArrival = makeArrival(id: "fresh", route: "G", time: now.addingTimeInterval(180))
        let client = SnapshotClient(snapshots: [
            SystemFeedSnapshot(
                arrivals: [cachedArrival],
                trains: [observation],
                fetchedAt: now,
                feedStatuses: [
                    RealtimeFeedStatus(
                        feedID: observation.id.feedID,
                        routeIDs: [routeID],
                        state: .succeeded,
                        feedTimestamp: now
                    ),
                ]
            ),
            SystemFeedSnapshot(
                arrivals: [freshArrival],
                trains: [],
                fetchedAt: now.addingTimeInterval(1),
                feedStatuses: [
                    RealtimeFeedStatus(
                        feedID: observation.id.feedID,
                        routeIDs: [routeID],
                        state: .failed
                    ),
                ]
            ),
        ])
        let model = AppModel(
            client: client,
            defaults: makeDefaults(),
            geometryLoader: FixedGeometryLoader(catalog: geometry)
        )
        await model.loadMapGeometry()

        await model.refresh()
        XCTAssertEqual(model.mapMotionPlans.map(\.id), [observation.id])

        await model.refresh()

        XCTAssertEqual(Set(model.allArrivals.map(\.id)), ["cached", "fresh"])
        XCTAssertEqual(model.mapMotionPlans.map(\.id), [observation.id])
        XCTAssertEqual(model.mapFeedStatuses.first?.state, .failed)
        XCTAssertEqual(model.mapLatestFeedTimestamp, now)

        await model.refresh()

        XCTAssertEqual(model.mapMotionPlans.map(\.id), [observation.id])
        XCTAssertEqual(model.mapFeedStatuses.first?.state, .failed)
        XCTAssertEqual(model.mapLatestFeedTimestamp, now)
    }

    func testMapGeometryFailureDoesNotChangeStartupOrArrivalState() async {
        let now = Date()
        let arrival = makeArrival(id: "q", route: "Q", time: now.addingTimeInterval(120))
        let client = SnapshotClient(snapshots: [
            SystemFeedSnapshot(
                arrivals: [arrival],
                trains: [],
                fetchedAt: now,
                feedStatuses: []
            ),
        ])
        let model = AppModel(
            client: client,
            defaults: makeDefaults(),
            geometryLoader: FailingGeometryLoader()
        )
        await model.refresh()
        let startupErrorBeforeMap = model.startupError

        await model.loadMapGeometry()

        XCTAssertEqual(model.allArrivals.map(\.id), ["q"])
        XCTAssertEqual(model.startupError, startupErrorBeforeMap)
        XCTAssertNil(model.mapGeometry)
        XCTAssertEqual(model.mapGeometryError, "Test geometry failed.")
    }

    func testTogglingArrivalTimeDisplayChangesTheSharedBoardMode() {
        let model = AppModel(defaults: makeDefaults())

        XCTAssertFalse(model.showsMinutesAndSeconds)

        model.toggleArrivalTimeDisplay()
        XCTAssertTrue(model.showsMinutesAndSeconds)

        model.toggleArrivalTimeDisplay()
        XCTAssertFalse(model.showsMinutesAndSeconds)
    }

    func testTogglingPinCreatesAndPersistsPinnedService() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")

        let model = AppModel(defaults: defaults)
        model.togglePin(routeID: "q", direction: .northbound)

        XCTAssertEqual(
            model.pinnedService,
            PinnedService(routeID: "Q", direction: .northbound)
        )
        XCTAssertEqual(defaults.string(forKey: "pinnedRoute"), "Q")
        XCTAssertEqual(defaults.string(forKey: "pinnedDirection"), "northbound")
    }

    func testTogglingActivePinClearsItAndItsPreferences() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        let model = AppModel(defaults: defaults)

        model.togglePin(routeID: "Q", direction: .northbound)
        model.togglePin(routeID: "Q", direction: .northbound)

        XCTAssertNil(model.pinnedService)
        XCTAssertNil(defaults.string(forKey: "pinnedRoute"))
        XCTAssertNil(defaults.string(forKey: "pinnedDirection"))
    }

    func testValidPinRestoresOnLaunch() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        defaults.set("q", forKey: "pinnedRoute")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "pinnedDirection")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(
            model.pinnedService,
            PinnedService(routeID: "Q", direction: .northbound)
        )
    }

    func testRemovingPinnedRouteFromFiltersClearsPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        let model = AppModel(defaults: defaults)
        model.togglePin(routeID: "Q", direction: .northbound)

        model.toggleRoute("Q")

        XCTAssertNil(model.pinnedService)
        XCTAssertNil(defaults.string(forKey: "pinnedRoute"))
        XCTAssertNil(defaults.string(forKey: "pinnedDirection"))
    }

    func testRemovingPinnedDirectionFromFiltersClearsPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        let model = AppModel(defaults: defaults)
        model.togglePin(routeID: "Q", direction: .northbound)

        model.toggleDirection(.northbound)

        XCTAssertNil(model.pinnedService)
    }

    func testTogglingDifferentServiceReplacesPin() {
        let defaults = makeDefaults()
        defaults.set(["N", "Q"], forKey: "selectedRoutes")
        defaults.set(
            [TravelDirection.northbound.rawValue, TravelDirection.southbound.rawValue],
            forKey: "selectedDirections"
        )
        let model = AppModel(defaults: defaults)
        model.togglePin(routeID: "Q", direction: .northbound)

        model.togglePin(routeID: "N", direction: .southbound)

        XCTAssertEqual(
            model.pinnedService,
            PinnedService(routeID: "N", direction: .southbound)
        )
    }

    func testClearPinRemovesPersistedPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        let model = AppModel(defaults: defaults)
        model.togglePin(routeID: "Q", direction: .northbound)

        model.clearPin()

        XCTAssertNil(model.pinnedService)
        XCTAssertNil(defaults.string(forKey: "pinnedRoute"))
        XCTAssertNil(defaults.string(forKey: "pinnedDirection"))
    }

    func testInvalidStoredPinsAreDiscarded() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        defaults.set("Q", forKey: "pinnedRoute")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "pinnedDirection")

        let model = AppModel(defaults: defaults)

        XCTAssertNil(model.pinnedService)
        XCTAssertNil(defaults.string(forKey: "pinnedRoute"))
        XCTAssertNil(defaults.string(forKey: "pinnedDirection"))

        let partialDefaults = makeDefaults()
        partialDefaults.set(["Q"], forKey: "selectedRoutes")
        partialDefaults.set([TravelDirection.northbound.rawValue], forKey: "selectedDirections")
        partialDefaults.set("Q", forKey: "pinnedRoute")

        let partialModel = AppModel(defaults: partialDefaults)

        XCTAssertNil(partialModel.pinnedService)
        XCTAssertNil(partialDefaults.string(forKey: "pinnedRoute"))
    }

    func testPinnedPresentationFormatsRouteDirectionAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrival = Arrival(
            id: "q",
            routeID: "Q",
            stationID: "R16",
            stopID: "R16N",
            direction: .northbound,
            destination: "96 St",
            arrivalTime: now.addingTimeInterval(264.9)
        )

        let presentation = MenuBarPresentation.pinned(
            service: PinnedService(routeID: "Q", direction: .northbound),
            arrival: arrival,
            now: now
        )

        XCTAssertEqual(presentation.text, "Q ↑ 4:24")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Q train uptown, arriving in 4 minutes 24 seconds"
        )
    }

    func testPinnedPresentationShowsUnavailableWithoutArrival() {
        let presentation = MenuBarPresentation.pinned(
            service: PinnedService(routeID: "Q", direction: .southbound),
            arrival: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(presentation.text, "Q ↓ --:--")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Q train downtown, no upcoming arrival"
        )
    }

    func testUnpinnedModelUsesIconPresentation() {
        let model = AppModel(defaults: makeDefaults())

        XCTAssertEqual(model.menuBarPresentation, .icon)
    }

    func testPinnedPresentationUpdatesAsNowAdvances() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = PinnedService(routeID: "Q", direction: .northbound)
        let arrival = Arrival(
            id: "q",
            routeID: "Q",
            stationID: "R16",
            stopID: "R16N",
            direction: .northbound,
            destination: "96 St",
            arrivalTime: now.addingTimeInterval(65)
        )

        let first = MenuBarPresentation.pinned(service: service, arrival: arrival, now: now)
        let second = MenuBarPresentation.pinned(
            service: service,
            arrival: arrival,
            now: now.addingTimeInterval(1)
        )

        XCTAssertEqual(first.text, "Q ↑ 1:05")
        XCTAssertEqual(second.text, "Q ↑ 1:04")
    }

    func testPartialFeedSnapshotRetainsFutureArrivalsForMissingRoutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cachedQ = makeArrival(id: "cached-q", route: "Q", time: now.addingTimeInterval(120))
        let expiredQ = makeArrival(id: "expired-q", route: "Q", time: now.addingTimeInterval(-1))
        let cachedN = makeArrival(id: "cached-n", route: "N", time: now.addingTimeInterval(180))
        let refreshedN = makeArrival(id: "fresh-n", route: "N", time: now.addingTimeInterval(240))
        let snapshot = FeedSnapshot(
            arrivals: [refreshedN],
            fetchedAt: now,
            failedFeedCount: 1,
            failedRouteIDs: ["Q"]
        )

        let result = ArrivalCache.merging(
            previous: [cachedQ, expiredQ, cachedN],
            snapshot: snapshot
        )

        XCTAssertEqual(result.map(\.id), ["cached-q", "fresh-n"])
    }

    func testCompleteFeedSnapshotReplacesCachedArrivals() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cachedQ = makeArrival(id: "cached-q", route: "Q", time: now.addingTimeInterval(120))
        let refreshedN = makeArrival(id: "fresh-n", route: "N", time: now.addingTimeInterval(240))
        let snapshot = FeedSnapshot(
            arrivals: [refreshedN],
            fetchedAt: now,
            failedFeedCount: 0
        )

        let result = ArrivalCache.merging(previous: [cachedQ], snapshot: snapshot)

        XCTAssertEqual(result.map(\.id), ["fresh-n"])
    }

    func testPartialFailureElsewhereDoesNotRetainPinnedRouteCache() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cachedQ = makeArrival(id: "cached-q", route: "Q", time: now.addingTimeInterval(120))
        let refreshedN = makeArrival(id: "fresh-n", route: "N", time: now.addingTimeInterval(240))
        let snapshot = FeedSnapshot(
            arrivals: [refreshedN],
            fetchedAt: now,
            failedFeedCount: 1,
            failedRouteIDs: ["A", "C", "E"]
        )

        let result = ArrivalCache.merging(previous: [cachedQ], snapshot: snapshot)

        XCTAssertEqual(result.map(\.id), ["fresh-n"])
    }

    func testDeniedLocationDoesNotPermitPinnedArrivalResolution() {
        XCTAssertFalse(CLAuthorizationStatus.denied.allowsStandClearLocation)
        XCTAssertFalse(CLAuthorizationStatus.restricted.allowsStandClearLocation)
        XCTAssertTrue(CLAuthorizationStatus.authorized.allowsStandClearLocation)
        XCTAssertTrue(CLAuthorizationStatus.authorizedAlways.allowsStandClearLocation)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(1, forKey: "selectionOnboardingVersion")
        defaults.set(true, forKey: "hasConfiguredLines")
        return defaults
    }

    private func makeArrival(id: String, route: String, time: Date) -> Arrival {
        Arrival(
            id: id,
            routeID: route,
            stationID: "R16",
            stopID: "R16N",
            direction: .northbound,
            destination: "96 St",
            arrivalTime: time
        )
    }

    private func makeTrainObservation(
        routeID: String,
        path: TrackPath,
        now: Date
    ) -> TrainObservation {
        let next = path.anchors[1]
        let id = TrainRunID(
            feedID: "test-feed",
            routeID: routeID,
            tripID: "120000_\(path.shapeID)",
            serviceDate: "20260722",
            startTime: "12:00:00"
        )
        return TrainObservation(
            id: id,
            entityIDs: ["entity"],
            directionID: path.directionIDs.first,
            nyctDirection: .northbound,
            destination: "Test destination",
            isAssigned: true,
            nyctTrainID: nil,
            feedTimestamp: now,
            tripUpdateTimestamp: now,
            stops: [
                TrainStopObservation(
                    stopID: next.stopID,
                    stopSequence: next.sequence,
                    arrivalTime: now.addingTimeInterval(60),
                    departureTime: now.addingTimeInterval(75),
                    isSkipped: false,
                    scheduledTrack: nil,
                    actualTrack: nil
                ),
            ],
            vehicle: nil
        )
    }
}

private actor SnapshotClient: SystemFeedFetching {
    private var snapshots: [SystemFeedSnapshot]

    init(snapshots: [SystemFeedSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchSystemSnapshot(catalog: StationCatalog, now: Date) async throws -> SystemFeedSnapshot {
        guard !snapshots.isEmpty else { throw MTAFeedError.allFeedsFailed }
        return snapshots.removeFirst()
    }
}

private struct FixedGeometryLoader: TrackGeometryLoading {
    let catalog: TrackGeometryCatalog

    func load() throws -> TrackGeometryCatalog { catalog }
}

private struct FailingGeometryLoader: TrackGeometryLoading {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Test geometry failed." }
    }

    func load() throws -> TrackGeometryCatalog { throw Failure() }
}
