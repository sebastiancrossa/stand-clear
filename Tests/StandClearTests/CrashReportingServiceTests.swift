@testable import StandClear
import XCTest

@MainActor
final class CrashReportingServiceTests: XCTestCase {
    func testDefaultsToEnabledWhenKeyIsAbsent() {
        let defaults = makeDefaults()
        let service = SentryCrashReportingService(defaults: defaults)

        XCTAssertTrue(service.isEnabled)
        XCTAssertNil(defaults.object(forKey: "crashReportingEnabled"))
    }

    func testSetEnabledPersistsAndRoundTrips() {
        let defaults = makeDefaults()
        let service = SentryCrashReportingService(defaults: defaults)

        service.setEnabled(false)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "crashReportingEnabled") as? Bool, false)

        service.setEnabled(true)
        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "crashReportingEnabled") as? Bool, true)
    }

    func testFreshServiceReadsPersistedValue() {
        let defaults = makeDefaults()
        let first = SentryCrashReportingService(defaults: defaults)
        first.setEnabled(false)

        let second = SentryCrashReportingService(defaults: defaults)
        XCTAssertFalse(second.isEnabled)
    }

    func testStartIsSafeWhenDSNIsAbsent() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "crashReportingEnabled")
        let service = SentryCrashReportingService(defaults: defaults)

        // Test bundle has no SentryDSN, so start must no-op rather than throw.
        service.start()
        XCTAssertTrue(service.isEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CrashReportingServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
