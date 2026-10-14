import Foundation
import CoreLocation
import Observation

/// Tracks and requests Location Services permission.
///
/// The app never reads the user's location. macOS treats Wi-Fi network names
/// as location data, because an SSID or BSSID can pinpoint where someone is,
/// so CoreWLAN returns `nil` for both — and nameless scan results — until the
/// app holds Location authorization.
@MainActor
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedAlways || status == .authorized
    }

    var isUndetermined: Bool {
        status == .notDetermined
    }

    /// Denied or restricted: the system will not show the prompt again, so the
    /// only way forward is System Settings.
    var needsSettings: Bool {
        status == .denied || status == .restricted
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openSettings() {
        openSystemSettings(pane: "com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let newStatus = manager.authorizationStatus
        Task { @MainActor in
            self.status = newStatus
        }
    }
}
