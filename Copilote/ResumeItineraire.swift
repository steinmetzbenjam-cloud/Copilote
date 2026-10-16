import SwiftUI
import CoreLocation

/// Distance et durée d'un trajet, calculées au moment de l'afficher (utilisé par l'Itinéraire).
struct ResumeItineraire: View {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D
    let mode: ModeTransport
    /// Durée corrigée à la main (minutes), affichée à la place de celle calculée.
    var dureeModifiee: Double?
    /// Itinéraire calculé avec Google Maps : il passe avant celui de Plans.
    var google: ItineraireGoogle?
    /// Sans distance ni durée (pas encore calculées, ou introuvables) : rien plutôt que « … ».
    var masquerSiVide = false
    @State private var itineraires = Itineraires.shared

    var body: some View {
        let resume = (google?.trajet ?? itineraires.trajet(a, b, mode))?.resume(dureeModifiee: dureeModifiee)
        Group {
            if let texte = resume ?? (masquerSiVide ? nil : "…") {
                Text(texte).font(.caption).foregroundStyle(.secondary)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
    }
}
