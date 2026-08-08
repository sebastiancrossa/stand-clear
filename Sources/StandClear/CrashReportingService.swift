import Foundation
import Sentry

@MainActor
protocol CrashReporting: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    func start()
}

/// Owns the crash-reporting preference and starts Sentry when enabled.
///
/// Preference is stored here rather than in `AppModel` because the SDK must start
/// before the model exists, and so a Settings toggle mutates the same instance that
/// launched the SDK. No-ops if `SentryDSN` is missing from Info.plist.
@MainActor
final class SentryCrashReportingService: CrashReporting {
    private static let defaultsKey = "crashReportingEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        defaults.set(enabled, forKey: Self.defaultsKey)
        if enabled {
            startSDKIfConfigured()
        } else {
            SentrySDK.close()
        }
    }

    func start() {
        guard isEnabled else { return }
        startSDKIfConfigured()
    }

    private func startSDKIfConfigured() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !dsn.isEmpty else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            options.environment = Self.isDebugBuild ? "development" : "production"
            options.sendDefaultPii = false
        }
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Test double that keeps the crash-reporting preference in memory.
@MainActor
final class PreviewCrashReportingService: CrashReporting {
    private(set) var isEnabled: Bool
    private(set) var didStart = false
    private(set) var setEnabledCallCount = 0

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        setEnabledCallCount += 1
        isEnabled = enabled
    }

    func start() {
        didStart = true
    }
}
