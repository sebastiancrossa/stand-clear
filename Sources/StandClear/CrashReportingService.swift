import Foundation
import Sentry

/// Starts Sentry so crashes and uncaught errors surface with a stack trace and the
/// app version that produced them. No-ops if `SentryDSN` is missing from Info.plist,
/// so local/ad-hoc builds without a DSN configured stay silent.
enum CrashReportingService {
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !dsn.isEmpty else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            options.environment = isDebugBuild ? "development" : "production"
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
