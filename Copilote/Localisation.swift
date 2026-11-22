import CoreLocation
import Observation

/// L'autorisation de voir la position de l'appareil, demandée seulement quand on touche « Ma position » sur la carte.
@MainActor @Observable
final class Localisation: NSObject, CLLocationManagerDelegate {
    static let shared = Localisation()

    private let gestionnaire = CLLocationManager()
    private(set) var statut: CLAuthorizationStatus

    override private init() {
        statut = gestionnaire.authorizationStatus
        super.init()
        gestionnaire.delegate = self
    }

    var autorisee: Bool {
        #if os(iOS)
        statut == .authorizedWhenInUse || statut == .authorizedAlways
        #else
        statut == .authorizedAlways || statut == .authorized
        #endif
    }

    var refusee: Bool { statut == .denied || statut == .restricted }

    /// Demande l'autorisation si elle n'a jamais été demandée ; rend `true` si la position peut être affichée.
    func demander() async -> Bool {
        if statut == .notDetermined {
            gestionnaire.requestWhenInUseAuthorization()
            // La réponse arrive par le délégué ; on l'attend (au plus une minute, le temps que la personne choisisse).
            var attente = 0
            while statut == .notDetermined, attente < 600 {
                try? await Task.sleep(for: .milliseconds(100))
                attente += 1
            }
        }
        return autorisee
    }

    /// Ma position actuelle : juste après l'autorisation, Plans ne la connaît pas encore, on l'attend quelques secondes.
    func coordonnee() async -> CLLocationCoordinate2D? {
        if let l = gestionnaire.location, -l.timestamp.timeIntervalSinceNow < 60 { return l.coordinate }
        gestionnaire.requestLocation()
        for _ in 0..<50 {
            if let l = gestionnaire.location { return l.coordinate }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.statut = s }
    }
}
