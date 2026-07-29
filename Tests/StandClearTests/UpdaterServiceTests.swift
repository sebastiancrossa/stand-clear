import Sparkle
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

    // MARK: Abort classification

    /// The regression that put "Couldn't check for updates. You're up to date!" on screen in
    /// red: Sparkle signs off a successful, nothing-found check by aborting with this error.
    func testNoUpdateErrorIsNotAFailure() {
        let reason = SparkleAbortReason(sparkleError(.noUpdateError, description: "You’re up to date!"))

        XCTAssertEqual(reason, .noUpdateFound)
    }

    func testDeclinedInstallIsNotAFailure() {
        XCTAssertEqual(
            SparkleAbortReason(sparkleError(.installationCanceledError)),
            .userDeclinedInstall
        )
        XCTAssertEqual(
            SparkleAbortReason(sparkleError(.installationAuthorizeLaterError)),
            .userDeclinedInstall
        )
    }

    func testUnreachableFeedIsAFailure() {
        let reason = SparkleAbortReason(sparkleError(.downloadError, description: "No internet."))

        XCTAssertEqual(reason, .checkFailed("No internet."))
    }

    /// Sparkle surfaces `URLError`s and friends untranslated, so a foreign domain carrying
    /// code 1001 must not be mistaken for `SUNoUpdateError`.
    func testForeignErrorSharingANoUpdateCodeIsAFailure() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: Int(SUError.noUpdateError.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
        )

        XCTAssertEqual(SparkleAbortReason(error), .checkFailed("The request timed out."))
    }

    private func sparkleError(
        _ code: SUError,
        description: String = "Something went wrong."
    ) -> NSError {
        NSError(
            domain: SUSparkleErrorDomain,
            code: Int(code.rawValue),
            userInfo: [NSLocalizedDescriptionKey: description]
        )
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
