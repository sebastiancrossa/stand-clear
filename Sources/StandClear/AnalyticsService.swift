import Foundation
import PostHog
import StandClearCore

enum AnalyticsEvent: Equatable {
    case appInstalled(existingUser: Bool)
    case setupCompleted(lineCount: Int)
    case boardOpened
    case appActive
    case directionSwitched(TravelDirection)
    case countdownPinned
    case countdownUnpinned
    case timeFormatChanged(ArrivalTimeDisplayMode)
    case stationExpanded
    case liveMapOpened
    case alertOpened
    case settingsOpened(pane: String)

    var name: String {
        switch self {
        case .appInstalled: "app_installed"
        case .setupCompleted: "setup_completed"
        case .boardOpened: "board_opened"
        case .appActive: "app_active"
        case .directionSwitched: "direction_switched"
        case .countdownPinned: "countdown_pinned"
        case .countdownUnpinned: "countdown_unpinned"
        case .timeFormatChanged: "time_format_changed"
        case .stationExpanded: "station_expanded"
        case .liveMapOpened: "live_map_opened"
        case .alertOpened: "alert_opened"
        case .settingsOpened: "settings_opened"
        }
    }

    var properties: [String: Any] {
        switch self {
        case let .appInstalled(existingUser):
            ["existing_user": existingUser]
        case let .setupCompleted(lineCount):
            ["line_count": lineCount]
        case .boardOpened, .appActive, .countdownPinned, .countdownUnpinned,
             .stationExpanded, .liveMapOpened, .alertOpened:
            [:]
        case let .directionSwitched(direction):
            ["direction": direction.rawValue]
        case let .timeFormatChanged(mode):
            ["mode": mode.rawValue]
        case let .settingsOpened(pane):
            ["pane": pane]
        }
    }
}

@MainActor
protocol AnalyticsTracking: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    func start()
    func capture(_ event: AnalyticsEvent)
}

/// Owns the usage-analytics preference and starts PostHog when enabled.
///
/// Preference is stored here rather than in `AppModel` because the SDK must start
/// before the model exists, and so a Settings toggle mutates the same instance that
/// launched the SDK. No-ops if `PostHogAPIKey` / `PostHogHost` are missing from
/// Info.plist, or in DEBUG builds.
@MainActor
final class PostHogAnalyticsService: AnalyticsTracking {
    private static let defaultsKey = "analyticsEnabled"

    private let defaults: UserDefaults
    private var isSDKStarted = false

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
            if isSDKStarted {
                PostHogSDK.shared.optIn()
            } else {
                startSDKIfConfigured()
            }
        } else if isSDKStarted {
            PostHogSDK.shared.optOut()
        }
    }

    func start() {
        guard isEnabled else { return }
        startSDKIfConfigured()
    }

    func capture(_ event: AnalyticsEvent) {
        guard isEnabled, isSDKStarted else { return }
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    private func startSDKIfConfigured() {
        guard !Self.isDebugBuild else { return }
        guard !isSDKStarted else { return }
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String,
              !apiKey.isEmpty,
              let host = Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String,
              !host.isEmpty
        else { return }

        let config = PostHogConfig(projectToken: apiKey, host: host)
        config.personProfiles = .never
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.enableSwizzling = false
        config.errorTrackingConfig.autoCapture = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.optIn()
        isSDKStarted = true
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// Test double that keeps the analytics preference and captured events in memory.
@MainActor
final class PreviewAnalyticsService: AnalyticsTracking {
    private(set) var isEnabled: Bool
    private(set) var didStart = false
    private(set) var captured: [AnalyticsEvent] = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func start() {
        didStart = true
    }

    func capture(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        captured.append(event)
    }

    func resetCaptured() {
        captured.removeAll()
    }
}
