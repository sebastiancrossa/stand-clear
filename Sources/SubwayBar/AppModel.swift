import AppKit
import Combine
import CoreLocation
import Foundation
import SubwayBarCore

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

    let locationService = LocationService()

    private let client: MTAClient
    private let catalog: StationCatalog?
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var lastRefreshAttempt: Date?

    private enum DefaultsKey {
        static let selectedRoutes = "selectedRoutes"
        static let hasConfiguredLines = "hasConfiguredLines"
    }

    init(client: MTAClient = MTAClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        selectedRoutes = Set(defaults.stringArray(forKey: DefaultsKey.selectedRoutes) ?? [])
        isChoosingLines = !defaults.bool(forKey: DefaultsKey.hasConfiguredLines)

        do {
            catalog = try StationCatalog.bundled()
        } catch {
            catalog = nil
            startupError = error.localizedDescription
        }

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
        guard let station = nearestStation else { return [] }
        return ArrivalBoard.arrivals(
            from: allArrivals,
            at: station.id,
            selectedRoutes: selectedRoutes,
            now: now
        )
    }

    var menuBarTitle: String {
        guard let arrival = displayedArrivals.first else { return "Subway" }
        return "\(arrival.routeID) \(arrival.etaText(relativeTo: now))"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        locationService.requestLocation()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing, let catalog else { return }
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

    func finishChoosingLines() {
        guard !selectedRoutes.intersection(availableRoutes).isEmpty else { return }
        defaults.set(true, forKey: DefaultsKey.hasConfiguredLines)
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
        let stationChanged = nearestStation?.id != nearest.station.id
        nearestStation = nearest.station
        distanceToStation = nearest.distance
        updateAvailableRoutes()

        if stationChanged, !availableRoutes.isEmpty, selectedRoutes.intersection(availableRoutes).isEmpty {
            selectedRoutes = Set(availableRoutes)
            persistSelection()
        }
    }

    private func updateAvailableRoutes() {
        guard let station = nearestStation else {
            availableRoutes = []
            return
        }
        availableRoutes = RouteID.sorted(
            allArrivals.lazy.filter { $0.stationID == station.id }.map(\.routeID)
        )

        if !defaults.bool(forKey: DefaultsKey.hasConfiguredLines), selectedRoutes.isEmpty {
            selectedRoutes = Set(availableRoutes)
            persistSelection()
        }
    }

    private func persistSelection() {
        defaults.set(RouteID.sorted(selectedRoutes), forKey: DefaultsKey.selectedRoutes)
    }
}

