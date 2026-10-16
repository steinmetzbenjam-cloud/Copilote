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
    /// Prix par personne en euros (ou en monnaie locale si le drapeau `…Local` est vrai). Optionnels : absents des transports déjà enregistrés.
    /// Fuseaux (identifiants) des heures de départ et d'arrivée, si différents de ceux des lieux.
    var fuseauDepart: String?
    var fuseauArrivee: String?
    var prixAdulte: Double?
    var prixEtudiant: Double?
    var prixEnfant: Double?
    var prixAdulteLocal: Bool?
    var prixEtudiantLocal: Bool?
    var prixEnfantLocal: Bool?
    /// Prix saisi dans la troisième monnaie du voyage (prioritaire sur `…Local`).
    var prixAdulteTierce: Bool?
    var prixEtudiantTierce: Bool?
    var prixEnfantTierce: Bool?
    var prixAdolescent: Double?
    var prixAdolescentLocal: Bool?
    var prixAdolescentTierce: Bool?
    /// Itinéraire en transports en commun cherché avec Google, gardé avec le transport (absent des anciens transports).
    var itineraireCommun: ItineraireCommun?
    /// Durée du trajet corrigée à la main après le calcul, en minutes. Le tracé calculé reste sur la carte ;
    /// un nouveau calcul l'efface.
    var dureeModifiee: Double?
    /// Itinéraire en voiture, à pied ou à vélo calculé avec Google Maps : il remplace celui de Plans sur la carte et pour la durée.
    var itineraireGoogle: ItineraireGoogle?
    /// Voyageurs (uid) non concernés par le prix prévu : ils ne comptent pas dans le Budget. Vide ou nil : tout le monde.
    var exclusBudget: [String]?
    /// Enfants et adolescents (uid) qui paient ici le prix de l'autre tarif : un adolescent au prix enfant, un enfant au prix adolescent.
    var basculesTarif: [String]?

    /// L'itinéraire Google, s'il a été calculé pour ce mode et entre ces deux lieux (il ne vaut plus si une étape a bougé).
    func itineraireGoogle(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> ItineraireGoogle? {
        guard let g = itineraireGoogle, g.mode == mode, g.relie(a, b) else { return nil }
        return g
    }

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

/// Un itinéraire calculé avec l'API Routes de Google, gardé avec le transport (il s'affiche hors ligne et chez tous les voyageurs).
struct ItineraireGoogle: Codable, Equatable {
    var mode: ModeTransport
    var secondes: Int
    var metres: Int
    /// Polyligne encodée de Google.
    var trace: String
    var departLatitude: Double
    var departLongitude: Double
    var arriveeLatitude: Double
    var arriveeLongitude: Double
    var calculeLe: Date

    var points: [CLLocationCoordinate2D] { PolylineGoogle.decoder(trace) }

    var trajet: Trajet { Trajet(points: points, distance: Double(metres), duree: Double(secondes)) }

    /// Vrai si l'itinéraire a été calculé entre ces deux lieux (à une cinquantaine de mètres près).
    func relie(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - departLatitude) < 0.0005 && abs(a.longitude - departLongitude) < 0.0005
            && abs(b.latitude - arriveeLatitude) < 0.0005 && abs(b.longitude - arriveeLongitude) < 0.0005
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
        await calculerMaintenant(a, b, mode, cle: cle)
    }

    /// Recalcule l'itinéraire ; l'ancien reste tracé tant que le nouveau n'est pas trouvé.
    func recalculer(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport) async {
        guard mode.aUnItineraire else { return }
        let cle = Self.cle(a, b, mode)
        guard !enCours.contains(cle) else { return }
        await calculerMaintenant(a, b, mode, cle: cle)
    }

    private func calculerMaintenant(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport, cle: String) async {
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
    var resume: String? { resume(dureeModifiee: nil) }

    /// « 12,4 km · 25 min » ; avec une durée corrigée à la main (en minutes), c'est elle qui s'affiche.
    func resume(dureeModifiee: Double?) -> String? {
        guard let distance, let duree = dureeModifiee.map({ $0 * 60 }) ?? duree else { return nil }
        let km = distance >= 1000 ? "\((distance / 1000).formatted(.number.precision(.fractionLength(1)))) km" : "\(Int(distance)) m"
        let minutes = Int((duree / 60).rounded())
        let temps = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        return "\(km) · \(temps)"
    }
}

extension Transport {
    /// Distance et temps d'un transport sans itinéraire routier (avion, transports en commun) : l'itinéraire enregistré,
    /// sinon la distance à vol d'oiseau et la durée tirée des horaires.
    func resume(depuis etapeDepart: Etape, vers etapeArrivee: Etape) -> String? {
        if let m = dureeModifiee {
            return CategorieEtape.texteDuree(m)
        }
        if let it = itineraireCommun { return it.resume }
        var morceaux: [String] = []
        if let a = etapeDepart.coordonnee, let b = etapeArrivee.coordonnee {
            let km = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
            morceaux.append(km >= 10 ? "\(Int(km.rounded())) km" : "\(km.formatted(.number.precision(.fractionLength(1)))) km")
        }
        if let d = self.depart, let f = self.arrivee {
            var minutes = f.timeIntervalSince(d) / 60
            if minutes < 0 { minutes += 24 * 60 }
            morceaux.append(CategorieEtape.texteDuree(minutes))
        }
        return morceaux.isEmpty ? nil : morceaux.joined(separator: " · ")
    }
}
