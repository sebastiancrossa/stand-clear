import AppKit
import Combine
import CoreLocation
import Foundation
import StandClearCore

struct PinnedService: Equatable {
    let routeID: String
    let direction: TravelDirection

    init(routeID: String, direction: TravelDirection) {
        self.routeID = RouteID.normalized(routeID)
        self.direction = direction
    }
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
    @Published var isChoosingLines: Bool
    @Published private(set) var selectedRoutes: Set<String>
    @Published private(set) var selectedDirections: Set<TravelDirection>
    @Published private(set) var pinnedService: PinnedService?
    @Published private(set) var showsMinutesAndSeconds = false

    let locationService = LocationService()

    private let client: MTAClient
    private let catalog: StationCatalog?
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var lastRefreshAttempt: Date?

    private enum DefaultsKey {
        static let selectedRoutes = "selectedRoutes"
        static let selectedDirections = "selectedDirections"
        static let hasConfiguredLines = "hasConfiguredLines"
        static let selectionOnboardingVersion = "selectionOnboardingVersion"
        static let pinnedRoute = "pinnedRoute"
        static let pinnedDirection = "pinnedDirection"
    }

    private static let currentSelectionOnboardingVersion = 1

    init(client: MTAClient = MTAClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
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
            restoredRoutes = Set(defaults.stringArray(forKey: DefaultsKey.selectedRoutes) ?? [])
            if let storedDirections = defaults.stringArray(forKey: DefaultsKey.selectedDirections) {
                restoredDirections = Set(storedDirections.compactMap(TravelDirection.init(rawValue:)))
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
        isChoosingLines = needsSelectionOnboarding || !defaults.bool(forKey: DefaultsKey.hasConfiguredLines)

        do {
            catalog = try StationCatalog.bundled()
        } catch {
            catalog = nil
            startupError = error.localizedDescription
        }
        availableRoutes = RouteID.sorted(catalog?.allRoutes ?? [])

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
        lastRefreshAttempt = Date()
        defer { isRefreshing = false }

        do {
            let snapshot = try await client.fetchArrivals(catalog: catalog)
            allArrivals = ArrivalCache.merging(previous: allArrivals, snapshot: snapshot)
            lastUpdated = snapshot.fetchedAt
            feedWarning = snapshot.failedFeedCount == 0
                ? nil
                : "\(snapshot.failedFeedCount) MTA feed\(snapshot.failedFeedCount == 1 ? "" : "s") did not respond."
            updateAvailableRoutes()
        } catch {
            feedWarning = error.localizedDescription
        }
    }

    func toggleRoute(_ routeID: String) {
        let routeID = RouteID.normalized(routeID)
        if selectedRoutes.contains(routeID) {
            selectedRoutes.remove(routeID)
        } else {
            selectedRoutes.insert(routeID)
        }
        persistSelection()
        clearPinIfInvalid()
    }

    func toggleDirection(_ direction: TravelDirection) {
        if selectedDirections.contains(direction) {
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
        showsMinutesAndSeconds.toggle()
    }

    func finishChoosingLines() {
        guard
            !selectedRoutes.intersection(availableRoutes).isEmpty,
            !selectedDirections.isEmpty
        else { return }
        defaults.set(true, forKey: DefaultsKey.hasConfiguredLines)
        defaults.set(
            Self.currentSelectionOnboardingVersion,
            forKey: DefaultsKey.selectionOnboardingVersion
        )
        isChoosingLines = false
    }

    func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
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
