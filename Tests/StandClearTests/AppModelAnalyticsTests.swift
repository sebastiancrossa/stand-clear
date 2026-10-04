@testable import StandClear
import StandClearCore
import XCTest

@MainActor
final class AppModelAnalyticsTests: XCTestCase {
    func testStartRecordsInstallAndDailyActiveOnce() {
        let defaults = makeConfiguredDefaults()
        let analytics = PreviewAnalyticsService()
        let first = makeModel(defaults: defaults, analytics: analytics)
        first.start()

        XCTAssertEqual(
            analytics.captured,
            [.appInstalled(existingUser: true), .appActive]
        )

        first.start()
        let second = makeModel(defaults: defaults, analytics: analytics)
        second.start()

        XCTAssertEqual(
            analytics.captured,
            [.appInstalled(existingUser: true), .appActive]
        )
    }

    func testInstallExistingUserFollowsHasConfiguredLines() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "hasConfiguredLines")
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)

        model.start()

        XCTAssertEqual(analytics.captured.first, .appInstalled(existingUser: false))
    }

    func testDailyActiveFiresOncePerDay() {
        let defaults = makeConfiguredDefaults()
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)
        model.start()
        analytics.resetCaptured()

        defaults.set("2000-01-01", forKey: "analyticsLastActiveDay")
        model.start()
        XCTAssertEqual(analytics.captured, [])

        let second = makeModel(defaults: defaults, analytics: analytics)
        second.start()
        XCTAssertEqual(analytics.captured, [.appActive])

        let third = makeModel(defaults: defaults, analytics: analytics)
        third.start()
        XCTAssertEqual(analytics.captured, [.appActive])
    }

    func testFeatureActionsRecordTheirEvents() {
        let defaults = makeConfiguredDefaults()
        defaults.set(["N", "Q"], forKey: "selectedRoutes")
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)

        model.setMenuPopoverActive(true)
        model.setLiveMapActive(true)
        model.selectDirection(.southbound)
        model.togglePin()
        model.clearPin()
        model.setArrivalTimeDisplayMode(.wholeMinutes)
        model.seedNearbyStationsForTesting([
            NearbyStation(
                station: Station(id: "A1", name: "Alpha", latitude: 40, longitude: -73),
                distance: 100
            ),
        ])
        model.toggleStationExpanded("A1")
        model.openSettings(section: .service)
        model.recordAlertsExpanded()
        model.recordSettingsPaneViewed(.about)

        XCTAssertEqual(
            analytics.captured,
            [
                .boardOpened,
                .liveMapOpened,
                .directionSwitched(.southbound),
                .countdownPinned,
                .countdownUnpinned,
                .timeFormatChanged(.wholeMinutes),
                .stationExpanded,
                .settingsOpened(pane: "lines"),
                .alertOpened,
                .settingsOpened(pane: "about"),
            ]
        )
    }

    func testSetupCompletedRecordsLineCount() throws {
        let defaults = makeDefaults()
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)
        let routeID = try XCTUnwrap(model.availableRoutes.first)

        model.selectDirection(.northbound)
        model.toggleRoute(routeID)
        model.finishChoosingLines()

        XCTAssertEqual(analytics.captured, [.setupCompleted(lineCount: 1)])
    }

    func testSelectingDirectionDuringOnboardingRecordsNothing() {
        let defaults = makeDefaults()
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)

        model.selectDirection(.northbound)

        XCTAssertEqual(analytics.captured, [])
    }

    func testActionsThatChangeNothingRecordNothing() {
        let defaults = makeConfiguredDefaults()
        let analytics = PreviewAnalyticsService()
        let model = makeModel(defaults: defaults, analytics: analytics)

        model.setMenuPopoverActive(false)
        model.setLiveMapActive(false)
        model.selectDirection(.northbound)
        model.togglePin()
        model.togglePin()
        analytics.resetCaptured()

        model.setMenuPopoverActive(false)
        model.setLiveMapActive(false)
        model.selectDirection(.northbound)
        model.clearPin()
        model.setArrivalTimeDisplayMode(.minutesAndSeconds)
        model.toggleStationExpanded("missing")

        XCTAssertEqual(analytics.captured, [])
    }

    func testDisabledAnalyticsRecordsNothing() {
        let defaults = makeConfiguredDefaults()
        let analytics = PreviewAnalyticsService(isEnabled: false)
        let model = makeModel(defaults: defaults, analytics: analytics)

        model.start()
        model.setMenuPopoverActive(true)
        model.setLiveMapActive(true)
        model.selectDirection(.southbound)
        model.togglePin()
        model.setArrivalTimeDisplayMode(.wholeMinutes)
        model.openSettings(section: .service)
        model.recordAlertsExpanded()
        model.recordSettingsPaneViewed(.general)

        XCTAssertEqual(analytics.captured, [])
        XCTAssertTrue(defaults.bool(forKey: "analyticsInstallRecorded"))
    }

    func testAppModelTogglePassthrough() {
        let analytics = PreviewAnalyticsService(isEnabled: true)
        let model = makeModel(defaults: makeConfiguredDefaults(), analytics: analytics)

        XCTAssertTrue(model.isAnalyticsEnabled)
        model.setAnalyticsEnabled(false)
        XCTAssertFalse(model.isAnalyticsEnabled)
        XCTAssertFalse(analytics.isEnabled)
    }

    private func makeModel(
        defaults: UserDefaults,
        analytics: PreviewAnalyticsService
    ) -> AppModel {
        AppModel(
            client: StubAnalyticsFeedClient(),
            alertsClient: StubAnalyticsAlertClient(),
            defaults: defaults,
            launchAtLogin: PreviewLaunchAtLoginService(),
            softwareUpdater: PreviewUpdaterService(),
            crashReporter: PreviewCrashReportingService(),
            analytics: analytics
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppModelAnalyticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeConfiguredDefaults() -> UserDefaults {
        let defaults = makeDefaults()
        defaults.set(1, forKey: "selectionOnboardingVersion")
        defaults.set(true, forKey: "hasConfiguredLines")
        defaults.set(["Q"], forKey: "selectedRoutes")
        defaults.set("northbound", forKey: "selectedDirection")
        return defaults
    }
}

private final class StubAnalyticsFeedClient: SystemFeedFetching {
    func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date,
        routeIDs: Set<String>?,
        includeTrains: Bool
    ) async throws -> SystemFeedSnapshot {
        SystemFeedSnapshot(
            arrivals: [],
            trains: [],
            fetchedAt: now,
            feedStatuses: []
        )
    }
}

private final class StubAnalyticsAlertClient: ServiceAlertFetching {
    func fetchAlerts(
        catalog: StationCatalog,
        now: Date
    ) async throws -> ServiceAlertSnapshot {
        ServiceAlertSnapshot(alerts: [], fetchedAt: now)
    }
}
