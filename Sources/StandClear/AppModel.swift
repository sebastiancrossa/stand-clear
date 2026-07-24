import AppKit
import Combine
import CoreLocation
import Foundation
import StandClearCore

protocol SystemFeedFetching {
    func fetchSystemSnapshot(
        catalog: StationCatalog,
        now: Date
    ) async throws -> SystemFeedSnapshot
}

extension MTAClient: SystemFeedFetching {}

protocol TrackGeometryLoading: Sendable {
    func load() throws -> TrackGeometryCatalog
}

struct BundledTrackGeometryLoader: TrackGeometryLoading {
    func load() throws -> TrackGeometryCatalog {
        try TrackGeometryCatalog.bundled()
    }
}

struct PinnedService: Equatable {
    let routeID: String
    let direction: TravelDirection

    init(routeID: String, direction: TravelDirection) {
        self.routeID = RouteID.normalized(routeID)
        self.direction = direction
    }
}

enum ArrivalTimeDisplayMode: String, CaseIterable {
    case wholeMinutes
    case minutesAndSeconds
}

enum SettingsPresentation {
    case hidden
    case settings
    case onboarding
}

struct MenuBarPresentation: Equatable {
    enum Content: Equatable {
        case icon
        case text(String)
    }

    let content: Content
    let accessibilityLabel: String

    var text: String? {
        guard case let .text(text) = content else { return nil }
        return text
    }

    static let icon = MenuBarPresentation(
        content: .icon,
        accessibilityLabel: "Stand Clear"
    )

    static func pinned(
        service: PinnedService,
        arrival: Arrival?,
        now: Date
    ) -> MenuBarPresentation {
        let route = RouteID.displayLabel(service.routeID)
        let direction = service.direction.arrow
        guard let arrival else {
            return MenuBarPresentation(
                content: .text("\(route) \(direction) --:--"),
                accessibilityLabel: "\(route) train \(service.direction.accessibilityName), no upcoming arrival"
            )
        }

        let remainingSeconds = max(0, Int(floor(arrival.arrivalTime.timeIntervalSince(now))))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return MenuBarPresentation(
            content: .text("\(route) \(direction) \(arrival.etaMinutesSecondsText(relativeTo: now))"),
            accessibilityLabel: "\(route) train \(service.direction.accessibilityName), arriving in "
                + "\(minutes) \(minutes == 1 ? "minute" : "minutes") "
                + "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        )
    }
}

private extension TravelDirection {
    var accessibilityName: String {
        switch self {
        case .northbound: "uptown"
        case .southbound: "downtown"
        case .unknown: "unknown direction"
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
    @Published private(set) var allArrivals: [Arrival] = []
    @Published private(set) var availableRoutes: [String] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var feedWarning: String?
    @Published private(set) var startupError: String?
    @Published private(set) var settingsPresentation: SettingsPresentation = .hidden
    @Published private(set) var selectedRoutes: Set<String>
    @Published private(set) var selectedDirections: Set<TravelDirection>
    @Published private(set) var pinnedService: PinnedService?
    @Published private(set) var arrivalTimeDisplayMode: ArrivalTimeDisplayMode
    @Published private(set) var mapGeometry: TrackGeometryCatalog?
    @Published private(set) var mapMotionPlans: [TrainMotionPlan] = []
    @Published private(set) var mapUnplacedRouteIDs: Set<String> = []
    @Published private(set) var mapUnplacedTrainCountsByRoute: [String: Int] = [:]
    @Published private(set) var mapProjectionCoverage = TrainProjectionCoverage.empty
    @Published private(set) var mapFeedStatuses: [RealtimeFeedStatus] = []
    @Published private(set) var mapLatestFeedTimestamp: Date?
    @Published private(set) var isMapGeometryLoading = false
    @Published private(set) var mapGeometryError: String?
    private(set) var mapStations: [LiveMapStation] = []

    let locationService = LocationService()

    private let client: any SystemFeedFetching
    private let catalog: StationCatalog?
    private let defaults: UserDefaults
    private let geometryLoader: any TrackGeometryLoading
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var lastRefreshAttempt: Date?
    private var trainObservationCache = TrainObservationCache()
    private var trainProjectionEngine: TrainProjectionEngine?

    private enum DefaultsKey {
        static let selectedRoutes = "selectedRoutes"
        static let selectedDirections = "selectedDirections"
        static let hasConfiguredLines = "hasConfiguredLines"
        static let selectionOnboardingVersion = "selectionOnboardingVersion"
        static let pinnedRoute = "pinnedRoute"
        static let pinnedDirection = "pinnedDirection"
        static let arrivalTimeDisplayMode = "arrivalTimeDisplayMode"
    }

    private static let currentSelectionOnboardingVersion = 1

    init(
        client: any SystemFeedFetching = MTAClient(),
        defaults: UserDefaults = .standard,
        geometryLoader: any TrackGeometryLoading = BundledTrackGeometryLoader()
    ) {
        self.client = client
        self.defaults = defaults
        self.geometryLoader = geometryLoader
        arrivalTimeDisplayMode = defaults.string(forKey: DefaultsKey.arrivalTimeDisplayMode)
            .flatMap(ArrivalTimeDisplayMode.init(rawValue:))
            ?? .wholeMinutes
        let needsSelectionOnboarding = defaults.integer(forKey: DefaultsKey.selectionOnboardingVersion)
            < Self.currentSelectionOnboardingVersion

        let restoredRoutes: Set<String>
        let restoredDirections: Set<TravelDirection>
        if needsSelectionOnboarding {
            restoredRoutes = []
            restoredDirections = []
            defaults.set([], forKey: DefaultsKey.selectedRoutes)
            defaults.set([], forKey: DefaultsKey.selectedDirections)
        } else {
            restoredRoutes = Set(
                (defaults.stringArray(forKey: DefaultsKey.selectedRoutes) ?? [])
                    .map(RouteID.normalized)
            )
            if let storedDirections = defaults.stringArray(forKey: DefaultsKey.selectedDirections) {
                restoredDirections = Set(
                    storedDirections
                        .compactMap(TravelDirection.init(rawValue:))
                        .filter(TravelDirection.selectableCases.contains)
                )
            } else {
                restoredDirections = []
            }
        }
        selectedRoutes = restoredRoutes
        selectedDirections = restoredDirections
        if
            let storedRoute = defaults.string(forKey: DefaultsKey.pinnedRoute),
            let storedDirection = defaults.string(forKey: DefaultsKey.pinnedDirection)
                .flatMap(TravelDirection.init(rawValue:)),
            TravelDirection.selectableCases.contains(storedDirection),
            restoredRoutes.contains(RouteID.normalized(storedRoute)),
            restoredDirections.contains(storedDirection)
        {
            pinnedService = PinnedService(routeID: storedRoute, direction: storedDirection)
        } else {
            pinnedService = nil
            defaults.removeObject(forKey: DefaultsKey.pinnedRoute)
            defaults.removeObject(forKey: DefaultsKey.pinnedDirection)
        }
        do {
            catalog = try StationCatalog.bundled()
        } catch {
            catalog = nil
            startupError = error.localizedDescription
        }
        availableRoutes = RouteID.sorted(catalog?.allRoutes ?? [])
        settingsPresentation = hasConfiguredSelection ? .hidden : .onboarding
        mapStations = (catalog?.stations ?? []).map { station in
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

        locationService.$location
            .sink { [weak self] location in
                guard let self else { return }
                if let location {
                    self.updateNearestStation(for: location)
                } else {
                    self.nearestStation = nil
                    self.distanceToStation = nil
                }
            }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                if let attempt = self.lastRefreshAttempt, date.timeIntervalSince(attempt) >= 30 {
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)
    }

    var displayedArrivals: [Arrival] {
        guard let station = nearestStation, let catalog else { return [] }
        return ArrivalBoard.arrivals(
            from: allArrivals,
            atAny: catalog.relatedStations(to: station.id),
            selectedRoutes: selectedRoutes,
            selectedDirections: selectedDirections,
            now: now
        )
    }

    var menuBarPresentation: MenuBarPresentation {
        guard let pinnedService else { return .icon }
        return .pinned(service: pinnedService, arrival: pinnedArrival, now: now)
    }

    var hasConfiguredSelection: Bool {
        defaults.bool(forKey: DefaultsKey.hasConfiguredLines)
            && defaults.integer(forKey: DefaultsKey.selectionOnboardingVersion)
                >= Self.currentSelectionOnboardingVersion
            && hasUsableSelection
    }

    var hasUsableSelection: Bool {
        !selectedRoutes.intersection(availableRoutes).isEmpty
            && !selectedDirections.intersection(TravelDirection.selectableCases).isEmpty
    }

    var showsMinutesAndSeconds: Bool {
        arrivalTimeDisplayMode == .minutesAndSeconds
    }

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

    func canToggleDirection(_ direction: TravelDirection) -> Bool {
        guard TravelDirection.selectableCases.contains(direction) else { return false }
        guard selectedDirections.contains(direction), !isOnboarding else { return true }
        return selectedDirections.intersection(TravelDirection.selectableCases) != [direction]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        locationService.requestLocation()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing, let catalog else { return }
        locationService.requestLocation()
        isRefreshing = true
        let refreshDate = Date()
        lastRefreshAttempt = refreshDate
        defer { isRefreshing = false }

        do {
            let snapshot = try await client.fetchSystemSnapshot(catalog: catalog, now: refreshDate)
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
            _ = trainObservationCache.merge(snapshot, at: refreshDate)
            updateMapMotionPlans(
                entries: trainObservationCache.coverageEntries(at: refreshDate),
                at: refreshDate
            )
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
            updateMapMotionPlans(
                entries: trainObservationCache.coverageEntries(at: refreshDate),
                at: refreshDate
            )
        }
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
            updateMapMotionPlans(
                entries: trainObservationCache.coverageEntries(at: now),
                at: now
            )
        } catch {
            mapGeometryError = error.localizedDescription
        }
    }

    func toggleRoute(_ routeID: String) {
        let routeID = RouteID.normalized(routeID)
        if selectedRoutes.contains(routeID) {
            guard canToggleRoute(routeID) else { return }
            selectedRoutes.remove(routeID)
        } else {
            selectedRoutes.insert(routeID)
        }
        persistSelection()
        clearPinIfInvalid()
    }

    func toggleDirection(_ direction: TravelDirection) {
        guard TravelDirection.selectableCases.contains(direction) else { return }
        if selectedDirections.contains(direction) {
            guard canToggleDirection(direction) else { return }
            selectedDirections.remove(direction)
        } else {
            selectedDirections.insert(direction)
        }
        persistDirections()
        clearPinIfInvalid()
    }

    func togglePin(routeID: String, direction: TravelDirection) {
        let pin = PinnedService(routeID: routeID, direction: direction)
        guard
            TravelDirection.selectableCases.contains(direction),
            selectedRoutes.contains(pin.routeID),
            selectedDirections.contains(direction)
        else { return }
        pinnedService = pinnedService == pin ? nil : pin
        persistPin()
    }

    func clearPin() {
        pinnedService = nil
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

    func openSettings() {
        settingsPresentation = hasConfiguredSelection ? .settings : .onboarding
    }

    func closeSettings() {
        guard settingsPresentation == .settings else { return }
        settingsPresentation = .hidden
    }

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

    private func updateNearestStation(for location: CLLocation) {
        guard let nearest = catalog?.nearest(to: location) else { return }
        nearestStation = nearest.station
        distanceToStation = nearest.distance
        updateAvailableRoutes()
    }

    private var pinnedArrival: Arrival? {
        guard
            locationService.authorizationStatus.allowsStandClearLocation,
            let pinnedService,
            let nearestStation,
            let catalog
        else { return nil }
        return ArrivalBoard.nextArrival(
            from: allArrivals,
            atAny: catalog.relatedStations(to: nearestStation.id),
            routeID: pinnedService.routeID,
            direction: pinnedService.direction,
            now: now
        )
    }

    private func updateAvailableRoutes() {
        availableRoutes = RouteID.sorted(catalog?.allRoutes ?? [])
    }

    private func updateMapMotionPlans(
        entries: [TrainObservationCache.Entry],
        at date: Date
    ) {
        guard var engine = trainProjectionEngine else { return }
        let plans = engine.update(entries: entries, at: date)
        mapMotionPlans = plans
        mapUnplacedRouteIDs = engine.coverage.unplacedRouteIDs
        mapUnplacedTrainCountsByRoute = engine.coverage.unplacedTrainCountsByRoute
        mapProjectionCoverage = engine.coverage
        trainProjectionEngine = engine
    }

    private func persistSelection() {
        defaults.set(RouteID.sorted(selectedRoutes), forKey: DefaultsKey.selectedRoutes)
    }

    private func persistDirections() {
        defaults.set(
            TravelDirection.selectableCases
                .filter(selectedDirections.contains)
                .map(\.rawValue),
            forKey: DefaultsKey.selectedDirections
        )
    }

    private func persistPin() {
        if let pinnedService {
            defaults.set(pinnedService.routeID, forKey: DefaultsKey.pinnedRoute)
            defaults.set(pinnedService.direction.rawValue, forKey: DefaultsKey.pinnedDirection)
        } else {
            defaults.removeObject(forKey: DefaultsKey.pinnedRoute)
            defaults.removeObject(forKey: DefaultsKey.pinnedDirection)
        }
    }

    private func clearPinIfInvalid() {
        guard let pinnedService else { return }
        guard
            selectedRoutes.contains(pinnedService.routeID),
            selectedDirections.contains(pinnedService.direction)
        else {
            self.pinnedService = nil
            persistPin()
            return
        }
    }
}
