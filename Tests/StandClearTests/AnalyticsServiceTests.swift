@testable import StandClear
import StandClearCore
import XCTest

@MainActor
final class AnalyticsServiceTests: XCTestCase {
    func testDefaultsToEnabledWhenKeyIsAbsent() {
        let defaults = makeDefaults()
        let service = PostHogAnalyticsService(defaults: defaults)

        XCTAssertTrue(service.isEnabled)
        XCTAssertNil(defaults.object(forKey: "analyticsEnabled"))
    }

    func testSetEnabledPersistsAndRoundTrips() {
        let defaults = makeDefaults()
        let service = PostHogAnalyticsService(defaults: defaults)

        service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "analyticsEnabled") as? Bool, false)

        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "analyticsEnabled") as? Bool, true)
    }

    func testSetEnabledIsIdempotent() {
        let defaults = makeDefaults()
        let service = PostHogAnalyticsService(defaults: defaults)

        service.setEnabled(true)
        XCTAssertNil(defaults.object(forKey: "analyticsEnabled"))

        service.setEnabled(false)
        service.setEnabled(false)
        XCTAssertEqual(defaults.object(forKey: "analyticsEnabled") as? Bool, false)
    }

    func testFreshServiceReadsPersistedValue() {
        let defaults = makeDefaults()
        let first = PostHogAnalyticsService(defaults: defaults)
        first.setEnabled(false)

        let second = PostHogAnalyticsService(defaults: defaults)
        XCTAssertFalse(second.isEnabled)
    }

    func testStartAndCaptureAreSafeWhenAPIKeyIsAbsent() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "analyticsEnabled")
        let service = PostHogAnalyticsService(defaults: defaults)

        // Test bundle has no PostHogAPIKey, so start and capture must no-op.
        service.start()
        service.capture(.boardOpened)
        XCTAssertTrue(service.isEnabled)
    }

    func testEveryEventHasASnakeCaseNameWithoutStationOrRouteProperties() {
        let events: [AnalyticsEvent] = [
            .appInstalled(existingUser: false),
            .setupCompleted(lineCount: 2),
            .boardOpened,
            .appActive,
            .directionSwitched(.northbound),
            .countdownPinned,
            .countdownUnpinned,
            .timeFormatChanged(.wholeMinutes),
            .stationExpanded,
            .liveMapOpened,
            .alertOpened,
            .settingsOpened(pane: "general"),
        ]

        for event in events {
            XCTAssertFalse(event.name.isEmpty, "missing name for \(event)")
            XCTAssertEqual(event.name, event.name.lowercased())
            XCTAssertFalse(event.name.contains(" "), "name should be snake_case: \(event.name)")
            XCTAssertTrue(event.name.contains("_"), "name should be snake_case: \(event.name)")
            for key in event.properties.keys {
                XCTAssertFalse(key.localizedCaseInsensitiveContains("station"), "\(event.name) has \(key)")
                XCTAssertFalse(key.localizedCaseInsensitiveContains("route"), "\(event.name) has \(key)")
            }
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AnalyticsServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
