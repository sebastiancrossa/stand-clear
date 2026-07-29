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
        model.setLiveMapActive(true)
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

    func testRefreshHidesAssignedPredepartureTrainAndReportsWaitingCoverage() async throws {
        let now = Date()
        let geometry = try TrackGeometryCatalog.bundled()
        let path = try XCTUnwrap(geometry.resource.paths.first(where: { $0.anchors.count >= 2 }))
        let routeID = try XCTUnwrap(path.routeIDs.first)
        let observation = makeTrainObservation(
            routeID: routeID,
            path: path,
            now: now,
            hasActiveEvidence: false
        )
        let client = SnapshotClient(snapshots: [
            SystemFeedSnapshot(
                arrivals: [],
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
        ])
        let model = AppModel(
            client: client,
            defaults: makeDefaults(),
            geometryLoader: FixedGeometryLoader(catalog: geometry)
        )
        model.setLiveMapActive(true)
        await model.loadMapGeometry()

        await model.refresh()

        XCTAssertTrue(model.mapMotionPlans.isEmpty)
        XCTAssertEqual(model.mapProjectionCoverage.predepartureObservationCount, 1)
        XCTAssertEqual(model.mapProjectionCoverage.eligibleObservationCount, 0)
        XCTAssertEqual(model.mapProjectionCoverage.unplacedTrainCount, 0)
    }

    func testReleaseMapResourcesClearsGeometryAndTrainState() async throws {
        let now = Date()
        let geometry = try TrackGeometryCatalog.bundled()
        let path = try XCTUnwrap(geometry.resource.paths.first(where: { $0.anchors.count >= 2 }))
        let routeID = try XCTUnwrap(path.routeIDs.first)
        let observation = makeTrainObservation(routeID: routeID, path: path, now: now)
        let client = SnapshotClient(snapshots: [
            SystemFeedSnapshot(
                arrivals: [],
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
        ])
        let model = AppModel(
            client: client,
            defaults: makeDefaults(),
            geometryLoader: FixedGeometryLoader(catalog: geometry)
        )
        model.setLiveMapActive(true)
        await model.loadMapGeometry()
        await model.refresh()
        XCTAssertNotNil(model.mapGeometry)
        XCTAssertFalse(model.mapMotionPlans.isEmpty)
        _ = model.mapStations

        model.setLiveMapActive(false)

        XCTAssertNil(model.mapGeometry)
        XCTAssertTrue(model.mapMotionPlans.isEmpty)
        XCTAssertEqual(model.mapProjectionCoverage, .empty)
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
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults)

        XCTAssertTrue(model.showsMinutesAndSeconds)
        XCTAssertEqual(model.arrivalTimeDisplayMode, .minutesAndSeconds)

        model.toggleArrivalTimeDisplay()
        XCTAssertFalse(model.showsMinutesAndSeconds)
        XCTAssertEqual(model.arrivalTimeDisplayMode, .wholeMinutes)
        XCTAssertEqual(defaults.string(forKey: "arrivalTimeDisplayMode"), "wholeMinutes")

        model.toggleArrivalTimeDisplay()
        XCTAssertTrue(model.showsMinutesAndSeconds)
        XCTAssertEqual(model.arrivalTimeDisplayMode, .minutesAndSeconds)
        XCTAssertEqual(defaults.string(forKey: "arrivalTimeDisplayMode"), "minutesAndSeconds")
    }

    /// Setup no longer asks for a format, so a rider who has never touched the setting
    /// gets the countdown the menu bar already speaks in.
    func testArrivalTimePreferenceDefaultAndInvalidValueFallBackToTheCountdown() {
        let defaults = makeDefaults()

        var model = AppModel(defaults: defaults)

        XCTAssertEqual(model.arrivalTimeDisplayMode, .minutesAndSeconds)

        defaults.set("tenthsOfASecond", forKey: "arrivalTimeDisplayMode")
        model = AppModel(defaults: defaults)

        XCTAssertEqual(model.arrivalTimeDisplayMode, .minutesAndSeconds)
    }

    func testArrivalTimePreferencePersistsAndRestores() {
        let defaults = makeDefaults()
        var model = AppModel(defaults: defaults)

        model.setArrivalTimeDisplayMode(.wholeMinutes)

        XCTAssertEqual(defaults.string(forKey: "arrivalTimeDisplayMode"), "wholeMinutes")

        model = AppModel(defaults: defaults)

        XCTAssertEqual(model.arrivalTimeDisplayMode, .wholeMinutes)
        XCTAssertFalse(model.showsMinutesAndSeconds)
    }

    func testConfiguredSelectionPreventsRemovingTheFinalRoute() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        XCTAssertTrue(model.hasConfiguredSelection)
        XCTAssertFalse(model.canToggleRoute("Q"))

        model.toggleRoute("Q")

        XCTAssertEqual(model.selectedRoutes, ["Q"])
        XCTAssertEqual(defaults.stringArray(forKey: "selectedRoutes"), ["Q"])
    }

    func testConfiguredSelectionAllowsRemovingOneOfMultipleRoutes() {
        let defaults = makeDefaults()
        defaults.set(["N", "Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        XCTAssertTrue(model.canToggleRoute("Q"))

        model.toggleRoute("Q")

        XCTAssertEqual(model.selectedRoutes, ["N"])
        XCTAssertTrue(model.hasConfiguredSelection)
    }

    func testSelectingConflictingVocabularyReplacesTheSelection() {
        let defaults = makeDefaults()
        defaults.set(["Q", "N"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.currentVocabulary, .uptownDowntown)

        model.toggleRoute("7")

        XCTAssertEqual(model.selectedRoutes, ["7"])
        XCTAssertEqual(model.currentVocabulary, .queensManhattan)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedRoutes"), ["7"])
        XCTAssertEqual(model.selectedDirection, .northbound)
    }

    func testSelectingCompatibleVocabularyAddsToTheSelection() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        model.toggleRoute("N")

        XCTAssertEqual(model.selectedRoutes, ["N", "Q"])
        XCTAssertEqual(model.currentVocabulary, .uptownDowntown)
    }

    func testMigratesPersistedConflictingVocabularyOnLoad() {
        let defaults = makeDefaults()
        defaults.set(["Q", "7"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedRoutes, ["Q"])
        XCTAssertEqual(model.currentVocabulary, .uptownDowntown)
        XCTAssertEqual(defaults.stringArray(forKey: "selectedRoutes"), ["Q"])
        XCTAssertEqual(model.selectedDirection, .southbound)
    }

    func testCurrentVocabularyFollowsSpecialLineSelection() {
        let defaults = makeDefaults()
        defaults.set(["L"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.currentVocabulary, .manhattanBrooklyn)
        XCTAssertEqual(model.currentVocabulary.title(for: .northbound), "MANHATTAN")
        XCTAssertEqual(model.currentVocabulary.glyph(for: .northbound), "←")
    }

    func testSelectingTheOtherDirectionReplacesItRatherThanAddingIt() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        model.selectDirection(.southbound)

        XCTAssertEqual(model.selectedDirection, .southbound)
        XCTAssertEqual(defaults.string(forKey: "selectedDirection"), "southbound")
        XCTAssertTrue(model.hasConfiguredSelection)
    }

    func testSelectingTheCurrentDirectionIsANoOp() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.togglePin()

        model.selectDirection(.northbound)

        XCTAssertEqual(model.selectedDirection, .northbound)
        XCTAssertTrue(model.isPinned)
    }

    func testUnselectableDirectionsAreRejected() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        model.selectDirection(.unknown)

        XCTAssertEqual(model.selectedDirection, .northbound)
    }

    func testSwappingDirectionFlipsItAndKeepsThePin() {
        // Every swap deselects the previous direction, so the pin has to follow the
        // selection rather than be cleared by it.
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.togglePin()

        model.swapDirection()

        XCTAssertEqual(model.selectedDirection, .southbound)
        XCTAssertTrue(model.isPinned)
        XCTAssertEqual(defaults.string(forKey: "selectedDirection"), "southbound")
        XCTAssertTrue(defaults.bool(forKey: "isPinned"))

        model.swapDirection()

        XCTAssertEqual(model.selectedDirection, .northbound)
        XCTAssertTrue(model.isPinned)
    }

    func testSwappingWithoutASelectedDirectionDoesNothing() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        let model = AppModel(defaults: defaults)

        model.swapDirection()

        XCTAssertNil(model.selectedDirection)
    }

    func testOnboardingRequiresADirectionAndARouteBeforeFinishing() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        let model = AppModel(defaults: defaults)
        let routeID = try XCTUnwrap(model.availableRoutes.first)

        XCTAssertTrue(model.isOnboarding)
        XCTAssertNil(model.selectedDirection)
        XCTAssertFalse(model.hasUsableSelection)

        model.selectDirection(.northbound)
        XCTAssertFalse(model.hasUsableSelection)

        model.finishChoosingLines()
        XCTAssertTrue(model.isShowingSettings)
        XCTAssertFalse(defaults.bool(forKey: "hasConfiguredLines"))

        model.toggleRoute(routeID)
        XCTAssertTrue(model.hasUsableSelection)
    }

    func testOnboardingAllowsRoutesToBecomeEmptyButCannotFinish() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        defaults.set(["Q"], forKey: "selectedRoutes")
        let model = AppModel(defaults: defaults)

        XCTAssertTrue(model.isShowingSettings)
        XCTAssertFalse(model.hasConfiguredSelection)
        XCTAssertTrue(model.canToggleRoute("Q"))

        model.selectDirection(.northbound)
        model.toggleRoute("Q")
        model.finishChoosingLines()

        XCTAssertTrue(model.selectedRoutes.isEmpty)
        XCTAssertEqual(model.selectedDirection, .northbound)
        XCTAssertTrue(model.isShowingSettings)
        XCTAssertFalse(defaults.bool(forKey: "hasConfiguredLines"))
    }

    func testCorruptConfiguredDefaultsRemainInOnboardingUntilFinished() throws {
        let defaults = makeDefaults()
        defaults.set(["NOT-A-ROUTE"], forKey: "selectedRoutes")
        defaults.set("sideways", forKey: "selectedDirection")

        let model = AppModel(defaults: defaults)
        let routeID = try XCTUnwrap(model.availableRoutes.first)

        XCTAssertNil(model.selectedDirection)
        XCTAssertFalse(model.hasConfiguredSelection)
        XCTAssertTrue(model.isShowingSettings)
        XCTAssertTrue(model.isOnboarding)

        model.toggleRoute(routeID)
        model.selectDirection(.northbound)

        XCTAssertTrue(model.hasConfiguredSelection)
        XCTAssertTrue(model.isShowingSettings)
        XCTAssertTrue(model.isOnboarding)
        XCTAssertTrue(model.canToggleRoute(routeID))

        model.toggleRoute(routeID)

        XCTAssertFalse(model.hasUsableSelection)
        XCTAssertTrue(model.isOnboarding)
    }

    func testFinishingOnboardingRecordsCompletionAndReturnsToArrivals() throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        defaults.set(0, forKey: "selectionOnboardingVersion")
        let model = AppModel(defaults: defaults)
        let routeID = try XCTUnwrap(model.availableRoutes.first)

        model.toggleRoute(routeID)
        model.selectDirection(.northbound)
        model.finishChoosingLines()

        XCTAssertTrue(model.hasConfiguredSelection)
        XCTAssertFalse(model.isShowingSettings)
        XCTAssertFalse(model.isOnboarding)
        XCTAssertTrue(defaults.bool(forKey: "hasConfiguredLines"))
        XCTAssertEqual(defaults.integer(forKey: "selectionOnboardingVersion"), 1)
    }

    func testTogglingPinSetsAndPersistsIt() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")

        let model = AppModel(defaults: defaults)
        model.togglePin()

        XCTAssertTrue(model.isPinned)
        XCTAssertTrue(defaults.bool(forKey: "isPinned"))
    }

    func testTogglingActivePinClearsItAndItsPreferences() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)

        model.togglePin()
        model.togglePin()

        XCTAssertFalse(model.isPinned)
        XCTAssertFalse(defaults.bool(forKey: "isPinned"))
    }

    func testValidPinRestoresOnLaunch() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        defaults.set(true, forKey: "isPinned")

        let model = AppModel(defaults: defaults)

        XCTAssertTrue(model.isPinned)
        XCTAssertEqual(model.selectedDirection, .northbound)
    }

    func testPinCannotBeSetWithoutASelectedDirection() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        let model = AppModel(defaults: defaults)

        model.togglePin()

        XCTAssertFalse(model.isPinned)
    }

    func testStoredPinWithoutADirectionIsDiscarded() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(true, forKey: "isPinned")

        let model = AppModel(defaults: defaults)

        XCTAssertNil(model.selectedDirection)
        XCTAssertFalse(model.isPinned)
        XCTAssertEqual(model.menuBarPresentation, .icon)
    }

    func testPinSurvivesRemovingARoute() {
        // A pin covers the whole direction, not one fixed route, so it should
        // keep tracking whichever selected route is soonest rather than clear.
        let defaults = makeDefaults()
        defaults.set(["N", "Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.togglePin()

        model.toggleRoute("Q")

        XCTAssertEqual(model.selectedRoutes, ["N"])
        XCTAssertTrue(model.isPinned)
        XCTAssertTrue(defaults.bool(forKey: "isPinned"))
    }

    func testClearPinRemovesPersistedPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.northbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.togglePin()

        model.clearPin()

        XCTAssertFalse(model.isPinned)
        XCTAssertFalse(defaults.bool(forKey: "isPinned"))
    }

    // MARK: - Migration off the multi-direction model

    func testMigrationKeepsASingleStoredDirectionAndRemovesLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.southbound.rawValue], forKey: "selectedDirections")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedDirection, .southbound)
        XCTAssertEqual(defaults.string(forKey: "selectedDirection"), "southbound")
        XCTAssertNil(defaults.stringArray(forKey: "selectedDirections"))
        XCTAssertNil(defaults.string(forKey: "pinnedDirection"))
    }

    func testMigrationResolvesBothDirectionsUsingTheStoredPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(
            [TravelDirection.northbound.rawValue, TravelDirection.southbound.rawValue],
            forKey: "selectedDirections"
        )
        defaults.set(TravelDirection.southbound.rawValue, forKey: "pinnedDirection")

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedDirection, .southbound)
        XCTAssertTrue(model.isPinned)
        XCTAssertTrue(defaults.bool(forKey: "isPinned"))
    }

    func testMigrationFallsBackToNorthboundWhenBothWereSelectedWithoutAPin() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(
            [TravelDirection.northbound.rawValue, TravelDirection.southbound.rawValue],
            forKey: "selectedDirections"
        )

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedDirection, .northbound)
        XCTAssertFalse(model.isPinned)
    }

    func testMigrationDiscardsUnusableLegacyValues() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set([TravelDirection.unknown.rawValue], forKey: "selectedDirections")
        defaults.set("not-a-direction", forKey: "pinnedDirection")

        let model = AppModel(defaults: defaults)

        XCTAssertNil(model.selectedDirection)
        XCTAssertFalse(model.isPinned)
        XCTAssertFalse(model.hasUsableSelection)
        XCTAssertNil(defaults.stringArray(forKey: "selectedDirections"))
    }

    func testMigrationPreservesSavedRoutesAndOnboardingVersion() {
        // Bumping selectionOnboardingVersion would have reset routes too, which is
        // why the migration is silent instead.
        let defaults = makeDefaults()
        defaults.set(["N", "Q"], forKey: "selectedRoutes")
        defaults.set(
            [TravelDirection.northbound.rawValue, TravelDirection.southbound.rawValue],
            forKey: "selectedDirections"
        )

        let model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedRoutes, ["N", "Q"])
        XCTAssertTrue(model.hasConfiguredSelection)
        XCTAssertEqual(defaults.integer(forKey: "selectionOnboardingVersion"), 1)
    }

    func testMigrationRunsOnceAndDoesNotOverrideALaterChoice() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(
            [TravelDirection.northbound.rawValue, TravelDirection.southbound.rawValue],
            forKey: "selectedDirections"
        )
        var model = AppModel(defaults: defaults)
        XCTAssertEqual(model.selectedDirection, .northbound)

        model.selectDirection(.southbound)
        model = AppModel(defaults: defaults)

        XCTAssertEqual(model.selectedDirection, .southbound)
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
            direction: .northbound,
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
        // With no arrival resolved, there's no route to attribute the pin to yet.
        let presentation = MenuBarPresentation.pinned(
            direction: .southbound,
            arrival: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(presentation.text, "↓ --:--")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "downtown trains, no upcoming arrival"
        )
    }

    func testUnpinnedModelUsesIconPresentation() {
        let model = AppModel(defaults: makeDefaults())

        XCTAssertEqual(model.menuBarPresentation, .icon)
    }

    func testWalkTimePreferencesPersistAcrossLaunches() {
        let defaults = makeDefaults()
        let first = AppModel(
            defaults: defaults,
            launchAtLogin: PreviewLaunchAtLoginService()
        )
        first.setWalkingPace(.brisk)
        first.setPlatformBufferSeconds(120)
        first.setStationWalkOverride(stationID: "R16", seconds: 240)
        first.setReachabilityEnabled(false)
        first.setMenuBarDisplayMode(.iconAndCountdown)
        first.setMenuBarShowRouteColor(false)
        first.setMenuBarHideWhenIdle(true)
        first.setMenuBarUrgencyEnabled(false)

        let second = AppModel(
            defaults: defaults,
            launchAtLogin: PreviewLaunchAtLoginService()
        )
        XCTAssertEqual(second.walkingPace, .brisk)
        XCTAssertEqual(second.platformBufferSeconds, 120)
        XCTAssertEqual(second.stationWalkOverrides["R16"], 240)
        XCTAssertFalse(second.reachabilityEnabled)
        XCTAssertEqual(second.menuBarDisplayMode, .iconAndCountdown)
        XCTAssertFalse(second.menuBarShowRouteColor)
        XCTAssertTrue(second.menuBarHideWhenIdle)
        XCTAssertFalse(second.menuBarUrgencyEnabled)
    }

    /// Setup asks for a direction and lines and nothing else. Launch at login is a
    /// General setting in the Settings window, so finishing setup must not register it.
    func testOnboardingFinishLeavesLaunchAtLoginToSettings() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "selectionOnboardingVersion")
        defaults.set(false, forKey: "hasConfiguredLines")
        let login = PreviewLaunchAtLoginService()
        let model = AppModel(defaults: defaults, launchAtLogin: login)
        model.selectDirection(.northbound)
        model.toggleRoute("Q")

        model.finishChoosingLines()

        XCTAssertFalse(login.isEnabled)
        XCTAssertFalse(model.isOnboarding)

        model.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(login.isEnabled)
        XCTAssertTrue(model.isLaunchAtLoginEnabled)
    }

    func testPinnedPresentationHideWhenIdleFallsBackToIcon() {
        let presentation = MenuBarPresentation.pinned(
            direction: .southbound,
            arrival: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000),
            hideWhenIdle: true
        )

        XCTAssertEqual(presentation, .icon)
    }

    func testPinnedPresentationUpdatesAsNowAdvances() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrival = Arrival(
            id: "q",
            routeID: "Q",
            stationID: "R16",
            stopID: "R16N",
            direction: .northbound,
            destination: "96 St",
            arrivalTime: now.addingTimeInterval(65)
        )

        let first = MenuBarPresentation.pinned(direction: .northbound, arrival: arrival, now: now)
        let second = MenuBarPresentation.pinned(
            direction: .northbound,
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

    func testRefreshAlertsStoresTheFetchedAlerts() async {
        let defaults = makeDefaults()
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(alerts: [makeAlert(id: "a", routeIDs: ["Q"])], fetchedAt: .now),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)

        await model.refreshAlerts()

        XCTAssertEqual(model.allAlerts.map(\.id), ["a"])
    }

    /// The alert feed is a separate request on a separate clock. When it dies the board
    /// has to keep working, and `feedWarning` must stay reserved for the arrival feeds.
    func testFailedAlertFetchLeavesTheBoardAndItsWarningAlone() async {
        let defaults = makeDefaults()
        let alertsClient = AlertsSnapshotClient(snapshots: [])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)

        await model.refreshAlerts()

        XCTAssertTrue(model.allAlerts.isEmpty)
        XCTAssertNil(model.feedWarning)
    }

    func testFailedAlertFetchKeepsThePreviouslyFetchedAlerts() async {
        let defaults = makeDefaults()
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(alerts: [makeAlert(id: "a", routeIDs: ["Q"])], fetchedAt: .now),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)

        await model.refreshAlerts()
        await model.refreshAlerts()

        XCTAssertEqual(model.allAlerts.map(\.id), ["a"])
    }

    /// The strip requires a line selection. With none selected, active alerts stay empty
    /// even though line-wide badges still light for every available route.
    func testAlertsAreNotSurfacedWithoutALineSelection() async {
        let defaults = makeDefaults()
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(alerts: [makeAlert(id: "a", routeIDs: ["Q"])], fetchedAt: .now),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)

        await model.refreshAlerts()

        XCTAssertFalse(model.allAlerts.isEmpty)
        XCTAssertTrue(model.activeAlerts.isEmpty)
        XCTAssertFalse(model.hasAlertAtNearestStation)
        XCTAssertEqual(model.alertedRouteIDs, ["Q"])
    }

    /// A selected line's distant alert still surfaces on the strip with no location fix.
    /// Local-station copy stays false because there is no nearest station to claim.
    func testSelectedLineDistantAlertSurfacesWithoutANearestStation() async {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(
                alerts: [makeAlert(id: "a", routeIDs: ["Q"], stationIDs: ["R01"])],
                fetchedAt: .now
            ),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)

        await model.refreshAlerts()

        XCTAssertEqual(model.activeAlerts.map(\.id), ["a"])
        XCTAssertFalse(model.hasAlertAtNearestStation)
        XCTAssertEqual(model.alertedRouteIDs, ["Q"])
    }

    /// Settings badges are line-wide and selection-agnostic: an alert naming a station
    /// the rider is not at still lights the badge, and deselecting the line does not
    /// hide it. The board strip stays selection-filtered via `activeAlerts`.
    func testAlertBadgesIncludeUnselectedRoutesWithDistantAlerts() async {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(
                alerts: [makeAlert(id: "n-delay", routeIDs: ["N"], stationIDs: ["R01"])],
                fetchedAt: .now
            ),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "R16", name: "Times Sq-42 St", latitude: 40.75, longitude: -73.99),
                distance: 50
            ),
        ])

        await model.refreshAlerts()

        XCTAssertEqual(model.selectedRoutes, ["Q"])
        XCTAssertTrue(model.activeAlerts.isEmpty)
        XCTAssertFalse(model.hasAlertAtNearestStation)
        XCTAssertEqual(model.alertedRouteIDs, ["N"])
    }

    func testHasAlertAtNearestStationIsTrueForALocalAlert() async {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(
                alerts: [makeAlert(id: "local", routeIDs: ["Q"], stationIDs: ["R16"])],
                fetchedAt: .now
            ),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "R16", name: "Times Sq-42 St", latitude: 40.75, longitude: -73.99),
                distance: 50
            ),
        ])

        await model.refreshAlerts()

        XCTAssertEqual(model.activeAlerts.map(\.id), ["local"])
        XCTAssertTrue(model.hasAlertAtNearestStation)
    }

    func testHasAlertAtNearestStationIsFalseForADistantAlert() async {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let alertsClient = AlertsSnapshotClient(snapshots: [
            ServiceAlertSnapshot(
                alerts: [makeAlert(id: "distant", routeIDs: ["Q"], stationIDs: ["R01"])],
                fetchedAt: .now
            ),
        ])
        let model = AppModel(alertsClient: alertsClient, defaults: defaults)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "R16", name: "Times Sq-42 St", latitude: 40.75, longitude: -73.99),
                distance: 50
            ),
        ])

        await model.refreshAlerts()

        XCTAssertEqual(model.activeAlerts.map(\.id), ["distant"])
        XCTAssertFalse(model.hasAlertAtNearestStation)
    }

    func testDeniedLocationDoesNotPermitPinnedArrivalResolution() {
        XCTAssertFalse(CLAuthorizationStatus.denied.allowsStandClearLocation)
        XCTAssertFalse(CLAuthorizationStatus.restricted.allowsStandClearLocation)
        XCTAssertFalse(CLAuthorizationStatus.notDetermined.allowsStandClearLocation)
        XCTAssertTrue(CLAuthorizationStatus.authorizedAlways.allowsStandClearLocation)
    }

    func testStationExpansionIsAccordionAndResetsOnCollapse() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "A1", name: "Alpha", latitude: 40, longitude: -73),
                distance: 100
            ),
            NearbyStation(
                station: Station(id: "B2", name: "Beta", latitude: 40.01, longitude: -73),
                distance: 200
            ),
        ])

        model.toggleStationExpanded("A1")
        XCTAssertEqual(model.expandedStationID, "A1")

        model.toggleStationExpanded("B2")
        XCTAssertEqual(model.expandedStationID, "B2")

        model.toggleStationExpanded("B2")
        XCTAssertNil(model.expandedStationID)

        model.toggleStationExpanded("A1")
        model.collapseExpandedStation()
        XCTAssertNil(model.expandedStationID)
    }

    func testStationExpansionIgnoresStationsNotOnTheBoard() {
        let defaults = makeDefaults()
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set(TravelDirection.southbound.rawValue, forKey: "selectedDirection")
        let model = AppModel(defaults: defaults)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "A1", name: "Alpha", latitude: 40, longitude: -73),
                distance: 100
            ),
        ])

        model.toggleStationExpanded("missing")

        XCTAssertNil(model.expandedStationID)
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

    private func makeAlert(
        id: String,
        alertType: String = "Delays",
        routeIDs: Set<String>,
        stationIDs: Set<String> = []
    ) -> ServiceAlert {
        ServiceAlert(
            id: id,
            alertType: alertType,
            headerText: "Header",
            routeIDs: routeIDs,
            stationIDs: stationIDs,
            activePeriods: []
        )
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
        now: Date,
        hasActiveEvidence: Bool = true
    ) -> TrainObservation {
        let next = hasActiveEvidence ? path.anchors[1] : path.anchors[0]
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
            vehicle: hasActiveEvidence
                ? TrainVehicleObservation(
                    entityID: "vehicle",
                    stopID: next.stopID,
                    stopSequence: next.sequence,
                    status: .inTransitTo,
                    timestamp: now
                )
                : nil
        )
    }
}

private actor SnapshotClient: SystemFeedFetching {
    private var snapshots: [SystemFeedSnapshot]

    init(snapshots: [SystemFeedSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date,
        routeIDs: Set<String>?,
        includeTrains: Bool
    ) async throws -> SystemFeedSnapshot {
        guard !snapshots.isEmpty else { throw MTAFeedError.allFeedsFailed }
        let snapshot = snapshots.removeFirst()
        if includeTrains {
            return snapshot
        }
        return SystemFeedSnapshot(
            arrivals: snapshot.arrivals,
            trains: [],
            fetchedAt: snapshot.fetchedAt,
            feedStatuses: snapshot.feedStatuses
        )
    }
}

private actor AlertsSnapshotClient: ServiceAlertFetching {
    private var snapshots: [ServiceAlertSnapshot]

    init(snapshots: [ServiceAlertSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchAlerts(catalog: StationCatalog, now: Date) async throws -> ServiceAlertSnapshot {
        guard !snapshots.isEmpty else { throw MTAAlertFeedError.invalidResponse }
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
