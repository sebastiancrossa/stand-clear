import Combine
@preconcurrency import CoreLocation

extension CLAuthorizationStatus {
    var allowsStandClearLocation: Bool {
        switch self {
        case .authorizedAlways: true
        case .notDetermined, .denied, .restricted: false
        @unknown default: false
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var locationError: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            location = nil
            locationError = "Location access is off for Stand Clear."
        @unknown default:
            location = nil
            locationError = "Location access is unavailable."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        location = newest
        locationError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let coreLocationError = error as? CLError, coreLocationError.code == .locationUnknown {
            return
        }
        locationError = error.localizedDescription
    }
}
