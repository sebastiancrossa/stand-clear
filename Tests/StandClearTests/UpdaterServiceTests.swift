import StandClearCore
import XCTest
@testable import StandClear

@MainActor
final class UpdaterServiceTests: XCTestCase {
    func testPreviewToggleRoundTrip() {
        let updater = PreviewUpdaterService(automaticallyChecksForUpdates: true)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)

        updater.setAutomaticallyChecksForUpdates(false)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)

        updater.setAutomaticallyChecksForUpdates(true)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    func testPreviewCheckForUpdatesAdoptsNextResult() {
        let updater = PreviewUpdaterService()
        updater.nextCheckResult = .available(version: "0.2.0")

        updater.checkForUpdates()

        XCTAssertEqual(updater.checkForUpdatesCallCount, 1)
        XCTAssertEqual(updater.state, .available(version: "0.2.0"))
        XCTAssertNotNil(updater.lastCheckDate)
    }

    func testPreviewRefreshUpdateInformationAdoptsNextResult() {
        let updater = PreviewUpdaterService()
        updater.nextCheckResult = .upToDate

        updater.refreshUpdateInformation()

        XCTAssertEqual(updater.refreshUpdateInformationCallCount, 1)
        XCTAssertEqual(updater.state, .upToDate)
    }

    func testAppModelHasPendingUpdateTracksUpdaterState() {
        let updater = PreviewUpdaterService(state: .idle)
        let model = AppModel(
            client: StubSystemFeedClient(),
            alertsClient: StubServiceAlertClient(),
            defaults: UserDefaults(suiteName: "UpdaterServiceTests.\(UUID().uuidString)")!,
            launchAtLogin: PreviewLaunchAtLoginService(),
            softwareUpdater: updater
        )

        XCTAssertFalse(model.hasPendingUpdate)

        updater.seedState(.available(version: "0.2.0"))
        XCTAssertTrue(model.hasPendingUpdate)

        updater.seedState(.upToDate)
        XCTAssertFalse(model.hasPendingUpdate)
    }

    func testAppModelStartStartsSoftwareUpdater() {
        let updater = PreviewUpdaterService()
        let model = AppModel(
            client: StubSystemFeedClient(),
            alertsClient: StubServiceAlertClient(),
            defaults: UserDefaults(suiteName: "UpdaterServiceTests.start.\(UUID().uuidString)")!,
            launchAtLogin: PreviewLaunchAtLoginService(),
            softwareUpdater: updater
        )

        model.start()

        XCTAssertTrue(updater.didStart)
    }

    func testAppModelTogglePassthrough() {
        let updater = PreviewUpdaterService(automaticallyChecksForUpdates: true)
        let model = AppModel(
            client: StubSystemFeedClient(),
            alertsClient: StubServiceAlertClient(),
            defaults: UserDefaults(suiteName: "UpdaterServiceTests.toggle.\(UUID().uuidString)")!,
            launchAtLogin: PreviewLaunchAtLoginService(),
            softwareUpdater: updater
        )

        XCTAssertTrue(model.isAutomaticUpdateChecksEnabled)
        model.setAutomaticUpdateChecksEnabled(false)
        XCTAssertFalse(model.isAutomaticUpdateChecksEnabled)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }
}

private final class StubSystemFeedClient: SystemFeedFetching {
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

private final class StubServiceAlertClient: ServiceAlertFetching {
    func fetchAlerts(
        catalog: StationCatalog,
        now: Date
    ) async throws -> ServiceAlertSnapshot {
        ServiceAlertSnapshot(alerts: [], fetchedAt: now)
    }
}
