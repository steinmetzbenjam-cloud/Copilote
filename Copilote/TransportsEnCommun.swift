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
        case "AIRPLANE": return "airplane"
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

    /// Coordonnées en polyligne encodée (pour enregistrer un tracé venu d'ailleurs que de Google).
    static func encoder(_ points: [CLLocationCoordinate2D]) -> String {
        var texte = ""
        var precLat = 0, precLon = 0
        func ajouter(_ valeur: Int) {
            var v = valeur < 0 ? ~(valeur << 1) : (valeur << 1)
            while v >= 0x20 {
                texte.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63))))
                v >>= 5
            }
            texte.append(Character(UnicodeScalar(UInt8(v + 63))))
        }
        for p in points {
            let lat = Int((p.latitude * 1e5).rounded()), lon = Int((p.longitude * 1e5).rounded())
            ajouter(lat - precLat)
            ajouter(lon - precLon)
            precLat = lat
            precLon = lon
        }
        return texte
    }
}

/// Choisit le service qui sait chercher l'itinéraire : NAVITIME au Japon, Google ailleurs.
enum RechercheCommun {
    static func chercher(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D, sousType: String, depart: Date?) async throws -> ItineraireCommun {
        let departAuJapon = await RoutesNavitime.auJapon(a)
        let arriveeAuJapon = departAuJapon ? true : await RoutesNavitime.auJapon(b)
        guard departAuJapon || arriveeAuJapon else {
            return try await RoutesGoogle.chercher(de: a, vers: b, sousType: sousType, depart: depart)
        }
        if RoutesNavitime.cle != nil {
            return try await RoutesNavitime.chercher(de: a, vers: b, depart: depart)
        }
        // Sans clé RapidAPI, on tente quand même Google, mais il ne donne pas les transports en commun du Japon.
        do {
            return try await RoutesGoogle.chercher(de: a, vers: b, sousType: sousType, depart: depart)
        } catch {
            throw RoutesNavitime.Erreur.pasDeCle
        }
    }
}

/// Itinéraires en train (Shinkansen, JR, lignes privées, métros) au Japon avec NAVITIME : l'API « NAVITIME Route(totalnavi) »
/// sur RapidAPI, avec la même clé RapidAPI que pour AeroDataBox. Google ne fournit pas les transports en commun du Japon
/// à ses API (seuls le site et l'app Google Maps les montrent).
enum RoutesNavitime {
    static let hote = "navitime-route-totalnavi.p.rapidapi.com"
    static let pageAbonnement = URL(string: "https://rapidapi.com/navitimejapan-navitimejapan/api/navitime-route-totalnavi")!

    /// La clé RapidAPI, rangée dans les Réglages avec AeroDataBox (une seule clé par compte RapidAPI).
    static var cle: String? {
        guard let c = Cles.lire(.aerodatabox), !c.isEmpty else { return nil }
        return c
    }

    enum Erreur: LocalizedError {
        case pasDeCle, nonAbonne(String), quota, parametre(String), refuse(String), aucunItineraire(String), illisible

        var errorDescription: String? {
            switch self {
            case .pasDeCle:
                "Google ne donne pas les trains du Japon à ses API. Au Japon, Copilote les cherche avec NAVITIME : ajoute ta clé RapidAPI dans les Réglages (section RapidAPI), puis abonne-toi à « NAVITIME Route(totalnavi) » sur RapidAPI."
            case .nonAbonne(let message):
                "RapidAPI refuse la recherche : abonne-toi à « NAVITIME Route(totalnavi) » sur RapidAPI, avec le compte de ta clé (lien dans les Réglages). Détail : \(message)"
            case .quota: "Le nombre de recherches NAVITIME de ton offre RapidAPI est atteint pour ce mois."
            case .parametre(let message), .refuse(let message): "NAVITIME a refusé la recherche : \(message)"
            case .aucunItineraire(let detail): "NAVITIME n'a trouvé aucun itinéraire en train entre ces deux lieux. \(detail)"
            case .illisible: "La réponse de NAVITIME n'a pas pu être lue."
            }
        }
    }

    /// Vrai si le lieu est au Japon (le cadre de l'archipel, puis le pays donné par Plans, pour écarter la Corée).
    static func auJapon(_ c: CLLocationCoordinate2D) async -> Bool {
        guard (20...46).contains(c.latitude), (122...154).contains(c.longitude) else { return false }
        let lieu = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        if let code = lieu?.isoCountryCode { return code == "JP" }
        return lieu?.timeZone?.identifier == "Asia/Tokyo"
    }

    /// Heures « murales », comme partout dans Copilote : 10 h 05 à Tokyo reste 10 h 05, quel que soit le fuseau de l'appareil.
    private static func formateur() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }

    /// Cherche l'itinéraire. Sans heure prévue, on calcule pour demain à 10 h, et l'itinéraire est donné à titre indicatif.
    static func chercher(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D, depart: Date?) async throws -> ItineraireCommun {
        guard let cle else { throw Erreur.pasDeCle }
        let calendrier = Calendar.current
        let demain = calendrier.date(bySettingHour: 10, minute: 0, second: 0,
                                     of: calendrier.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now.addingTimeInterval(86_400)
        let heure = depart ?? demain
        // Le tracé des voies (une seconde requête) arrive pendant qu'on cherche l'itinéraire.
        async let voies = traceDesVoies(a, b, cle: cle, heure: heure)
        // Noms en anglais si l'offre le permet, sinon en japonais.
        var derniere: Error = Erreur.illisible
        for anglais in [true, false] {
            do {
                var resultat = try await appeler(a, b, cle: cle, heure: heure, anglais: anglais)
                resultat.indicatif = depart == nil
                return suivre(resultat, await voies)
            } catch Erreur.parametre(let message) {
                derniere = Erreur.parametre(message)
            }
        }
        throw derniere
    }

    /// Les paramètres communs à la recherche de l'itinéraire et à celle de son tracé (le même trajet doit sortir des deux).
    private static func parametres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, heure: Date) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start", value: "\(a.latitude),\(a.longitude)"),
            URLQueryItem(name: "goal", value: "\(b.latitude),\(b.longitude)"),
            URLQueryItem(name: "start_time", value: formateur().string(from: heure)),
            URLQueryItem(name: "unuse", value: "domestic_flight"),
            URLQueryItem(name: "datum", value: "wgs84"),
            URLQueryItem(name: "coord_unit", value: "degree"),
        ]
    }

    private static func requete(_ chemin: String, _ parametres: [URLQueryItem], cle: String) -> URLRequest {
        var adresse = URLComponents(string: "https://\(hote)/\(chemin)")!
        adresse.queryItems = parametres
        var requete = URLRequest(url: adresse.url!)
        requete.setValue(cle, forHTTPHeaderField: "X-RapidAPI-Key")
        requete.setValue(hote, forHTTPHeaderField: "X-RapidAPI-Host")
        requete.timeoutInterval = 25
        return requete
    }

    private static func appeler(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, cle: String, heure: Date,
                                anglais: Bool) async throws -> ItineraireCommun {
        var liste = parametres(a, b, heure: heure) + [URLQueryItem(name: "limit", value: "1")]
        if anglais { liste.append(URLQueryItem(name: "lang", value: "en")) }

        let (donnees, reponse) = try await URLSession.shared.data(for: requete("route_transit", liste, cle: cle))
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
        if code != 200 {
            let message = (json?["message"] as? String)
                ?? ((json?["errors"] as? [[String: Any]])?.first?["message"] as? String)
                ?? String(data: donnees.prefix(300), encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } ?? "erreur \(code)"
            switch code {
            case 401, 403: throw Erreur.nonAbonne(message)
            case 429: throw Erreur.quota
            case 400: throw Erreur.parametre(message)
            case 404: throw Erreur.aucunItineraire(message)
            default: throw Erreur.refuse(message)
            }
        }
        guard let item = (json?["items"] as? [[String: Any]])?.first else { throw Erreur.aucunItineraire("") }
        let sections = item["sections"] as? [[String: Any]] ?? []

        func coordonnee(_ s: [String: Any]?) -> CLLocationCoordinate2D? {
            guard let c = s?["coord"] as? [String: Any],
                  let lat = (c["lat"] as? NSNumber)?.doubleValue, let lon = (c["lon"] as? NSNumber)?.doubleValue else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        func texte(_ v: Any?) -> String? {
            let t = (v as? String) ?? ((v as? [String: Any])?["name"] as? String)
            return t?.trimmingCharacters(in: .whitespaces).isEmpty == false ? t : nil
        }
        func date(_ v: Any?) -> Date? {
            guard let t = v as? String, t.count >= 19 else { return nil }
            return formateur().date(from: String(t.prefix(19)))
        }
        func nombre(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

        // Chaque tronçon part d'abord en ligne droite d'un point à l'autre ; `suivre` la remplace par le tracé des voies.
        var etapes: [EtapeCommun] = []
        for (i, s) in sections.enumerated() where s["type"] as? String == "move" {
            let avant = i > 0 ? sections[i - 1] : nil, apres = i + 1 < sections.count ? sections[i + 1] : nil
            let points = [coordonnee(avant), coordonnee(apres)].compactMap { $0 }
            let mouvement = s["move"] as? String ?? ""
            let secondes = nombre(s["time"]) * 60, metres = nombre(s["distance"])
            if mouvement == "walk" {
                etapes.append(EtapeCommun(mode: "MARCHE", secondes: secondes, metres: metres, trace: PolylineGoogle.encoder(points)))
                continue
            }
            let transport = s["transport"] as? [String: Any]
            let lien = (transport?["links"] as? [[String: Any]])?.first
            etapes.append(EtapeCommun(
                mode: "TRANSPORT", vehicule: vehicule(mouvement),
                ligne: nil, nomLigne: texte(transport?["self_name"]) ?? texte(s["line_name"]) ?? texte(transport?["name"]),
                couleur: transport?["color"] as? String, couleurTexte: nil,
                depart: texte(avant?["name"]), arrivee: texte(apres?["name"]),
                direction: texte(lien?["destination"]) ?? texte(transport?["destination"]), arrets: nil,
                heureDepart: date(s["from_time"]), heureArrivee: date(s["to_time"]),
                secondes: secondes, metres: metres, trace: PolylineGoogle.encoder(points)))
        }
        guard etapes.contains(where: { !$0.estMarche }) else { throw Erreur.aucunItineraire("Itinéraire à pied seulement.") }
        let resume = (item["summary"] as? [String: Any])?["move"] as? [String: Any]
        return ItineraireCommun(secondes: nombre(resume?["time"]) * 60, metres: nombre(resume?["distance"]),
                                trace: PolylineGoogle.encoder(etapes.flatMap { PolylineGoogle.decoder($0.trace) }),
                                etapes: etapes, calculeLe: .now, source: "NAVITIME")
    }

    /// Les types de NAVITIME ramenés à ceux de Google, pour l'icône du tronçon.
    private static func vehicule(_ mouvement: String) -> String? {
        switch mouvement {
        case "superexpress_train": "HIGH_SPEED_TRAIN"
        case "sleeper_ultraexpress", "ultraexpress_train", "express_train", "rapid_train", "semiexpress_train", "local_train": "TRAIN"
        case "shuttle_bus", "local_bus", "highway_bus": "BUS"
        case "ferry": "FERRY"
        case "domestic_flight": "AIRPLANE"
        default: nil
        }
    }

    /// Le tracé complet du trajet, voies ferrées comprises, de bout en bout (`/shape_transit`). Sans l'option
    /// « transport_shape », NAVITIME ne trace que la marche. Vide si le tracé n'a pas pu être obtenu.
    private static func traceDesVoies(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, cle: String, heure: Date) async -> [CLLocationCoordinate2D] {
        let liste = parametres(a, b, heure: heure) + [URLQueryItem(name: "format", value: "geojson"),
                                                     URLQueryItem(name: "options", value: "transport_shape")]
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: requete("shape_transit", liste, cle: cle)),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: donnees) else { return [] }
        // Les morceaux arrivent dans l'ordre du trajet : on les met bout à bout.
        var ligne: [CLLocationCoordinate2D] = []
        for morceau in traces(json) {
            if let dernier = ligne.last, let premier = morceau.first, metres(dernier, premier) < 1 {
                ligne += morceau.dropFirst()
            } else {
                ligne += morceau
            }
        }
        return ligne
    }

    /// Les tracés d'un GeoJSON (lignes en [longitude, latitude]).
    private static func traces(_ formes: Any?) -> [[CLLocationCoordinate2D]] {
        func ligne(_ v: Any?) -> [CLLocationCoordinate2D] {
            ((v as? [[Any]]) ?? []).compactMap { p in
                guard p.count >= 2, let lon = (p[0] as? NSNumber)?.doubleValue, let lat = (p[1] as? NSNumber)?.doubleValue else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        var resultat: [[CLLocationCoordinate2D]] = []
        for f in ((formes as? [String: Any])?["features"] as? [[String: Any]]) ?? [] {
            guard let g = f["geometry"] as? [String: Any] else { continue }
            switch g["type"] as? String {
            case "LineString": resultat.append(ligne(g["coordinates"]))
            case "MultiLineString": resultat += ((g["coordinates"] as? [Any]) ?? []).map(ligne)
            default: break
            }
        }
        return resultat.filter { $0.count >= 2 }
    }

    /// Distance approchée en mètres (largement assez précise à l'échelle d'un trajet).
    private static func metres(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D) -> Double {
        let x = (q.longitude - p.longitude) * cos((p.latitude + q.latitude) / 2 * .pi / 180)
        let y = q.latitude - p.latitude
        return (x * x + y * y).squareRoot() * 111_195
    }

    /// Remplace la ligne droite de chaque tronçon par le morceau du tracé complet qui va d'une de ses extrémités à l'autre.
    static func suivre(_ itineraire: ItineraireCommun, _ ligne: [CLLocationCoordinate2D]) -> ItineraireCommun {
        guard ligne.count >= 2 else { return itineraire }
        var resultat = itineraire
        var curseur = 0
        var tout: [CLLocationCoordinate2D] = []
        for i in resultat.etapes.indices {
            let bouts = PolylineGoogle.decoder(resultat.etapes[i].trace)
            guard let a = bouts.first, let b = bouts.last, bouts.count >= 2 else { continue }
            if let morceau = decouper(ligne, de: a, vers: b, curseur: &curseur) {
                resultat.etapes[i].trace = PolylineGoogle.encoder(morceau)
                tout += morceau
            } else {
                tout += bouts
            }
        }
        resultat.trace = PolylineGoogle.encoder(tout)
        return resultat
    }

    /// Le morceau du tracé entre les points les plus proches de `a` puis de `b`, en avançant dans le sens du trajet.
    /// `nil` si le tracé passe loin de l'un des deux (plus de 2 km) : le tronçon garde alors sa ligne droite.
    private static func decouper(_ ligne: [CLLocationCoordinate2D], de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D,
                                 curseur: inout Int) -> [CLLocationCoordinate2D]? {
        guard curseur < ligne.count else { return nil }
        func plusProche(de p: CLLocationCoordinate2D, depuis debut: Int) -> (indice: Int, distance: Double) {
            var meilleur = (indice: debut, distance: Double.infinity)
            for j in debut..<ligne.count {
                let d = metres(ligne[j], p)
                if d < meilleur.distance { meilleur = (j, d) }
            }
            return meilleur
        }
        let depart = plusProche(de: a, depuis: curseur)
        let arrivee = plusProche(de: b, depuis: depart.indice)
        guard depart.distance < 2000, arrivee.distance < 2000, arrivee.indice > depart.indice else { return nil }
        curseur = arrivee.indice
        return [a] + ligne[depart.indice...arrivee.indice] + [b]
    }
}

/// Recherche d'itinéraire en transports en commun avec l'API Routes de Google (la clé Google des Réglages).
/// Plans ne calcule pas ces itinéraires : il ne donne que la durée.
enum RoutesGoogle {
    enum Erreur: LocalizedError {
        case pasDeCle, refuse(String), aucunItineraire(String), illisible, trajetIntrouvable(ModeTransport)

        var errorDescription: String? {
            switch self {
            case .pasDeCle: "Aucune clé Google dans les Réglages."
            case .refuse(let message): "Google a refusé la recherche : \(message)"
            case .aucunItineraire(let detail): "Google n'a trouvé aucun itinéraire en transports en commun entre ces deux lieux. Détail : \(detail)"
            case .illisible: "La réponse de Google n'a pas pu être lue."
            case .trajetIntrouvable(let mode): "Google Maps n'a trouvé aucun itinéraire \(mode == .pied ? "à pied" : mode == .velo ? "à vélo" : "en voiture") entre ces deux lieux."
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

extension RoutesGoogle {
    /// Itinéraire en voiture, à pied ou à vélo avec Google Maps (API Routes, la clé Google des Réglages).
    static func itineraire(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D, mode: ModeTransport) async throws -> ItineraireGoogle {
        guard let cle = Cles.lire(.google), !cle.isEmpty else { throw Erreur.pasDeCle }
        func point(_ c: CLLocationCoordinate2D) -> [String: Any] { ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]] }
        let modeGoogle = switch mode {
        case .pied: "WALK"
        case .velo: "BICYCLE"
        default: "DRIVE"
        }
        let corps: [String: Any] = ["origin": point(a), "destination": point(b), "travelMode": modeGoogle, "languageCode": "fr"]
        var requete = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(cle, forHTTPHeaderField: "X-Goog-Api-Key")
        requete.setValue("routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline", forHTTPHeaderField: "X-Goog-FieldMask")
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        requete.timeoutInterval = 25

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
        if code != 200 {
            throw Erreur.refuse(((json?["error"] as? [String: Any])?["message"] as? String) ?? "erreur \(code)")
        }
        guard let route = (json?["routes"] as? [[String: Any]])?.first,
              let trace = (route["polyline"] as? [String: Any])?["encodedPolyline"] as? String else {
            throw Erreur.trajetIntrouvable(mode)
        }
        let secondes = Int((route["duration"] as? String).flatMap { Double($0.dropLast()) } ?? 0)
        return ItineraireGoogle(mode: mode, secondes: secondes, metres: (route["distanceMeters"] as? NSNumber)?.intValue ?? 0, trace: trace,
                                departLatitude: a.latitude, departLongitude: a.longitude,
                                arriveeLatitude: b.latitude, arriveeLongitude: b.longitude, calculeLe: .now)
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
            if itineraire.source == "NAVITIME" {
                Text(itineraire.indicatif == true
                     ? "Itinéraire NAVITIME calculé sans heure de départ : saisis l'heure prévue puis relance la recherche pour avoir les horaires."
                     : "Itinéraire NAVITIME : horaires estimés d'après le temps de parcours moyen des trains, à vérifier sur place (Shinkansen à réserver).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if itineraire.indicatif == true && !itineraire.estDureeSeule {
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

    /// L'itinéraire en transports en commun sur Google Maps (site ou app) : il couvre aussi le Japon, sans clé.
    static func lienGoogleMaps(de a: CLLocationCoordinate2D, vers b: CLLocationCoordinate2D) -> URL {
        var adresse = URLComponents(string: "https://www.google.com/maps/dir/")!
        adresse.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: "\(a.latitude),\(a.longitude)"),
            URLQueryItem(name: "destination", value: "\(b.latitude),\(b.longitude)"),
            URLQueryItem(name: "travelmode", value: "transit"),
        ]
        return adresse.url!
    }
}
