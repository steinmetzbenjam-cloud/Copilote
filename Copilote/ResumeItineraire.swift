import SwiftUI
import CoreLocation

/// Distance et durée d'un trajet, calculées au moment de l'afficher (utilisé par l'Itinéraire).
struct ResumeItineraire: View {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D
    let mode: ModeTransport
    /// Durée corrigée à la main (minutes), affichée à la place de celle calculée.
    var dureeModifiee: Double?
    @State private var itineraires = Itineraires.shared

    var body: some View {
        Text(itineraires.trajet(a, b, mode)?.resume(dureeModifiee: dureeModifiee) ?? "…")
            .font(.caption).foregroundStyle(.secondary)
            .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
    }
}
