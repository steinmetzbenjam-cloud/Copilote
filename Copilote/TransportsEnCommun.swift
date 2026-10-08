import SwiftUI
import MapKit

/// Un tronçon d'un itinéraire en transports en commun : une marche, ou un trajet en métro, bus, train, tram…
struct EtapeCommun: Codable, Equatable {
    /// « MARCHE » ou « TRANSPORT ».
    var mode: String
    /// Type de véhicule renvoyé par Google (SUBWAY, BUS, TRAIN, TRAM, FERRY…).
    var vehicule: String?
    var ligne: String?
    var nomLigne: String?
    var couleur: String?
    var couleurTexte: String?
    var depart: String?
    var arrivee: String?
    var direction: String?
    var arrets: Int?
    var heureDepart: Date?
    var heureArrivee: Date?
    var secondes: Int
    var metres: Int
    /// Tracé du tronçon, en polyligne encodée (format Google).
    var trace: String

    var estMarche: Bool { mode == "MARCHE" }

    var symbole: String {
        if estMarche { return "figure.walk" }
        switch vehicule ?? "" {
        case "SUBWAY": return "tram.fill.tunnel"
        case "BUS", "INTERCITY_BUS", "TROLLEYBUS": return "bus.fill"
        case "HEAVY_RAIL", "RAIL", "HIGH_SPEED_TRAIN", "COMMUTER_TRAIN", "LONG_DISTANCE_TRAIN", "TRAIN": return "train.side.front.car"
        case "FERRY": return "ferry.fill"
        case "CABLE_CAR", "GONDOLA_LIFT", "FUNICULAR": return "cablecar.fill"
        default: return "tram.fill"
        }
    }

    var teinte: Color {
        if estMarche { return .gray }
        return couleur.flatMap(Color.init(hexa:)) ?? .blue
    }
}

/// L'itinéraire complet, enregistré avec le transport : il s'affiche hors ligne et sur la carte.
struct ItineraireCommun: Codable, Equatable {
    var secondes: Int
    var metres: Int
    var trace: String
    var etapes: [EtapeCommun]
    var calculeLe: Date
    /// Horaires de passage donnés à titre d'exemple (calculés pour un autre jour que celui du voyage).
    var indicatif: Bool?
    /// « Google » ou « Plans » (Plans ne donne que la durée).
    var source: String?

    var estDureeSeule: Bool { etapes.isEmpty }

    /// « 32 min · 6,4 km »
    var resume: String {
        let minutes = Int((Double(secondes) / 60).rounded())
        let temps = minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
        if metres == 0 { return temps }
        let km = metres >= 1000 ? "\((Double(metres) / 1000).formatted(.number.precision(.fractionLength(1)))) km" : "\(metres) m"
        return "\(temps) · \(km)"
    }

    /// Les lignes empruntées : « M1 › M4 ».
    var lignes: String {
        etapes.filter { !$0.estMarche }.compactMap { $0.ligne ?? $0.nomLigne }.joined(separator: " › ")
    }

    var correspondances: Int { max(etapes.filter { !$0.estMarche }.count - 1, 0) }
}

extension Color {
    /// « #RRGGBB » ou « RRGGBB ».
    init?(hexa: String) {
        var texte = hexa.trimmingCharacters(in: .whitespaces)
        if texte.hasPrefix("#") { texte.removeFirst() }
        guard texte.count == 6, let v = Int(texte, radix: 16) else { return nil }
        self.init(rouge: (v >> 16) & 0xFF, vert: (v >> 8) & 0xFF, bleu: v & 0xFF)
    }
}

/// Polyligne encodée de Google (précision 1e-5) en coordonnées.
enum PolylineGoogle {
    static func decoder(_ texte: String) -> [CLLocationCoordinate2D] {
        let octets = Array(texte.utf8)
        var i = 0, lat = 0, lon = 0
        var points: [CLLocationCoordinate2D] = []
        func lire() -> Int? {
            var resultat = 0, decalage = 0
            while i < octets.count {
                let b = Int(octets[i]) - 63
                i += 1
                resultat |= (b & 0x1F) << decalage
                decalage += 5
                if b < 0x20 { return (resultat & 1) != 0 ? ~(resultat >> 1) : (resultat >> 1) }
            }
            return nil
        }
        while i < octets.count {
            guard let dLat = lire(), let dLon = lire() else { break }
            lat += dLat
            lon += dLon
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return points
    }
}

/// Recherche d'itinéraire en transports en commun avec l'API Routes de Google (la clé Google des Réglages).
/// Plans ne calcule pas ces itinéraires : il ne donne que la durée.
enum RoutesGoogle {
    enum Erreur: LocalizedError {
        case pasDeCle, refuse(String), aucunItineraire(String), illisible

        var errorDescription: String? {
            switch self {
            case .pasDeCle: "Aucune clé Google dans les Réglages."
            case .refuse(let message): "Google a refusé la recherche : \(message)"
            case .aucunItineraire(let detail): "Google n'a trouvé aucun itinéraire en transports en commun entre ces deux lieux. Détail : \(detail)"
            case .illisible: "La réponse de Google n'a pas pu être lue."
            }
        }
    }

    /// Les types de véhicule acceptés par l'API selon le choix « Type » du transport.
    private static func vehicules(pour sousType: String) -> [String]? {
        switch sousType {
        case "Métro": ["SUBWAY"]
        case "Bus": ["BUS"]
        case "Tram": ["LIGHT_RAIL"]
        case "Train": ["TRAIN", "RAIL"]
        default: nil
        }
    }

    /// Cherche l'itinéraire. Les horaires de transport ne sont connus que pour les semaines à venir : si le jour du voyage est trop loin
    /// (ou sans heure), on calcule pour demain à 10 h, heure du lieu, et l'itinéraire est alors donné à titre indicatif.
    static func chercher(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D, sousType: String, depart: Date?) async throws -> ItineraireCommun {
        guard let cle = Cles.lire(.google), !cle.isEmpty else { throw Erreur.pasDeCle }
        let fuseau = await fuseauHoraire(a)
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let demain = calendrier.date(bySettingHour: 10, minute: 0, second: 0,
                                     of: calendrier.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now.addingTimeInterval(86_400)

        var heures: [(date: Date, indicatif: Bool)] = []
        if let depart, depart > .now.addingTimeInterval(120), depart < .now.addingTimeInterval(45 * 86_400) { heures.append((depart, false)) }
        heures.append((demain, true))
        let restreints: [Bool] = vehicules(pour: sousType) == nil ? [false] : [true, false]

        var derniere: Error = Erreur.aucunItineraire("aucune tentative")
        var details: [String] = []
        for restreint in restreints {
            for heure in heures {
                let libelle = "\(restreint ? "type \(sousType)" : "tous types") · \(heure.indicatif ? "demain 10 h" : "heure prévue")"
                do {
                    var resultat = try await appeler(a, b, cle: cle, vehicules: restreint ? vehicules(pour: sousType) : nil, depart: heure.date)
                    resultat.indicatif = heure.indicatif
                    return resultat
                } catch Erreur.aucunItineraire(let detail) {
                    details.append("\(libelle) : \(detail)")
                    derniere = Erreur.aucunItineraire(details.joined(separator: " ; "))
                } catch Erreur.refuse(let message) {
                    // Un refus de Google (clé, facturation) ne s'arrange pas en réessayant autrement.
                    throw Erreur.refuse(message)
                }
            }
        }
        throw derniere
    }

    /// Le fuseau horaire du lieu de départ (pour parler d'« demain 10 h » là-bas).
    private static func fuseauHoraire(_ c: CLLocationCoordinate2D) async -> TimeZone {
        let lieu = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return (try? await CLGeocoder().reverseGeocodeLocation(lieu))?.first?.timeZone ?? .current
    }

    private static func appeler(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, cle: String, vehicules: [String]?, depart: Date?) async throws -> ItineraireCommun {
        func point(_ c: CLLocationCoordinate2D) -> [String: Any] { ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]] }
        var corps: [String: Any] = ["origin": point(a), "destination": point(b), "travelMode": "TRANSIT", "languageCode": "fr"]
        if let vehicules { corps["transitPreferences"] = ["allowedTravelModes": vehicules] }
        if let depart, depart > .now.addingTimeInterval(60) {
            corps["departureTime"] = ISO8601DateFormatter().string(from: depart)
        }
        var requete = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(cle, forHTTPHeaderField: "X-Goog-Api-Key")
        requete.setValue("routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps.travelMode,routes.legs.steps.staticDuration,routes.legs.steps.distanceMeters,routes.legs.steps.polyline.encodedPolyline,routes.legs.steps.transitDetails",
                         forHTTPHeaderField: "X-Goog-FieldMask")
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        requete.timeoutInterval = 25

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
        if code != 200 {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "erreur \(code)"
            if code == 404 { throw Erreur.aucunItineraire("réponse 404 — \(message)") }
            throw Erreur.refuse(message)
        }
        guard let route = (json?["routes"] as? [[String: Any]])?.first else { throw Erreur.aucunItineraire("réponse vide (aucune route)") }
        guard let trace = (route["polyline"] as? [String: Any])?["encodedPolyline"] as? String else { throw Erreur.illisible }

        func secondes(_ texte: Any?) -> Int { Int((texte as? String).flatMap { Double($0.dropLast()) } ?? 0) }
        func date(_ texte: Any?) -> Date? {
            guard let t = texte as? String else { return nil }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: t) ?? ISO8601DateFormatter().date(from: t)
        }

        var etapes: [EtapeCommun] = []
        for jambe in (route["legs"] as? [[String: Any]]) ?? [] {
            for pas in (jambe["steps"] as? [[String: Any]]) ?? [] {
                let tracePas = (pas["polyline"] as? [String: Any])?["encodedPolyline"] as? String ?? ""
                let metres = (pas["distanceMeters"] as? NSNumber)?.intValue ?? 0
                if let t = pas["transitDetails"] as? [String: Any] {
                    let arrets = t["stopDetails"] as? [String: Any]
                    let ligne = t["transitLine"] as? [String: Any]
                    let vehicule = ligne?["vehicle"] as? [String: Any]
                    let debut = date(arrets?["departureTime"]), fin = date(arrets?["arrivalTime"])
                    etapes.append(EtapeCommun(
                        mode: "TRANSPORT", vehicule: vehicule?["type"] as? String,
                        ligne: ligne?["nameShort"] as? String, nomLigne: ligne?["name"] as? String,
                        couleur: ligne?["color"] as? String, couleurTexte: ligne?["textColor"] as? String,
                        depart: (arrets?["departureStop"] as? [String: Any])?["name"] as? String,
                        arrivee: (arrets?["arrivalStop"] as? [String: Any])?["name"] as? String,
                        direction: t["headsign"] as? String, arrets: (t["stopCount"] as? NSNumber)?.intValue,
                        heureDepart: debut, heureArrivee: fin,
                        secondes: secondes(pas["staticDuration"]), metres: metres, trace: tracePas))
                } else {
                    etapes.append(EtapeCommun(mode: "MARCHE", secondes: secondes(pas["staticDuration"]), metres: metres, trace: tracePas))
                }
            }
        }
        guard etapes.contains(where: { !$0.estMarche }) else { throw Erreur.aucunItineraire("itinéraire à pied seulement") }
        return ItineraireCommun(secondes: secondes(route["duration"]), metres: (route["distanceMeters"] as? NSNumber)?.intValue ?? 0,
                                trace: trace, etapes: etapes, calculeLe: .now)
    }
}

/// Le détail d'un itinéraire en transports en commun : tronçons, lignes, arrêts et horaires.
struct DetailItineraireCommun: View {
    var itineraire: ItineraireCommun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill").foregroundStyle(.tint)
                Text(itineraire.resume).fontWeight(.semibold)
                if itineraire.correspondances > 0 {
                    Text("· \(itineraire.correspondances) correspondance\(itineraire.correspondances > 1 ? "s" : "")").foregroundStyle(.secondary)
                }
            }
            if itineraire.estDureeSeule {
                Text("Durée estimée par Plans : sans détail des lignes ni tracé. Ouvre l'itinéraire dans Plans pour le voir en entier.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(itineraire.etapes.enumerated()), id: \.offset) { _, etape in ligne(etape) }
            if itineraire.indicatif == true && !itineraire.estDureeSeule {
                Text("Horaires donnés à titre d'exemple (un jour de semaine ordinaire) : les horaires du voyage ne sont pas encore publiés.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func heure(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "" }

    private func duree(_ s: Int) -> String {
        let m = max(Int((Double(s) / 60).rounded()), 1)
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }

    private func ligne(_ e: EtapeCommun) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: e.symbole).foregroundStyle(.white).frame(width: 30, height: 30)
                .background(Circle().fill(e.teinte))
            VStack(alignment: .leading, spacing: 2) {
                if e.estMarche {
                    Text("Marche · \(duree(e.secondes)) · \(e.metres) m").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        if let l = e.ligne ?? e.nomLigne {
                            Text(l).font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                                .foregroundStyle(e.couleurTexte.flatMap(Color.init(hexa:)) ?? .white)
                                .background(e.teinte, in: RoundedRectangle(cornerRadius: 5))
                        }
                        if let d = e.direction { Text("direction \(d)").font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Text("\(e.depart ?? "—") → \(e.arrivee ?? "—")").font(.subheadline)
                    Text([(heure(e.heureDepart).isEmpty || itineraire.indicatif == true) ? nil : "\(heure(e.heureDepart)) → \(heure(e.heureArrivee))",
                          e.arrets.map { "\($0) arrêt\($0 > 1 ? "s" : "")" }, duree(e.secondes)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Plans ne calcule pas d'itinéraire en transports en commun, mais estime la durée du trajet.
enum EstimationPlans {
    static func estimer(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D) async -> ItineraireCommun? {
        let demande = MKDirections.Request()
        demande.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        demande.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        demande.transportType = .transit
        guard let eta = try? await MKDirections(request: demande).calculateETA() else { return nil }
        return ItineraireCommun(secondes: Int(eta.expectedTravelTime), metres: Int(eta.distance), trace: "", etapes: [], calculeLe: .now,
                                indicatif: true, source: "Plans")
    }

    /// Ouvre l'itinéraire en transports en commun dans l'app Plans.
    @MainActor static func ouvrir(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D, depart: String?, arrivee: String?) {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: a)), cible = MKMapItem(placemark: MKPlacemark(coordinate: b))
        source.name = depart ?? "Départ"
        cible.name = arrivee ?? "Arrivée"
        MKMapItem.openMaps(with: [source, cible], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }
}
