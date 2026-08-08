import AppKit
import Combine
import CoreLocation
import Foundation
import StandClearCore

protocol SystemFeedFetching {
    func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date,
        routeIDs: Set<String>?,
        includeTrains: Bool
    ) async throws -> SystemFeedSnapshot
}

extension MTAClient: SystemFeedFetching {}

protocol ServiceAlertFetching {
    func fetchAlerts(
        catalog: StationCatalog,
        now: Date
    ) async throws -> ServiceAlertSnapshot
}

extension MTAAlertsClient: ServiceAlertFetching {}

protocol TrackGeometryLoading: Sendable {
    func load() throws -> TrackGeometryCatalog
}

struct BundledTrackGeometryLoader: TrackGeometryLoading {
    func load() throws -> TrackGeometryCatalog {
        try TrackGeometryCatalog.bundled()
    }
}

enum ArrivalTimeDisplayMode: String, CaseIterable {
    case wholeMinutes
    case minutesAndSeconds
}

enum MenuBarDisplayMode: String, CaseIterable, Hashable {
    case iconOnly
    case countdownWhenPinned
    case iconAndCountdown

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .countdownWhenPinned: "Countdown"
        case .iconAndCountdown: "Icon & countdown"
        }
    }
}

enum SettingsSection: Equatable {
    case service
}

enum SettingsPresentation: Equatable {
    case hidden
    case settings(SettingsSection)
    case onboarding
}

enum AppSettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general
    case menuBar
    case walkTime
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .walkTime: "Walk Time"
        case .about: "About"
        }
    }

    /// The sidebar glyph. Every pane needs one, so this is a stored fact about the pane
    /// rather than a literal buried in the sidebar's row builder.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .walkTime: "figure.walk"
        case .about: "info.circle"
        }
    }

    /// The line under the pane title, saying what the pane decides. The window's own
    /// title bar already says "Settings", so the header names the pane instead of
    /// repeating it, and this is what keeps that header from being one bare word.
    var caption: String {
        switch self {
        case .general: "Startup, location access, and updates."
        case .menuBar: "What Stand Clear shows in the menu bar."
        case .walkTime: "How long it takes you to reach a platform."
        case .about: "Version, credits, and where the data comes from."
        }
    }
}

struct MenuBarPresentation: Equatable {
    enum Content: Equatable {
        case icon
        case text(String)
        case iconAndText(String)
    }

    let content: Content
    let accessibilityLabel: String
    let isUrgent: Bool
    let routeID: String?

    var text: String? {
        switch content {
        case let .text(text), let .iconAndText(text):
            return text
        case .icon:
            return nil
        }
    }

    static let icon = MenuBarPresentation(
        content: .icon,
        accessibilityLabel: "Stand Clear",
        isUrgent: false,
        routeID: nil
    )

    static func pinned(
        direction: TravelDirection,
        arrival: Arrival?,
        now: Date,
        displayMode: MenuBarDisplayMode = .countdownWhenPinned,
        hideWhenIdle: Bool = false,
        isUrgent: Bool = false,
        vocabulary: DirectionVocabulary = .uptownDowntown
    ) -> MenuBarPresentation {
        let arrow = vocabulary.glyph(for: direction)
        let accessibilityName = vocabulary.accessibilityName(for: direction)
        guard let arrival else {
            if hideWhenIdle || displayMode == .iconOnly {
                return .icon
            }
            let text = "\(arrow) --:--"
            return MenuBarPresentation(
                content: content(for: displayMode, text: text),
                accessibilityLabel: "\(accessibilityName) trains, no upcoming arrival",
                isUrgent: false,
                routeID: nil
            )
        }

        let route = RouteID.displayLabel(arrival.routeID)
        let remainingSeconds = max(0, Int(floor(arrival.arrivalTime.timeIntervalSince(now))))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let text = "\(route) \(arrow) \(arrival.etaMinutesSecondsText(relativeTo: now))"
        let urgencySuffix = isUrgent ? ", leave now" : ""
        if displayMode == .iconOnly {
            return MenuBarPresentation(
                content: .icon,
                accessibilityLabel: "\(route) train \(accessibilityName), arriving in "
                    + "\(minutes) \(minutes == 1 ? "minute" : "minutes") "
                    + "\(seconds) \(seconds == 1 ? "second" : "seconds")"
                    + urgencySuffix,
                isUrgent: isUrgent,
                routeID: arrival.routeID
            )
        }
        return MenuBarPresentation(
            content: content(for: displayMode, text: text),
            accessibilityLabel: "\(route) train \(accessibilityName), arriving in "
                + "\(minutes) \(minutes == 1 ? "minute" : "minutes") "
                + "\(seconds) \(seconds == 1 ? "second" : "seconds")"
                + urgencySuffix,
            isUrgent: isUrgent,
            routeID: arrival.routeID
        )
    }

    private static func content(for displayMode: MenuBarDisplayMode, text: String) -> Content {
        switch displayMode {
        case .iconOnly:
            return .icon
        case .countdownWhenPinned:
            return .text(text)
        case .iconAndCountdown:
            return .iconAndText(text)
        }
    }
}

enum ArrivalCache {
    static func merging(previous: [Arrival], snapshot: FeedSnapshot) -> [Arrival] {
        guard snapshot.failedFeedCount > 0 else { return snapshot.arrivals }

        // Fresh data replaces the snapshot while future arrivals covered by failed feeds
        // remain available until their scheduled time passes.
        var arrivalsByID = Dictionary(
            uniqueKeysWithValues: snapshot.arrivals.map { ($0.id, $0) }
        )
        for arrival in previous where
            arrival.arrivalTime > snapshot.fetchedAt
                && snapshot.failedRouteIDs.contains(arrival.routeID)
        {
            arrivalsByID[arrival.id] = arrival
        }
        return arrivalsByID.values.sorted { $0.arrivalTime < $1.arrivalTime }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var nearestStation: Station?
    @Published private(set) var distanceToStation: CLLocationDistance?
    @Published private(set) var nearbyStations: [NearbyStation] = []
    @Published private(set) var expandedStationID: String?
    @Published private(set) var allArrivals: [Arrival] = []
    @Published private(set) var availableRoutes: [String] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var feedWarning: String?
    @Published private(set) var allAlerts: [ServiceAlert] = []
    /// Alerts for the board strip: active on a selected line. Service-affecting alerts
    /// are line-wide; informational notices stay station-gated. Local alerts sort first.
    @Published private(set) var activeAlerts: [ServiceAlert] = []
    /// Whether any surfaced alert names the rider's own station. The empty-board copy
    /// claims the alert above explains the gap, which is only honest when the alert is
    /// here rather than elsewhere on the line.
    @Published private(set) var hasAlertAtNearestStation = false
    @Published private(set) var startupError: String?
    @Published private(set) var settingsPresentation: SettingsPresentation = .hidden
    @Published private(set) var selectedRoutes: Set<String>
    @Published private(set) var selectedDirection: TravelDirection?
    @Published private(set) var isPinned: Bool
    @Published private(set) var arrivalTimeDisplayMode: ArrivalTimeDisplayMode
    @Published private(set) var walkingPace: WalkingPace
    @Published private(set) var platformBufferSeconds: Int
    @Published private(set) var stationWalkOverrides: [String: Int]
    @Published private(set) var reachabilityEnabled: Bool
    @Published private(set) var menuBarUrgencyEnabled: Bool
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode
    @Published private(set) var menuBarShowRouteColor: Bool
    @Published private(set) var menuBarHideWhenIdle: Bool
    @Published private(set) var mapGeometry: TrackGeometryCatalog?
    @Published private(set) var mapMotionPlans: [TrainMotionPlan] = []
    @Published private(set) var mapUnplacedRouteIDs: Set<String> = []
    @Published private(set) var mapUnplacedTrainCountsByRoute: [String: Int] = [:]
    @Published private(set) var mapProjectionCoverage = TrainProjectionCoverage.empty
    @Published private(set) var mapFeedStatuses: [RealtimeFeedStatus] = []
    @Published private(set) var mapLatestFeedTimestamp: Date?
    @Published private(set) var isMapGeometryLoading = false
    @Published private(set) var mapGeometryError: String?
    @Published private(set) var isLiveMapActive = false
    @Published private(set) var isMenuPopoverActive = false
    private var cachedMapStations: [LiveMapStation]?

    let locationService = LocationService()
    let launchAtLogin: any LaunchAtLoginControlling
    let softwareUpdater: any SoftwareUpdating
    let crashReporter: any CrashReporting

    private let client: any SystemFeedFetching
    private let alertsClient: any ServiceAlertFetching
    private let catalog: StationCatalog?
    private let defaults: UserDefaults
    private let geometryLoader: any TrackGeometryLoading
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var lastRefreshAttempt: Date?
    private var isRefreshingAlerts = false
    private var lastAlertRefreshAttempt: Date?
    private var trainObservationCache = TrainObservationCache()
    private var trainProjectionEngine: TrainProjectionEngine?
    private var refreshTimer: AnyCancellable?
    private var countdownTimer: AnyCancellable?
    private var alertTimer: AnyCancellable?

    private enum DefaultsKey {
        static let selectedRoutes = "selectedRoutes"
        static let selectedDirection = "selectedDirection"
        static let hasConfiguredLines = "hasConfiguredLines"
        static let selectionOnboardingVersion = "selectionOnboardingVersion"
        static let isPinned = "isPinned"
        static let arrivalTimeDisplayMode = "arrivalTimeDisplayMode"
        static let walkingPace = "walkingPace"
        static let platformBufferSeconds = "platformBufferSeconds"
        static let stationWalkOverrides = "stationWalkOverrides"
        static let reachabilityEnabled = "reachabilityEnabled"
        static let menuBarUrgencyEnabled = "menuBarUrgencyEnabled"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let menuBarShowRouteColor = "menuBarShowRouteColor"
        static let menuBarHideWhenIdle = "menuBarHideWhenIdle"

        // Written by builds that allowed selecting both directions at once. Read
        // once during migration, then removed.
        static let legacySelectedDirections = "selectedDirections"
        static let legacyPinnedDirection = "pinnedDirection"
    }

    private static let currentSelectionOnboardingVersion = 1

    /// Arrivals move constantly; alerts do not. The MTA publishes no cache validators
    /// on this feed, so a slow poll is the only lever against re-downloading a payload
    /// that changes a few times an hour.
    private static let alertRefreshInterval: TimeInterval = 300
    private static let feedRefreshInterval: TimeInterval = 30
    private static let countdownTickInterval: TimeInterval = 1

    /// Folds a stored multi-direction selection down to the one direction the rider
    /// most likely watches, then writes the result forward so this runs only once.
    /// Deliberately avoids bumping `currentSelectionOnboardingVersion`, which would
    /// also reset the saved routes.
    private static func migratedSelection(
        from defaults: UserDefaults
    ) -> (direction: TravelDirection?, isPinned: Bool) {
        let legacyDirections = (defaults.stringArray(forKey: DefaultsKey.legacySelectedDirections) ?? [])
            .compactMap(TravelDirection.init(rawValue:))
            .filter(TravelDirection.selectableCases.contains)
        let legacyPin = defaults.string(forKey: DefaultsKey.legacyPinnedDirection)
            .flatMap(TravelDirection.init(rawValue:))
            .flatMap { TravelDirection.selectableCases.contains($0) ? $0 : nil }

        let direction: TravelDirection?
        switch legacyDirections.count {
        case 0:
            direction = nil
        case 1:
            direction = legacyDirections.first
        default:
            // Both directions were selected, so the pin is the strongest available
            // signal for which one the rider actually cared about.
            direction = legacyPin.flatMap { legacyDirections.contains($0) ? $0 : nil }
                ?? .northbound
        }

        let isPinned = direction != nil && legacyPin != nil
        if let direction {
            defaults.set(direction.rawValue, forKey: DefaultsKey.selectedDirection)
            defaults.set(isPinned, forKey: DefaultsKey.isPinned)
        }
        removeLegacySelectionKeys(from: defaults)
        return (direction, isPinned)
    }

    private static func removeLegacySelectionKeys(from defaults: UserDefaults) {
        defaults.removeObject(forKey: DefaultsKey.legacySelectedDirections)
        defaults.removeObject(forKey: DefaultsKey.legacyPinnedDirection)
    }

    init(
        client: any SystemFeedFetching = MTAClient(),
        alertsClient: any ServiceAlertFetching = MTAAlertsClient(),
        defaults: UserDefaults = .standard,
        geometryLoader: any TrackGeometryLoading = BundledTrackGeometryLoader(),
        launchAtLogin: (any LaunchAtLoginControlling)? = nil,
        softwareUpdater: (any SoftwareUpdating)? = nil,
        crashReporter: (any CrashReporting)? = nil
    ) {
        self.client = client
        self.alertsClient = alertsClient
        self.defaults = defaults
        self.geometryLoader = geometryLoader
        self.launchAtLogin = launchAtLogin ?? LaunchAtLoginService()
        self.softwareUpdater = softwareUpdater ?? SparkleUpdaterService()
        self.crashReporter = crashReporter ?? SentryCrashReportingService(defaults: defaults)
        // The countdown is the format the board is built around — it is what the menu
        // bar already shows for a pinned train — so it is what a rider who has never
        // opened Settings gets. Setup no longer asks; clicking any ETA still switches.
        arrivalTimeDisplayMode = defaults.string(forKey: DefaultsKey.arrivalTimeDisplayMode)
            .flatMap(ArrivalTimeDisplayMode.init(rawValue:))
            ?? .minutesAndSeconds
        walkingPace = defaults.string(forKey: DefaultsKey.walkingPace)
            .flatMap(WalkingPace.init(rawValue:))
            ?? .average
        if defaults.object(forKey: DefaultsKey.platformBufferSeconds) == nil {
            platformBufferSeconds = WalkTimeEstimator.defaultPlatformBufferSeconds
        } else {
            platformBufferSeconds = max(0, defaults.integer(forKey: DefaultsKey.platformBufferSeconds))
        }
        stationWalkOverrides = Self.loadStationWalkOverrides(from: defaults)
        reachabilityEnabled = defaults.object(forKey: DefaultsKey.reachabilityEnabled) as? Bool ?? false
        menuBarUrgencyEnabled = defaults.object(forKey: DefaultsKey.menuBarUrgencyEnabled) as? Bool ?? true
        menuBarDisplayMode = defaults.string(forKey: DefaultsKey.menuBarDisplayMode)
            .flatMap(MenuBarDisplayMode.init(rawValue:))
            ?? .countdownWhenPinned
        menuBarShowRouteColor = defaults.object(forKey: DefaultsKey.menuBarShowRouteColor) as? Bool ?? true
        menuBarHideWhenIdle = defaults.bool(forKey: DefaultsKey.menuBarHideWhenIdle)
        let needsSelectionOnboarding = defaults.integer(forKey: DefaultsKey.selectionOnboardingVersion)
            < Self.currentSelectionOnboardingVersion

        let restoredRoutes: Set<String>
        let restoredDirection: TravelDirection?
        let restoredPin: Bool
        if needsSelectionOnboarding {
            restoredRoutes = []
            restoredDirection = nil
            restoredPin = false
            defaults.set([], forKey: DefaultsKey.selectedRoutes)
            defaults.removeObject(forKey: DefaultsKey.selectedDirection)
            defaults.removeObject(forKey: DefaultsKey.isPinned)
            Self.removeLegacySelectionKeys(from: defaults)
        } else {
            let loadedRoutes = Set(
                (defaults.stringArray(forKey: DefaultsKey.selectedRoutes) ?? [])
                    .map(RouteID.normalized)
            )
            restoredRoutes = DirectionVocabulary.compatibleSubset(of: loadedRoutes)
            if restoredRoutes != loadedRoutes {
                defaults.set(RouteID.sorted(restoredRoutes), forKey: DefaultsKey.selectedRoutes)
            }
            if
                let storedDirection = defaults.string(forKey: DefaultsKey.selectedDirection)
                    .flatMap(TravelDirection.init(rawValue:)),
                TravelDirection.selectableCases.contains(storedDirection)
            {
                restoredDirection = storedDirection
                restoredPin = defaults.bool(forKey: DefaultsKey.isPinned)
            } else {
                let migrated = Self.migratedSelection(from: defaults)
                restoredDirection = migrated.direction
                restoredPin = migrated.isPinned
            }
        }
        selectedRoutes = restoredRoutes
        selectedDirection = restoredDirection
        isPinned = restoredDirection == nil ? false : restoredPin
        do {
            catalog = try StationCatalog.bundled()
        } catch {
            catalog = nil
            startupError = error.localizedDescription
        }
        availableRoutes = RouteID.sorted(catalog?.allRoutes ?? [])
        settingsPresentation = hasConfiguredSelection ? .hidden : .onboarding

        self.softwareUpdater.onStateChange = { [weak self] in
            self?.objectWillChange.send()
        }

        locationService.$location
            .sink { [weak self] location in
                guard let self else { return }
                self.updateNearbyStations(for: location)
            }
            .store(in: &cancellables)
    }

    /// Built on first Live Map open so menu-bar-only sessions never pay for
    /// ~500 station presentation records.
    var mapStations: [LiveMapStation] {
        if let cachedMapStations { return cachedMapStations }
        let stations = (catalog?.stations ?? []).map { station -> LiveMapStation in
            let related = catalog?.relatedStations(to: station.id) ?? [station.id]
            let routes = catalog?.routes(serving: station.id) ?? []
            let isTransfer = related.count > 1
            return LiveMapStation(
                id: station.id,
                name: station.name,
                latitude: station.latitude,
                longitude: station.longitude,
                routeIDs: routes,
                isTransfer: isTransfer,
                showsInOverview: isTransfer && station.id == related.sorted().first
            )
        }
        cachedMapStations = stations
        return stations
    }

    private static func loadStationWalkOverrides(from defaults: UserDefaults) -> [String: Int] {
        guard let raw = defaults.dictionary(forKey: DefaultsKey.stationWalkOverrides) else {
            return [:]
        }
        var overrides: [String: Int] = [:]
        for (key, value) in raw {
            if let intValue = value as? Int {
                overrides[key] = max(0, intValue)
            } else if let number = value as? NSNumber {
                overrides[key] = max(0, number.intValue)
            }
        }
        return overrides
    }

    var stationSections: [StationSection] {
        guard let catalog, let selectedDirection else { return [] }
        return StationBoard.sections(
            nearby: nearbyStations,
            catalog: catalog,
            arrivals: allArrivals,
            selectedRoutes: selectedRoutes,
            selectedDirection: selectedDirection,
            expandedStationID: expandedStationID,
            now: now
        )
    }

    var menuBarPresentation: MenuBarPresentation {
        guard isPinned, let selectedDirection else { return .icon }
        let arrival = pinnedArrival
        let urgent: Bool
        if
            menuBarUrgencyEnabled,
            reachabilityEnabled,
            let arrival,
            let walkSeconds = walkSeconds(forStationID: nearestStation?.id)
        {
            urgent = WalkTimeEstimator.classify(
                arrivalTime: arrival.arrivalTime,
                now: now,
                walkSeconds: walkSeconds
            ) == .leaveNow
        } else {
            urgent = false
        }
        return .pinned(
            direction: selectedDirection,
            arrival: arrival,
            now: now,
            displayMode: menuBarDisplayMode,
            hideWhenIdle: menuBarHideWhenIdle,
            isUrgent: urgent,
            vocabulary: currentVocabulary
        )
    }

    var currentVocabulary: DirectionVocabulary {
        DirectionVocabulary.forSelection(selectedRoutes)
    }

    var hasConfiguredSelection: Bool {
        defaults.bool(forKey: DefaultsKey.hasConfiguredLines)
            && defaults.integer(forKey: DefaultsKey.selectionOnboardingVersion)
                >= Self.currentSelectionOnboardingVersion
            && hasUsableSelection
    }

    var hasUsableSelection: Bool {
        !selectedRoutes.intersection(availableRoutes).isEmpty && selectedDirection != nil
    }

    var showsMinutesAndSeconds: Bool {
        arrivalTimeDisplayMode == .minutesAndSeconds
    }

    /// Routes carrying an alert badge in Settings. Line-wide and selection-agnostic:
    /// any active, service-affecting alert anywhere on the line lights the badge, so
    /// turning a line off does not hide that it has trouble. Informational notices
    /// (boarding changes, station notices) stay out. The board strip via `activeAlerts`
    /// covers the same service-affecting set, filtered to selected lines.
    @Published private(set) var alertedRouteIDs: Set<String> = []

    var isShowingSettings: Bool {
        settingsPresentation != .hidden
    }

    var isOnboarding: Bool {
        settingsPresentation == .onboarding
    }

    func canToggleRoute(_ routeID: String) -> Bool {
        let routeID = RouteID.normalized(routeID)
        guard selectedRoutes.contains(routeID), !isOnboarding else { return true }
        return selectedRoutes.intersection(availableRoutes) != [routeID]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        locationService.requestLocation()
        softwareUpdater.start()
        startBackgroundTimers()
        updateCountdownTimer()
        Task { await refresh() }
        Task { await refreshAlerts() }
    }

    var hasPendingUpdate: Bool {
        if case .available = softwareUpdater.state {
            return true
        }
        return false
    }

    var isAutomaticUpdateChecksEnabled: Bool {
        softwareUpdater.automaticallyChecksForUpdates
    }

    func setAutomaticUpdateChecksEnabled(_ enabled: Bool) {
        softwareUpdater.setAutomaticallyChecksForUpdates(enabled)
        objectWillChange.send()
    }

    var isCrashReportingEnabled: Bool {
        crashReporter.isEnabled
    }

    func setCrashReportingEnabled(_ enabled: Bool) {
        crashReporter.setEnabled(enabled)
        objectWillChange.send()
    }

    func checkForSoftwareUpdates() {
        softwareUpdater.checkForUpdates()
        objectWillChange.send()
    }

    func refreshSoftwareUpdateInformation() {
        softwareUpdater.refreshUpdateInformation()
        objectWillChange.send()
    }

    func setMenuPopoverActive(_ active: Bool) {
        guard isMenuPopoverActive != active else { return }
        isMenuPopoverActive = active
        if active {
            now = Date()
        }
        updateCountdownTimer()
    }

    func setLiveMapActive(_ active: Bool) {
        guard isLiveMapActive != active else { return }
        isLiveMapActive = active
        if active {
            now = Date()
            updateCountdownTimer()
            // Pull train observations as soon as the map opens, but only once
            // the app has started its normal refresh loop (tests seed snapshots
            // without calling start()).
            if hasStarted {
                Task { await refresh() }
            }
        } else {
            releaseMapResources()
            updateCountdownTimer()
        }
    }

    func refresh() async {
        guard !isRefreshing, let catalog else { return }
        locationService.requestLocation()
        isRefreshing = true
        let refreshDate = Date()
        lastRefreshAttempt = refreshDate
        defer { isRefreshing = false }

        let includeTrains = isLiveMapActive
        // Live Map needs every feed (`nil`); the board only needs selected lines
        // (empty set → fetch nothing during onboarding).
        let routeFilter: Set<String>? = includeTrains ? nil : selectedRoutes

        do {
            let snapshot = try await client.fetchSystemSnapshot(
                catalog: catalog,
                now: refreshDate,
                routeIDs: routeFilter,
                includeTrains: includeTrains
            )
            let arrivalSnapshot = FeedSnapshot(
                arrivals: snapshot.arrivals,
                fetchedAt: snapshot.fetchedAt,
                failedFeedCount: snapshot.failedFeedCount,
                failedRouteIDs: snapshot.failedRouteIDs
            )
            allArrivals = ArrivalCache.merging(previous: allArrivals, snapshot: arrivalSnapshot)
            lastUpdated = snapshot.fetchedAt
            feedWarning = snapshot.failedFeedCount == 0
                ? nil
                : "\(snapshot.failedFeedCount) MTA feed\(snapshot.failedFeedCount == 1 ? "" : "s") did not respond."
            mapFeedStatuses = snapshot.feedStatuses
            if let latestFeedTimestamp = snapshot.latestFeedTimestamp {
                mapLatestFeedTimestamp = latestFeedTimestamp
            }
            if includeTrains {
                _ = trainObservationCache.merge(snapshot, at: refreshDate)
                await updateMapMotionPlans(
                    entries: trainObservationCache.coverageEntries(at: refreshDate),
                    at: refreshDate
                )
            }
            updateAvailableRoutes()
        } catch {
            feedWarning = error.localizedDescription
            mapFeedStatuses = mapFeedStatuses.map { status in
                RealtimeFeedStatus(
                    feedID: status.feedID,
                    routeIDs: status.routeIDs,
                    state: .failed,
                    feedTimestamp: status.feedTimestamp,
                    deletedEntityIDs: status.deletedEntityIDs
                )
            }
            if includeTrains {
                await updateMapMotionPlans(
                    entries: trainObservationCache.coverageEntries(at: refreshDate),
                    at: refreshDate
                )
            }
        }
    }

    /// Alerts are fetched on their own clock and fail on their own terms. A dead alert
    /// feed leaves the last known alerts in place and never touches `feedWarning`, which
    /// belongs to the arrival feeds — the board must keep working when only this breaks.
    func refreshAlerts() async {
        guard !isRefreshingAlerts, let catalog else { return }
        isRefreshingAlerts = true
        let refreshDate = Date()
        lastAlertRefreshAttempt = refreshDate
        defer { isRefreshingAlerts = false }

        guard let snapshot = try? await alertsClient.fetchAlerts(
            catalog: catalog,
            now: refreshDate
        ) else { return }

        allAlerts = snapshot.alerts
        updateActiveAlerts()
    }

    func loadMapGeometry() async {
        guard mapGeometry == nil, !isMapGeometryLoading else { return }
        isMapGeometryLoading = true
        mapGeometryError = nil
        let loader = geometryLoader
        defer { isMapGeometryLoading = false }

        do {
            let geometry = try await Task.detached(priority: .userInitiated) {
                try loader.load()
            }.value
            mapGeometry = geometry
            trainProjectionEngine = TrainProjectionEngine(catalog: geometry)
            // Ensure stations exist once the map is about to draw.
            _ = mapStations
            await updateMapMotionPlans(
                entries: trainObservationCache.coverageEntries(at: now),
                at: now
            )
        } catch {
            mapGeometryError = error.localizedDescription
        }
    }

    /// Drops Live Map–only state so a closed map does not keep geometry,
    /// projection plans, or system-wide train observations resident.
    func releaseMapResources() {
        mapGeometry = nil
        trainProjectionEngine = nil
        mapMotionPlans = []
        mapUnplacedRouteIDs = []
        mapUnplacedTrainCountsByRoute = [:]
        mapProjectionCoverage = .empty
        mapGeometryError = nil
        isMapGeometryLoading = false
        trainObservationCache = TrainObservationCache()
        cachedMapStations = nil
    }

    func toggleRoute(_ routeID: String) {
        let routeID = RouteID.normalized(routeID)
        if selectedRoutes.contains(routeID) {
            guard canToggleRoute(routeID) else { return }
            selectedRoutes.remove(routeID)
        } else if !selectedRoutes.isEmpty,
                  RouteID.vocabulary(routeID) != DirectionVocabulary.forSelection(selectedRoutes)
        {
            // Conflicting direction vocabulary: replace the selection so one toggle
            // always describes every selected line.
            selectedRoutes = [routeID]
        } else {
            selectedRoutes.insert(routeID)
        }
        persistSelection()
        updateNearbyStations(for: locationService.location)
    }

    /// Accordion: expanding one station collapses any other. Tapping the open station
    /// collapses it again.
    func toggleStationExpanded(_ stationID: String) {
        guard nearbyStations.contains(where: { $0.id == stationID }) else { return }
        expandedStationID = expandedStationID == stationID ? nil : stationID
    }

    func collapseExpandedStation() {
        expandedStationID = nil
    }

    /// Testing seam so accordion / alert-badge behavior can be exercised without Core Location.
    func seedNearbyStationsForTesting(_ stations: [NearbyStation]) {
        nearbyStations = stations
        nearestStation = stations.first?.station
        distanceToStation = stations.first?.distance
        updateActiveAlerts()
    }

    func selectDirection(_ direction: TravelDirection) {
        guard TravelDirection.selectableCases.contains(direction) else { return }
        guard selectedDirection != direction else { return }
        selectedDirection = direction
        persistDirection()
    }

    /// Flips to the opposite direction while leaving the pin alone, so the menu bar
    /// countdown follows whichever direction is selected instead of being cleared.
    func swapDirection() {
        guard let selectedDirection else { return }
        guard
            let other = TravelDirection.selectableCases.first(where: { $0 != selectedDirection })
        else { return }
        selectDirection(other)
    }

    func togglePin() {
        guard selectedDirection != nil else { return }
        isPinned.toggle()
        persistPin()
    }

    func clearPin() {
        isPinned = false
        persistPin()
    }

    func toggleArrivalTimeDisplay() {
        setArrivalTimeDisplayMode(
            showsMinutesAndSeconds ? .wholeMinutes : .minutesAndSeconds
        )
    }

    func setArrivalTimeDisplayMode(_ mode: ArrivalTimeDisplayMode) {
        guard arrivalTimeDisplayMode != mode else { return }
        arrivalTimeDisplayMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.arrivalTimeDisplayMode)
    }

    func requestManualRefresh() {
        Task { await refresh() }
    }

    func setWalkingPace(_ pace: WalkingPace) {
        guard walkingPace != pace else { return }
        walkingPace = pace
        defaults.set(pace.rawValue, forKey: DefaultsKey.walkingPace)
    }

    func setPlatformBufferSeconds(_ seconds: Int) {
        let clamped = max(0, min(seconds, 600))
        guard platformBufferSeconds != clamped else { return }
        platformBufferSeconds = clamped
        defaults.set(clamped, forKey: DefaultsKey.platformBufferSeconds)
    }

    func setStationWalkOverride(stationID: String, seconds: Int?) {
        if let seconds {
            stationWalkOverrides[stationID] = max(0, min(seconds, 1_800))
        } else {
            stationWalkOverrides.removeValue(forKey: stationID)
        }
        defaults.set(stationWalkOverrides, forKey: DefaultsKey.stationWalkOverrides)
    }

    func setReachabilityEnabled(_ enabled: Bool) {
        guard reachabilityEnabled != enabled else { return }
        reachabilityEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.reachabilityEnabled)
    }

    func setMenuBarUrgencyEnabled(_ enabled: Bool) {
        guard menuBarUrgencyEnabled != enabled else { return }
        menuBarUrgencyEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.menuBarUrgencyEnabled)
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        guard menuBarDisplayMode != mode else { return }
        menuBarDisplayMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.menuBarDisplayMode)
    }

    func setMenuBarShowRouteColor(_ enabled: Bool) {
        guard menuBarShowRouteColor != enabled else { return }
        menuBarShowRouteColor = enabled
        defaults.set(enabled, forKey: DefaultsKey.menuBarShowRouteColor)
    }

    func setMenuBarHideWhenIdle(_ enabled: Bool) {
        guard menuBarHideWhenIdle != enabled else { return }
        menuBarHideWhenIdle = enabled
        defaults.set(enabled, forKey: DefaultsKey.menuBarHideWhenIdle)
    }

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> String? {
        do {
            try launchAtLogin.setEnabled(enabled)
            objectWillChange.send()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        launchAtLogin.isEnabled
    }

    func walkSeconds(forStationID stationID: String?) -> Int? {
        guard let stationID else { return nil }
        let nearby = nearbyStations.first(where: { $0.id == stationID })
        let distance = nearby?.distance ?? (stationID == nearestStation?.id ? distanceToStation : nil)
        guard let distance else { return nil }
        return WalkTimeEstimator.resolveSeconds(
            straightLineMeters: distance,
            pace: walkingPace,
            platformBufferSeconds: platformBufferSeconds,
            stationOverrideSeconds: stationWalkOverrides[stationID]
        )
    }

    func reachability(for arrival: Arrival, atStationID stationID: String) -> Reachability? {
        guard reachabilityEnabled, let walkSeconds = walkSeconds(forStationID: stationID) else {
            return nil
        }
        return WalkTimeEstimator.classify(
            arrivalTime: arrival.arrivalTime,
            now: now,
            walkSeconds: walkSeconds
        )
    }

    func openSettings(section: SettingsSection) {
        settingsPresentation = hasConfiguredSelection ? .settings(section) : .onboarding
    }

    func closeSettings() {
        guard case .settings = settingsPresentation else { return }
        settingsPresentation = .hidden
    }

    /// Records the rider's direction and lines and hands over the board. Launch at
    /// login is deliberately not asked here — it is a General setting in the Settings
    /// window, not a question standing between a first-run rider and their arrivals.
    func finishChoosingLines() {
        guard hasUsableSelection else { return }
        defaults.set(true, forKey: DefaultsKey.hasConfiguredLines)
        defaults.set(
            Self.currentSelectionOnboardingVersion,
            forKey: DefaultsKey.selectionOnboardingVersion
        )
        settingsPresentation = .hidden
    }

    func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func mapStationName(forStopID stopID: String) -> String? {
        catalog?.stationName(forStopID: stopID)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateNearbyStations(for location: CLLocation?) {
        guard let catalog, let location else {
            nearestStation = nil
            distanceToStation = nil
            nearbyStations = []
            expandedStationID = nil
            updateAvailableRoutes()
            updateActiveAlerts()
            return
        }

        if selectedRoutes.isEmpty {
            nearbyStations = []
            if let nearest = catalog.nearest(to: location) {
                nearestStation = nearest.station
                distanceToStation = nearest.distance
            } else {
                nearestStation = nil
                distanceToStation = nil
            }
        } else {
            let results = catalog.nearestStations(
                to: location,
                count: StationBoard.nearbyStationCount,
                servingAnyOf: selectedRoutes
            )
            nearbyStations = results.map { NearbyStation(station: $0.station, distance: $0.distance) }
            nearestStation = results.first?.station
            distanceToStation = results.first?.distance
        }

        if let expandedStationID,
           !nearbyStations.contains(where: { $0.id == expandedStationID })
        {
            self.expandedStationID = nil
        }

        updateAvailableRoutes()
        updateActiveAlerts()
    }

    /// The soonest catchable arrival among selected routes in the selected direction when
    /// reachability is on; otherwise the soonest matching arrival. A pin covers the whole
    /// direction, not one fixed route, so this can resolve to a different route over time.
    var pinnedArrival: Arrival? {
        guard
            isPinned,
            locationService.authorizationStatus.allowsStandClearLocation,
            let selectedDirection,
            let nearestStation,
            let catalog
        else { return nil }
        let candidates = ArrivalBoard.arrivals(
            from: allArrivals,
            atAny: catalog.relatedStations(to: nearestStation.id),
            selectedRoutes: selectedRoutes,
            selectedDirections: [selectedDirection],
            now: now,
            limit: 8
        )
        guard reachabilityEnabled else { return candidates.first }
        guard let walkSeconds = walkSeconds(forStationID: nearestStation.id) else {
            return candidates.first
        }
        return candidates.first { arrival in
            WalkTimeEstimator.classify(
                arrivalTime: arrival.arrivalTime,
                now: now,
                walkSeconds: walkSeconds
            ).isCatchable
        }
    }

    private func updateAvailableRoutes() {
        availableRoutes = RouteID.sorted(catalog?.allRoutes ?? [])
    }

    /// Recomputed on the three things that can change the answer — a new alert fetch, a
    /// new nearest station, a changed line selection — rather than derived on read. A
    /// computed property would re-filter the whole feed every second, because `now`
    /// ticks once a second to drive the countdowns.
    private func updateActiveAlerts() {
        alertedRouteIDs = AlertBoard
            .alertedRouteIDs(from: allAlerts, now: now)
            .intersection(availableRoutes)

        let stationIDs = nearestStation.flatMap { station in
            catalog?.relatedStations(to: station.id)
        } ?? []
        activeAlerts = AlertBoard.alerts(
            from: allAlerts,
            atAny: stationIDs,
            selectedRoutes: selectedRoutes,
            now: now
        )
        hasAlertAtNearestStation = !stationIDs.isEmpty
            && activeAlerts.contains { $0.affectsAnyStation(in: stationIDs) }
    }

    private func updateMapMotionPlans(
        entries: [TrainObservationCache.Entry],
        at date: Date
    ) async {
        guard let engine = trainProjectionEngine else { return }
        let result = await Task.detached(priority: .userInitiated) {
            var engine = engine
            let plans = engine.update(entries: entries, at: date)
            return (plans, engine)
        }.value
        mapMotionPlans = result.0
        mapUnplacedRouteIDs = result.1.coverage.unplacedRouteIDs
        mapUnplacedTrainCountsByRoute = result.1.coverage.unplacedTrainCountsByRoute
        mapProjectionCoverage = result.1.coverage
        trainProjectionEngine = result.1
    }

    private func persistSelection() {
        defaults.set(RouteID.sorted(selectedRoutes), forKey: DefaultsKey.selectedRoutes)
    }

    private func persistDirection() {
        if let selectedDirection {
            defaults.set(selectedDirection.rawValue, forKey: DefaultsKey.selectedDirection)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedDirection)
        }
    }

    private func persistPin() {
        defaults.set(isPinned, forKey: DefaultsKey.isPinned)
        updateCountdownTimer()
    }

    private func startBackgroundTimers() {
        refreshTimer = Timer.publish(every: Self.feedRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
        alertTimer = Timer.publish(every: Self.alertRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshAlerts() }
            }
    }

    /// The 1 Hz countdown only runs when something on screen needs it: an open
    /// popover, a pinned menu-bar countdown, or the Live Map. Otherwise the
    /// published `now` tick would rebuild the whole board for no reason.
    private func updateCountdownTimer() {
        let needsCountdown = isMenuPopoverActive || isLiveMapActive || isPinned
        if needsCountdown {
            guard countdownTimer == nil else { return }
            countdownTimer = Timer.publish(every: Self.countdownTickInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] date in
                    self?.now = date
                }
        } else {
            countdownTimer?.cancel()
            countdownTimer = nil
        }
    }
}
