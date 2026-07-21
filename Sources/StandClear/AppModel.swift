import AppKit
import Combine
import CoreLocation
import Foundation
import StandClearCore

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
    }

    private static let currentSelectionOnboardingVersion = 1

    init(client: MTAClient = MTAClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        let needsSelectionOnboarding = defaults.integer(forKey: DefaultsKey.selectionOnboardingVersion)
            < Self.currentSelectionOnboardingVersion

        if needsSelectionOnboarding {
            selectedRoutes = []
            selectedDirections = []
            defaults.set([], forKey: DefaultsKey.selectedRoutes)
            defaults.set([], forKey: DefaultsKey.selectedDirections)
        } else {
            selectedRoutes = Set(defaults.stringArray(forKey: DefaultsKey.selectedRoutes) ?? [])
            if let storedDirections = defaults.stringArray(forKey: DefaultsKey.selectedDirections) {
                selectedDirections = Set(storedDirections.compactMap(TravelDirection.init(rawValue:)))
            } else {
                selectedDirections = []
            }
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
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.updateNearestStation(for: location)
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

    var menuBarTitle: String {
        guard let arrival = displayedArrivals.first else { return "Stand Clear" }
        return "\(RouteID.displayLabel(arrival.routeID)) \(arrival.etaText(relativeTo: now))"
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
            allArrivals = snapshot.arrivals
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
    }

    func toggleDirection(_ direction: TravelDirection) {
        if selectedDirections.contains(direction) {
            selectedDirections.remove(direction)
        } else {
            selectedDirections.insert(direction)
        }
        persistDirections()
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
}
