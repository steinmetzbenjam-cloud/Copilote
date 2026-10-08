import Foundation
import MapKit
import Observation

enum ModeTransport: String, Codable, CaseIterable, Identifiable {
    case avion, voiture, pied, velo, commun

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .avion: "Avion"
        case .voiture: "Voiture"
        case .pied: "À pied"
        case .velo: "Vélo"
        case .commun: "Transports en commun"
        }
    }

    var libelleCourt: String {
        switch self {
        case .commun: "En commun"
        default: libelle
        }
    }

    var symbole: String {
        switch self {
        case .avion: "airplane"
        case .voiture: "car.fill"
        case .pied: "figure.walk"
        case .velo: "bicycle"
        case .commun: "tram.fill"
        }
    }

    /// Choix proposés selon le mode.
    var sousTypes: [String] {
        switch self {
        case .avion: ["Économique", "Premium", "Affaires", "Première"]
        case .voiture: ["Voiture personnelle", "Location", "Taxi / VTC", "Covoiturage"]
        case .pied: []
        case .velo: ["Vélo personnel", "Location", "Libre-service"]
        case .commun: ["Train", "Bus", "Métro", "Tram", "Ferry"]
        }
    }

    var titreSousType: String {
        switch self {
        case .avion: "Classe"
        case .commun: "Type"
        default: "Véhicule"
        }
    }

    /// Un itinéraire est calculé et tracé sur la carte.
    var aUnItineraire: Bool { self == .voiture || self == .pied || self == .velo }
}

/// Le trajet qui mène d'une étape à la suivante.
struct Transport: Codable, Equatable {
    var mode: ModeTransport = .voiture
    var sousType = ""
    /// Compagnie aérienne, loueur ou opérateur.
    var compagnie = ""
    /// Numéro de vol ou ligne.
    var numero = ""
    /// Aéroport, gare ou station de départ / d'arrivée.
    var de = ""
    var vers = ""
    var depart: Date?
    var arrivee: Date?
    var notes = ""
    /// Transport d'aller ou de retour : le lieu de départ et le lieu d'arrivée, avec leurs coordonnées (le trait de la carte les relie).
    /// Optionnels : les transports déjà enregistrés n'ont pas ces clés.
    var departLieu: String?
    var departLatitude: Double?
    var departLongitude: Double?
    var arriveeLieu: String?
    var arriveeLatitude: Double?
    var arriveeLongitude: Double?

    var departCoordonnee: CLLocationCoordinate2D? {
        guard let departLatitude, let departLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: departLatitude, longitude: departLongitude)
    }
    var arriveeCoordonnee: CLLocationCoordinate2D? {
        guard let arriveeLatitude, let arriveeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: arriveeLatitude, longitude: arriveeLongitude)
    }
}

extension Etape {
    /// Transport pour aller de cette étape à la suivante du même jour.
    var transport: Transport? {
        get { transportJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Transport.self, from: $0) } }
        set {
            transportJSON = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

extension Voyage {
    private static func decoder(_ json: String?) -> Transport? {
        json.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Transport.self, from: $0) }
    }
    private static func encoder(_ t: Transport?) -> String? {
        t.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
    }
    /// Transport pour rejoindre la première étape du voyage.
    var transportAller: Transport? {
        get { Self.decoder(transportAllerJSON) }
        set { transportAllerJSON = Self.encoder(newValue) }
    }
    /// Transport pour rentrer après la dernière étape.
    var transportRetour: Transport? {
        get { Self.decoder(transportRetourJSON) }
        set { transportRetourJSON = Self.encoder(newValue) }
    }

    /// Les étapes et hébergements placés sur un jour, dans l'ordre du voyage.
    var elementsDuVoyage: [Etape] {
        jours.flatMap { etapes(du: $0) + hebergements(apres: $0) }
    }
}

struct Trajet {
    var points: [CLLocationCoordinate2D]
    /// Mètres et secondes, quand un itinéraire a été calculé.
    var distance: Double?
    var duree: TimeInterval?
}

/// Itinéraires calculés avec Plans, gardés en mémoire pour ne pas les redemander.
@MainActor @Observable
final class Itineraires {
    static let shared = Itineraires()
    private(set) var trajets: [String: Trajet] = [:]
    private var enCours: Set<String> = []

    static func cle(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport) -> String {
        String(format: "%.5f,%.5f|%.5f,%.5f|%@", a.latitude, a.longitude, b.latitude, b.longitude, mode.rawValue)
    }

    func trajet(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport) -> Trajet? {
        trajets[Self.cle(a, b, mode)]
    }

    /// Cherche l'itinéraire le plus court. En cas d'échec, rien n'est mémorisé et la carte garde une ligne droite.
    func charger(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport) async {
        guard mode.aUnItineraire else { return }
        let cle = Self.cle(a, b, mode)
        guard trajets[cle] == nil, !enCours.contains(cle) else { return }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        // Dans une tâche à part : si la vue qui demande disparaît ou se recalcule (ouverture du voyage), le calcul continue.
        if let trajet = await Task(operation: { await Self.calculer(a, b, mode) }).value {
            trajets[cle] = trajet
        }
    }

    /// Plans refuse parfois les premières demandes (trop de requêtes d'un coup à l'ouverture d'un voyage) : on réessaie.
    private nonisolated static func calculer(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport) async -> Trajet? {
        let requete = MKDirections.Request()
        requete.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        requete.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        // Plans n'a pas de mode vélo : on suit les chemins piétons, avec une durée à 15 km/h.
        requete.transportType = mode == .voiture ? .automobile : .walking
        requete.requestsAlternateRoutes = true
        for tentative in 1...4 {
            if let reponse = try? await MKDirections(request: requete).calculate(),
               let route = reponse.routes.min(by: { $0.distance < $1.distance }) {
                let n = route.polyline.pointCount
                var points = [CLLocationCoordinate2D](repeating: .init(), count: n)
                route.polyline.getCoordinates(&points, range: NSRange(location: 0, length: n))
                let duree = mode == .velo ? route.distance / (15_000.0 / 3600) : route.expectedTravelTime
                return Trajet(points: points, distance: route.distance, duree: duree)
            }
            try? await Task.sleep(for: .seconds(Double(tentative) * 1.5))
        }
        return nil
    }

    /// Courbe en arc, comme la trajectoire d'un vol.
    static func arc(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let dLat = b.latitude - a.latitude, dLon = b.longitude - a.longitude
        let controle = CLLocationCoordinate2D(
            latitude: (a.latitude + b.latitude) / 2 + dLon * 0.2,
            longitude: (a.longitude + b.longitude) / 2 - dLat * 0.2)
        return (0...48).map { i in
            let t = Double(i) / 48, u = 1 - t
            return CLLocationCoordinate2D(
                latitude: u * u * a.latitude + 2 * u * t * controle.latitude + t * t * b.latitude,
                longitude: u * u * a.longitude + 2 * u * t * controle.longitude + t * t * b.longitude)
        }
    }
}

extension Trajet {
    var resume: String? {
        guard let distance, let duree else { return nil }
        let km = distance >= 1000 ? "\((distance / 1000).formatted(.number.precision(.fractionLength(1)))) km" : "\(Int(distance)) m"
        let minutes = Int((duree / 60).rounded())
        let temps = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        return "\(km) · \(temps)"
    }
}
