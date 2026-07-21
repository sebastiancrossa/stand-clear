@testable import StandClear
import CoreLocation
import StandClearCore
import XCTest

@MainActor
final class AppModelTests: XCTestCase {
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
}
