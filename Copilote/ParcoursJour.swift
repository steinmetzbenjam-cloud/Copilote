import SwiftUI
import MapKit
import CoreLocation

// MARK: - Soleil

/// Position du soleil (algorithme de la NOAA, à une minute près) : hauteur au-dessus de l'horizon, lever et coucher.
enum Soleil {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Déclinaison du soleil (radians) et équation du temps (minutes) à cet instant.
    private static func elements(_ date: Date) -> (declinaison: Double, equation: Double) {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t) + sin(rad(3 * m)) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let declinaison = asin(sin(rad(eps)) * sin(rad(lambda)))
        let y = pow(tan(rad(eps) / 2), 2)
        let equation = 4 * deg(y * sin(2 * rad(l0)) - 2 * e * sin(rad(m)) + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
                               - 0.5 * y * y * sin(4 * rad(l0)) - 1.25 * e * e * sin(2 * rad(m)))
        return (declinaison, equation)
    }

    private static func minutesUTC(_ date: Date) -> Double {
        let s = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        return (s < 0 ? s + 86_400 : s) / 60
    }

    /// Hauteur du soleil au-dessus de l'horizon, en degrés (négative la nuit).
    static func hauteur(_ date: Date, _ c: CLLocationCoordinate2D) -> Double {
        let (declinaison, equation) = elements(date)
        let solaire = minutesUTC(date) + equation + 4 * c.longitude
        let angle = rad(solaire / 4 - 180)
        let lat = rad(c.latitude)
        let cosZ = sin(lat) * sin(declinaison) + cos(lat) * cos(declinaison) * cos(angle)
        return 90 - deg(acos(min(max(cosZ, -1), 1)))
    }

    /// Lever et coucher du soleil, ce jour-là (date du calendrier de l'app) dans le fuseau `zone`.
    /// Nil pendant la nuit polaire ou le jour polaire.
    static func leverCoucher(jour: Date, _ c: CLLocationCoordinate2D, zone: TimeZone) -> (lever: Date, coucher: Date)? {
        let midi = ParcoursJour.instant(jour, 12 * 60, zone: zone)
        func evenement(_ signe: Double) -> Date? {
            var instant = midi
            // Deux passes : la position du soleil est recalculée à l'heure trouvée.
            for _ in 0..<2 {
                let (declinaison, equation) = elements(instant)
                let lat = rad(c.latitude)
                let cosH = cos(rad(90.833)) / (cos(lat) * cos(declinaison)) - tan(lat) * tan(declinaison)
                guard cosH >= -1, cosH <= 1 else { return nil }
                let h = deg(acos(cosH))
                var ecart = 720 - 4 * c.longitude - equation - minutesUTC(midi)
                while ecart > 720 { ecart -= 1440 }
                while ecart < -720 { ecart += 1440 }
                instant = midi.addingTimeInterval((ecart + signe * 4 * h) * 60)
            }
            return instant
        }
        guard let lever = evenement(-1), let coucher = evenement(1) else { return nil }
        return (lever, coucher)
    }

    /// Couleurs du ciel (haut, bas) selon la hauteur du soleil, de la nuit au plein jour en passant par l'aube.
    static func couleursCiel(hauteur: Double, gris: Double) -> (haut: Color, bas: Color) {
        typealias RVB = (Double, Double, Double)
        let reperes: [(Double, RVB, RVB)] = [
            (-18, (0.03, 0.04, 0.12), (0.06, 0.08, 0.20)),
            (-10, (0.07, 0.09, 0.25), (0.20, 0.18, 0.38)),
            (-4, (0.16, 0.20, 0.45), (0.72, 0.42, 0.40)),
            (0, (0.27, 0.37, 0.66), (0.97, 0.60, 0.36)),
            (6, (0.24, 0.47, 0.82), (0.92, 0.78, 0.58)),
            (15, (0.22, 0.46, 0.80), (0.46, 0.67, 0.93)),
        ]
        func melange(_ a: RVB, _ b: RVB, _ f: Double) -> RVB { (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f) }
        var haut = reperes.first!.1, bas = reperes.first!.2
        if hauteur >= reperes.last!.0 {
            haut = reperes.last!.1; bas = reperes.last!.2
        } else if let i = reperes.indices.dropLast().first(where: { hauteur >= reperes[$0].0 && hauteur < reperes[$0 + 1].0 }) {
            let f = (hauteur - reperes[i].0) / (reperes[i + 1].0 - reperes[i].0)
            haut = melange(reperes[i].1, reperes[i + 1].1, f)
            bas = melange(reperes[i].2, reperes[i + 1].2, f)
        }
        // Par temps couvert, le ciel tourne au gris (de même luminosité).
        func griser(_ c: RVB) -> Color {
            let l = 0.3 * c.0 + 0.59 * c.1 + 0.11 * c.2
            let g = melange(c, (l * 1.05, l * 1.07, l * 1.12), gris)
            return Color(red: g.0, green: g.1, blue: g.2)
        }
        return (griser(haut), griser(bas))
    }
}

// MARK: - Météo heure par heure

struct MeteoHeure: Codable, Equatable {
    var date: Date
    var code: Int
    var temperature: Double

    private var jour: MeteoJour { MeteoJour(date: date, tMin: temperature, tMax: temperature, code: code) }
    var symbole: String { jour.symbole }
    var libelle: String { jour.libelle }

    /// Part de gris dans le ciel.
    var gris: Double {
        switch code {
        case 0: 0
        case 1, 2: 0.15
        case 3: 0.55
        case 45, 48: 0.6
        case 51...57, 71...77, 85, 86: 0.5
        case 61...67, 80...82: 0.65
        case 95...99: 0.75
        default: 0.4
        }
    }
}

/// Météo heure par heure d'une journée (Open-Meteo, prévisions et jours passés), gardée pour le hors-ligne.
@MainActor @Observable
final class MeteoHoraire {
    static let shared = MeteoHoraire()
    private(set) var heures: [String: [MeteoHeure]] = [:]
    private var enCours: Set<String> = []

    /// Un lieu par demi-degré : la météo ne change guère à l'intérieur.
    nonisolated static func lieu(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (c.latitude * 2).rounded() / 2, longitude: (c.longitude * 2).rounded() / 2)
    }

    private static func jourTexte(_ jour: Date, decalage: Int = 0) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: decalage, to: jour) ?? jour
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func cle(_ c: CLLocationCoordinate2D, _ jour: Date) -> String {
        let l = lieu(c)
        return String(format: "%.1f,%.1f|", l.latitude, l.longitude) + jourTexte(jour)
    }

    func liste(_ c: CLLocationCoordinate2D, jour: Date) -> [MeteoHeure] {
        let cle = Self.cle(c, jour)
        if let v = heures[cle] { return v }
        if let d = UserDefaults.standard.data(forKey: "meteoHeures-\(cle)"), let v = try? JSONDecoder().decode([MeteoHeure].self, from: d) {
            heures[cle] = v
            return v
        }
        return []
    }

    func charger(_ c: CLLocationCoordinate2D, jour: Date) async {
        let cle = Self.cle(c, jour)
        guard heures[cle] == nil, !enCours.contains(cle) else { return }
        if !liste(c, jour: jour).isEmpty, !Self.estProche(jour) { return }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        let l = Self.lieu(c)
        var composants = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // La veille et le lendemain aussi : la journée locale déborde sur deux jours en temps universel.
        composants.queryItems = [
            URLQueryItem(name: "latitude", value: String(l.latitude)),
            URLQueryItem(name: "longitude", value: String(l.longitude)),
            URLQueryItem(name: "hourly", value: "weather_code,temperature_2m"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "start_date", value: Self.jourTexte(jour, decalage: -1)),
            URLQueryItem(name: "end_date", value: Self.jourTexte(jour, decalage: 1)),
        ]
        guard let url = composants.url,
              let (donnees, reponse) = try? await URLSession.shared.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let h = json["hourly"] as? [String: Any],
              let temps = h["time"] as? [String], let codes = h["weather_code"] as? [Any] else { return }
        let temperatures = h["temperature_2m"] as? [Any] ?? []
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd'T'HH:mm"
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "GMT")
        var liste: [MeteoHeure] = []
        for (i, texte) in temps.enumerated() {
            guard i < codes.count, let date = format.date(from: texte), let code = (codes[i] as? NSNumber)?.intValue else { continue }
            let t = i < temperatures.count ? (temperatures[i] as? NSNumber)?.doubleValue ?? .nan : .nan
            liste.append(MeteoHeure(date: date, code: code, temperature: t))
        }
        guard !liste.isEmpty else { return }
        heures[cle] = liste
        if let d = try? JSONEncoder().encode(liste) { UserDefaults.standard.set(d, forKey: "meteoHeures-\(cle)") }
    }

    /// Une prévision à moins de deux semaines peut encore changer : on la redemande.
    private static func estProche(_ jour: Date) -> Bool {
        jour > Date.now.addingTimeInterval(-86_400 * 2) && jour < Date.now.addingTimeInterval(86_400 * 16)
    }

    /// Le temps qu'il fait à cet instant (l'heure commencée).
    static func a(_ instant: Date, dans liste: [MeteoHeure]) -> MeteoHeure? {
        liste.last { $0.date <= instant } ?? liste.first
    }
}

// MARK: - Parcours d'une journée

/// Le déroulé d'une journée, minute par minute : où l'on est, en quoi l'on se déplace. Les horaires sont ceux du Timing
/// (heure locale du lieu visité, en minutes depuis minuit).
struct ParcoursJour {
    enum Genre { case hotel, etape, extremite }

    struct Arret: Identifiable {
        let id: String
        let titre: String
        let detail: String
        let symbole: String
        let genre: Genre
        let rang: Int?
        let coordonnee: CLLocationCoordinate2D
        /// Horaires affichés : arrivée et départ (nil : ne s'affiche pas, comme l'arrivée à l'hôtel du matin).
        var heureArrivee: Double?
        var heureDepart: Double?
        var sous: [SousArret] = []
        /// Les sous-étapes apparaissent quand l'icône approche de l'étape, et disparaissent quand elle l'a quittée.
        var visibleDe: Double = 0
        var visibleA: Double = 0
        /// Transport vers l'arrêt suivant.
        var modeSuivant: ModeTransport?
    }

    struct SousArret: Identifiable {
        let id: String
        let titre: String
        let rang: Int
        let coordonnee: CLLocationCoordinate2D
    }

    struct Morceau {
        var debut: Double
        var fin: Double
        var points: [CLLocationCoordinate2D]
        var cumul: [Double] = []
        var mode: ModeTransport?
        /// Trajet entre deux arrêts.
        var trajet = false
        /// Trajet entre deux sous-étapes (ou vers la première).
        var trajetSous = false
        /// L'arrêt où l'on est ; pendant un trajet, celui d'où l'on part.
        var arret: Int
        var sousArret: Int?

        var bouge: Bool { trajet || trajetSous }
    }

    var debut: Double
    var fin: Double
    var arrets: [Arret]
    var morceaux: [Morceau]
    /// Itinéraires à demander à Plans (le tracé s'affine quand ils arrivent).
    var aCharger: [(CLLocationCoordinate2D, CLLocationCoordinate2D, ModeTransport)] = []

    /// Durée de la lecture : de 5 à 20 secondes selon le nombre d'étapes.
    var secondes: Double {
        let n = arrets.count + arrets.reduce(0) { $0 + $1.sous.count }
        return min(20, max(5, 2 + 2.5 * Double(n)))
    }
    /// Minutes de la journée par seconde de lecture.
    var vitesse: Double { (fin - debut) / secondes }

    /// Les lieux où demander la météo (un par demi-degré).
    var lieuxMeteo: [CLLocationCoordinate2D] {
        var vus: Set<String> = []
        return arrets.compactMap { a in
            let l = MeteoHoraire.lieu(a.coordonnee)
            return vus.insert("\(l.latitude),\(l.longitude)").inserted ? l : nil
        }
    }

    // MARK: Position à une heure donnée

    func indice(a t: Double) -> Int {
        guard !morceaux.isEmpty else { return 0 }
        if let i = morceaux.firstIndex(where: { t < $0.fin && $0.fin > $0.debut }) { return i }
        return morceaux.count - 1
    }

    private static func avancement(_ m: Morceau, _ t: Double) -> Double {
        m.fin > m.debut ? min(max((t - m.debut) / (m.fin - m.debut), 0), 1) : 1
    }

    func position(a t: Double) -> CLLocationCoordinate2D? {
        guard !morceaux.isEmpty else { return nil }
        let m = morceaux[indice(a: t)]
        return Self.point(m, Self.avancement(m, t))
    }

    /// Le point situé à cette part (0…1) du tracé d'un morceau.
    private static func point(_ m: Morceau, _ f: Double) -> CLLocationCoordinate2D {
        guard m.points.count > 1, let total = m.cumul.last, total > 0 else { return m.points.first ?? CLLocationCoordinate2D() }
        let d = f * total
        let i = max(1, m.cumul.firstIndex { $0 >= d } ?? m.cumul.count - 1)
        let a = m.points[i - 1], b = m.points[i]
        let l = m.cumul[i] - m.cumul[i - 1]
        let g = l > 0 ? (d - m.cumul[i - 1]) / l : 1
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * g,
                                      longitude: a.longitude + (b.longitude - a.longitude) * g)
    }

    /// L'aspect de l'icône : le transport du dernier trajet commencé (avant le premier, celui du premier). Nil : un point.
    func mode(a t: Double) -> ModeTransport? {
        let i = indice(a: t)
        if let m = morceaux[...i].last(where: { $0.bouge && $0.debut <= t }) { return m.mode }
        return morceaux.first { $0.bouge }?.mode
    }

    /// Place dans la liste des arrêts, en continu : 2 à l'arrêt n° 2, 2,5 à mi-chemin entre le 2 et le 3.
    func curseur(a t: Double) -> Double {
        guard !morceaux.isEmpty else { return 0 }
        let m = morceaux[indice(a: t)]
        return Double(m.arret) + (m.trajet ? Self.avancement(m, t) : 0)
    }

    /// La sous-étape où l'on se trouve (ou vers laquelle on va).
    func sousArret(a t: Double) -> (arret: Int, sous: Int)? {
        guard !morceaux.isEmpty else { return nil }
        let m = morceaux[indice(a: t)]
        return m.sousArret.map { (m.arret, $0) }
    }

    func sousEtapesVisibles(_ arret: Arret, a t: Double) -> Bool {
        !arret.sous.isEmpty && t >= arret.visibleDe && t <= arret.visibleA
    }

    /// Les tracés déjà parcourus à cette heure (le dernier en partie).
    func parcouru(a t: Double) -> [[CLLocationCoordinate2D]] {
        morceaux.compactMap { m in
            guard m.bouge, m.debut <= t, m.points.count > 1 else { return nil }
            let f = Self.avancement(m, t)
            if f >= 1 { return m.points }
            let d = f * (m.cumul.last ?? 0)
            var points = zip(m.points, m.cumul).prefix { $0.1 < d }.map(\.0)
            points.append(Self.point(m, f))
            return points.count > 1 ? points : nil
        }
    }

    // MARK: Construction

    /// Distance « à plat » entre deux points (degrés, longitude corrigée de la latitude) : suffit pour avancer à vitesse régulière.
    private static func cumul(_ points: [CLLocationCoordinate2D]) -> [Double] {
        var r: [Double] = [0]
        for i in points.indices.dropFirst() {
            let a = points[i - 1], b = points[i]
            let k = cos((a.latitude + b.latitude) / 2 * .pi / 180)
            let dx = (b.longitude - a.longitude) * k, dy = b.latitude - a.latitude
            r.append(r[i - 1] + (dx * dx + dy * dy).squareRoot())
        }
        return r
    }

    /// Le tracé d'un trajet, comme sur la carte du voyage : itinéraire enregistré ou calculé, arc pour un vol, sinon ligne droite.
    @MainActor static func trace(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Transport?) -> [CLLocationCoordinate2D] {
        guard let t else { return [a, b] }
        var points: [CLLocationCoordinate2D]
        switch t.mode {
        case .avion: points = Itineraires.arc(a, b)
        case .voiture, .pied, .velo: points = t.itineraireGoogle(a, b)?.points ?? Itineraires.shared.trajet(a, b, t.mode)?.points ?? []
        case .bateau: points = Itineraires.shared.trajet(a, b, .bateau)?.points ?? []
        case .commun: points = t.itineraireCommun?.etapes.flatMap { PolylineGoogle.decoder($0.trace) } ?? []
        }
        if points.count < 2 { return [a, b] }
        return [a] + points + [b]
    }

    /// L'heure locale `minutes` de ce jour (jour du calendrier de l'app), dans le fuseau `zone`.
    static func instant(_ jour: Date, _ minutes: Double, zone: TimeZone) -> Date {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: jour)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let minuit = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? jour
        return minuit.addingTimeInterval(minutes * 60)
    }

    @MainActor static func calculer(voyage: Voyage, jour: Date) -> ParcoursJour? {
        typealias Bloc = TimingView.Bloc
        let blocs = TimingView(voyage: voyage).blocs(du: jour).sorted { $0.debut < $1.debut }
        let transports = blocs.filter { $0.genre == .transport }
        let matins = blocs.filter { $0.genre == .hotelMatin }
        let matin = matins.first { b in transports.contains { $0.extremite == nil && $0.etape === b.etape } } ?? matins.first
        let etapes = blocs.filter { $0.genre == .etape }
        let soirs = blocs.filter { $0.genre == .hotelSoir }
        let vise = etapes.last?.etape.flatMap { voyage.hebergementVise(depuis: $0, apres: jour) }
        let soir = soirs.first { $0.etape === vise } ?? soirs.first
        let aller = transports.first { $0.extremite == .aller }
        let retour = transports.first { $0.extremite == .retour }
        let activites = blocs.filter { $0.genre == .etape || $0.genre == .transport }

        // De une heure avant la fin de la nuit d'hôtel à une heure après le début de celle du soir.
        var debut = max(0, (matin?.fin ?? activites.map(\.debut).min() ?? 8 * 60) - 60)
        var fin = min(24 * 60, (soir?.debut ?? activites.map(\.fin).max() ?? 20 * 60) + 60)
        if fin < debut + 60 { fin = min(24 * 60, debut + 60); debut = min(debut, fin - 60) }

        let rangs = voyage.etapes(du: jour).filter { $0.coordonnee != nil }
        var arrets: [Arret] = []
        /// Pour chaque arrêt : le bloc de transport qui en part.
        var departs: [Bloc?] = []

        if let aller, let t = aller.transport, let c = t.departCoordonnee {
            arrets.append(Arret(id: "aller", titre: t.de.isEmpty ? "Départ" : t.de, detail: "", symbole: "house.fill", genre: .extremite,
                                rang: nil, coordonnee: c, heureArrivee: nil, heureDepart: aller.debut))
            departs.append(aller)
        }
        if let matin, let h = matin.etape, let c = h.coordonnee {
            arrets.append(Arret(id: "matin-\(h.uid)", titre: matin.titre, detail: matin.detail, symbole: "bed.double.fill", genre: .hotel,
                                rang: nil, coordonnee: c, heureArrivee: nil, heureDepart: matin.fin))
            departs.append(transports.first { $0.extremite == nil && $0.etape === h })
        }
        for b in etapes {
            guard let e = b.etape, let c = e.coordonnee else { continue }
            let sous = e.sousEtapes.enumerated().compactMap { i, s in
                s.coordonnee.map { SousArret(id: s.uid, titre: s.titre.isEmpty ? "Sous-étape \(i + 1)" : s.titre, rang: i + 1, coordonnee: $0) }
            }
            arrets.append(Arret(id: e.uid, titre: b.titre, detail: b.detail, symbole: e.categorie.symbole, genre: .etape,
                                rang: rangs.firstIndex { $0 === e }.map { $0 + 1 }, coordonnee: c,
                                heureArrivee: b.debut, heureDepart: b.fin, sous: sous))
            departs.append(transports.first { $0.extremite == nil && $0.etape === e })
        }
        if let soir, let h = soir.etape, let c = h.coordonnee {
            arrets.append(Arret(id: "soir-\(h.uid)", titre: soir.titre, detail: soir.detail, symbole: "bed.double.fill", genre: .hotel,
                                rang: nil, coordonnee: c, heureArrivee: soir.debut, heureDepart: nil))
            departs.append(nil)
        }
        if let retour, let t = retour.transport, let c = t.arriveeCoordonnee {
            if !departs.isEmpty { departs[departs.count - 1] = retour }
            arrets.append(Arret(id: "retour", titre: t.vers.isEmpty ? "Arrivée" : t.vers, detail: "", symbole: "house.fill", genre: .extremite,
                                rang: nil, coordonnee: c, heureArrivee: retour.fin, heureDepart: nil))
            departs.append(nil)
        }
        guard !arrets.isEmpty else { return nil }

        // Sous-étapes : chacune garde sa durée (30 min par défaut), les trajets entre elles 10 min, le tout à l'échelle du temps passé sur place.
        let sousEtapes: [String: [Etape]] = Dictionary(uniqueKeysWithValues: etapes.compactMap { b in
            b.etape.map { ($0.uid, $0.sousEtapes.filter { $0.coordonnee != nil }) }
        })

        var morceaux: [Morceau] = []
        var aCharger: [(CLLocationCoordinate2D, CLLocationCoordinate2D, ModeTransport)] = []
        let minimum = max(4, (fin - debut) * 0.02)
        var t = debut
        var origineSuivante: CLLocationCoordinate2D?

        func ajouterSejour(_ i: Int, de d: Double, a f: Double) {
            let a = arrets[i]
            let sous = sousEtapes[a.id] ?? []
            guard !sous.isEmpty, f > d else {
                morceaux.append(Morceau(debut: d, fin: f, points: [a.coordonnee], arret: i))
                origineSuivante = nil
                return
            }
            // Poids de chaque morceau : l'arrivée, puis trajet → sous-étape → trajet → sous-étape…
            var plan: [(poids: Double, morceau: Morceau)] = [(5, Morceau(debut: 0, fin: 0, points: [a.coordonnee], arret: i))]
            var precedent: (c: CLLocationCoordinate2D, transport: Transport?) = (a.coordonnee, nil)
            for (k, s) in sous.enumerated() {
                let c = s.coordonnee!
                let tr = precedent.transport
                if let tr, tr.mode.aUnItineraire, tr.itineraireGoogle(precedent.c, c) == nil { aCharger.append((precedent.c, c, tr.mode)) }
                plan.append((10, Morceau(debut: 0, fin: 0, points: trace(precedent.c, c, tr), mode: tr?.mode, trajetSous: true, arret: i, sousArret: k)))
                plan.append((s.duree ?? 30, Morceau(debut: 0, fin: 0, points: [c], arret: i, sousArret: k)))
                precedent = (c, s.transport)
            }
            let total = plan.reduce(0) { $0 + $1.poids }
            var curseur = d
            for (poids, var m) in plan {
                m.debut = curseur
                m.fin = curseur + (f - d) * poids / total
                curseur = m.fin
                morceaux.append(m)
            }
            origineSuivante = precedent.c
        }

        for i in arrets.indices {
            arrets[i].visibleDe = t
            guard i + 1 < arrets.count else {
                ajouterSejour(i, de: t, a: max(fin, t))
                break
            }
            let bloc = departs[i]
            var depart = bloc?.debut ?? arrets[i].heureDepart ?? t
            var arrivee = bloc?.fin ?? arrets[i + 1].heureArrivee ?? depart
            depart = max(depart, t)
            arrivee = max(arrivee, depart)
            // Pas de temps pour aller d'une étape à l'autre : un court trajet, pris sur la visite.
            if arrivee - depart < minimum {
                let recul = min(minimum - (arrivee - depart), (depart - t) / 2)
                depart -= max(recul, 0)
                arrivee = max(arrivee, depart + minimum)
            }
            ajouterSejour(i, de: t, a: depart)
            let b = arrets[i + 1].coordonnee
            var points = trace(arrets[i].coordonnee, b, bloc?.transport)
            if let o = origineSuivante { points.insert(o, at: 0) }
            if let tr = bloc?.transport, tr.mode.aUnItineraire, tr.itineraireGoogle(arrets[i].coordonnee, b) == nil {
                aCharger.append((arrets[i].coordonnee, b, tr.mode))
            }
            morceaux.append(Morceau(debut: depart, fin: arrivee, points: points, mode: bloc?.transport?.mode, trajet: true, arret: i))
            arrets[i].modeSuivant = bloc?.transport?.mode
            t = arrivee
        }
        fin = max(fin, t)

        for i in morceaux.indices { morceaux[i].cumul = cumul(morceaux[i].points) }
        // Les sous-étapes s'affichent à mi-chemin du trajet qui mène à l'étape, et jusqu'à mi-chemin du suivant.
        for i in arrets.indices where !arrets[i].sous.isEmpty {
            let entrant = morceaux.last { $0.trajet && $0.arret == i - 1 }
            let sortant = morceaux.first { $0.trajet && $0.arret == i }
            let sejour = morceaux.filter { !$0.trajet && $0.arret == i }
            let arrivee = sejour.first?.debut ?? arrets[i].visibleDe
            let depart = sejour.last?.fin ?? arrivee
            arrets[i].visibleDe = entrant.map { ($0.debut + $0.fin) / 2 } ?? max(debut, arrivee - 30)
            arrets[i].visibleA = sortant.map { ($0.debut + $0.fin) / 2 } ?? depart + 30
        }
        return ParcoursJour(debut: debut, fin: fin, arrets: arrets, morceaux: morceaux, aCharger: aCharger)
    }

    /// Région qui montre tous ces points, avec de la marge.
    static func region(_ points: [CLLocationCoordinate2D], marge: Double = 1.6, minimum: Double = 0.012) -> MKCoordinateRegion? {
        guard let premier = points.first else { return nil }
        var minLat = premier.latitude, maxLat = premier.latitude, minLon = premier.longitude, maxLon = premier.longitude
        for p in points {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let span = MKCoordinateSpan(latitudeDelta: min(max((maxLat - minLat) * marge, minimum), 170),
                                    longitudeDelta: min(max((maxLon - minLon) * marge, minimum), 340))
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: span)
    }
}

// MARK: - Lecture

/// Le jour à afficher en lecture.
struct ParcoursJourChoisi: Identifiable {
    let jour: Date
    let numero: Int
    var id: Date { jour }
}

/// « Jouer la journée » : une icône parcourt les étapes dans l'ordre et à l'heure prévus, sous un ciel qui suit le soleil et la météo.
struct ParcoursJourView: View {
    let voyage: Voyage
    let jour: Date
    let numero: Int
    @Environment(\.dismiss) private var dismiss
    @State private var parcours: ParcoursJour?
    @State private var pret = false
    @State private var temps: Double = 0
    @State private var lecture = false
    @State private var camera: MapCameraPosition = .automatic
    /// Change quand la carte bouge (glissée, zoomée, cadrage animé) : l'icône suit.
    @State private var mouvementsCarte = 0
    @State private var itineraires = Itineraires.shared
    @State private var meteo = MeteoHoraire.shared

    private var couleur: Color { CarteDuVoyage.couleur(du: numero - 1) }
    private var zone: TimeZone { voyage.fuseau(du: jour) }

    var body: some View {
        VStack(spacing: 0) {
            entete
            if let parcours {
                ZStack(alignment: .top) {
                    carte(parcours)
                    CielDuParcours(parcours: parcours, temps: temps, jour: jour, zone: zone, meteo: meteoActuelle(parcours))
                        .frame(height: 92)
                        .padding(.horizontal, 10).padding(.top, 8)
                        .allowsHitTesting(false)
                }
                commandes(parcours)
                BandeEtapes(parcours: parcours, temps: temps, couleur: couleur)
                    .frame(height: 118)
                    .padding(.bottom, 8)
            } else if pret {
                ContentUnavailableView("Rien à parcourir", systemImage: "map",
                                       description: Text("Aucune étape ni aucun hébergement de ce jour n'a de lieu sur la carte."))
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(Color.fondParcours)
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 900, minHeight: 720, idealHeight: 860)
        #endif
        .task { await preparer() }
        .task(id: lecture) { await jouer() }
        .onChange(of: itineraires.trajets.count) {
            // Un itinéraire est arrivé : le tracé suit désormais la route.
            if let p = ParcoursJour.calculer(voyage: voyage, jour: jour) { parcours = p }
        }
        .onChange(of: cleCamera) { _, cle in cadrer(cle) }
    }

    private var entete: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.bold())
                    .frame(width: 34, height: 34)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Fermer")
            VStack(alignment: .leading, spacing: 1) {
                Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(couleur)
                Text(jour.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.headline)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Carte

    private func carte(_ p: ParcoursJour) -> some View {
        let position = p.position(a: temps)
        let mode = p.mode(a: temps)
        let traces = Array(p.morceaux.enumerated()).filter { $0.element.trajet && $0.element.points.count > 1 }
        let parcouru = p.parcouru(a: temps)
        return MapReader { proxy in
        Map(position: $camera) {
            ForEach(traces, id: \.offset) { _, m in
                MapPolyline(coordinates: m.points)
                    .stroke(couleur.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: m.mode == .avion ? [7, 6] : []))
            }
            ForEach(Array(p.arrets.enumerated()), id: \.element.id) { i, a in
                if p.sousEtapesVisibles(a, a: temps) {
                    let sousTraces = p.morceaux.filter { $0.trajetSous && $0.arret == i && $0.points.count > 1 }
                    ForEach(Array(sousTraces.enumerated()), id: \.offset) { _, m in
                        MapPolyline(coordinates: m.points)
                            .stroke(couleur.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 5]))
                    }
                }
            }
            ForEach(Array(parcouru.enumerated()), id: \.offset) { _, points in
                MapPolyline(coordinates: points)
                    .stroke(couleur, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(p.arrets) { a in
                Annotation(a.titre, coordinate: a.coordonnee) { repere(a) }
            }
            ForEach(Array(p.arrets.enumerated()), id: \.element.id) { i, a in
                let visibles = p.sousEtapesVisibles(a, a: temps)
                let actuelle = p.sousArret(a: temps)
                ForEach(a.sous) { s in
                    Annotation(s.titre, coordinate: s.coordonnee) {
                        repereSous(s, visible: visibles, actif: actuelle?.arret == i && a.sous.firstIndex { $0.id == s.id } == actuelle?.sous)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        // Le bandeau du ciel couvre le haut de la carte : les cadrages en tiennent compte.
        .safeAreaPadding(.top, 104)
        .onMapCameraChange(frequency: .continuous) { _ in mouvementsCarte += 1 }
        // L'icône est posée par-dessus la carte : elle reste au-dessus des repères des étapes.
        .overlay {
            GeometryReader { geo in
                let _ = mouvementsCarte
                if let position, let point = proxy.convert(position, to: .global) {
                    let origine = geo.frame(in: .global).origin
                    icone(mode).position(x: point.x - origine.x, y: point.y - origine.y)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        }
    }

    private func repere(_ a: ParcoursJour.Arret) -> some View {
        Group {
            if let rang = a.rang {
                Text("\(rang)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            } else {
                Image(systemName: a.symbole).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .background(a.genre == .hotel ? voyage.couleurNuit(apres: jour) : couleur, in: Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private func repereSous(_ s: ParcoursJour.SousArret, visible: Bool, actif: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(s.rang)")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(couleur)
                .frame(width: 20, height: 20)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(couleur, lineWidth: 2))
                .scaleEffect(actif ? 1.3 : 1)
            Text(s.titre).font(.caption2.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.regularMaterial, in: Capsule())
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.2)
        .animation(.spring(duration: 0.4), value: visible)
        .animation(.spring(duration: 0.3), value: actif)
    }

    private func icone(_ mode: ModeTransport?) -> some View {
        ZStack {
            Circle().fill(couleur)
                .frame(width: mode == nil ? 16 : 38, height: mode == nil ? 16 : 38)
                .overlay(Circle().stroke(.white, lineWidth: 3))
            if let mode {
                Image(systemName: mode.symbole)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
                    .id(mode)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .animation(.spring(duration: 0.35), value: mode)
    }

    // MARK: Commandes

    private func commandes(_ p: ParcoursJour) -> some View {
        HStack(spacing: 12) {
            Button {
                if !lecture, temps >= p.fin - 0.5 { temps = p.debut }
                lecture.toggle()
            } label: {
                Image(systemName: lecture ? "pause.fill" : "play.fill")
                    .font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(couleur, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(lecture ? "Pause" : "Lecture")
            Text(Self.heure(temps))
                .font(.title2.bold().monospacedDigit())
                .frame(minWidth: 70, alignment: .leading)
                .contentTransition(.numericText())
            Slider(value: Binding(get: { temps }, set: { temps = $0; lecture = false }), in: p.debut...p.fin) { enCours in
                if enCours { lecture = false }
            }
            .tint(couleur)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    static func heure(_ minutes: Double) -> String {
        let m = Int(minutes.rounded(.down)) % (24 * 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // MARK: Météo

    private func meteoActuelle(_ p: ParcoursJour) -> [MeteoHeure] {
        guard let position = p.position(a: temps) else { return [] }
        let lieux = p.lieuxMeteo
        guard let proche = lieux.min(by: { distance($0, position) < distance($1, position) }) else { return [] }
        return meteo.liste(proche, jour: jour)
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = a.longitude - b.longitude, dy = a.latitude - b.latitude
        return dx * dx + dy * dy
    }

    // MARK: Lecture et caméra

    private func preparer() async {
        guard parcours == nil else { return }
        let p = ParcoursJour.calculer(voyage: voyage, jour: jour)
        parcours = p
        pret = true
        guard let p else { return }
        temps = p.debut
        // On part de la première étape (ou de l'hôtel de la veille), de près.
        if let premier = p.arrets.first {
            camera = .region(MKCoordinateRegion(center: premier.coordonnee, latitudinalMeters: 1800, longitudinalMeters: 1800))
        }
        async let routes: Void = chargerItineraires(p)
        async let ciel: Void = chargerMeteo(p)
        try? await Task.sleep(for: .seconds(1))
        if !Task.isCancelled { lecture = true }
        _ = await (routes, ciel)
    }

    private func chargerItineraires(_ p: ParcoursJour) async {
        for (a, b, mode) in p.aCharger { await Itineraires.shared.charger(a, b, mode) }
    }

    private func chargerMeteo(_ p: ParcoursJour) async {
        for lieu in p.lieuxMeteo { await meteo.charger(lieu, jour: jour) }
    }

    private func jouer() async {
        guard lecture, let p = parcours else { return }
        if temps >= p.fin - 0.5 { temps = p.debut }
        var dernier = Date.now
        while !Task.isCancelled, lecture {
            try? await Task.sleep(for: .milliseconds(30))
            let maintenant = Date.now
            temps = min(p.fin, temps + maintenant.timeIntervalSince(dernier) * p.vitesse)
            dernier = maintenant
            if temps >= p.fin { lecture = false }
        }
    }

    /// Ce que la caméra doit montrer : le trajet en cours (départ et arrivée), ou une étape et ses sous-étapes.
    private var cleCamera: String? {
        guard let p = parcours, !p.morceaux.isEmpty else { return nil }
        let i = p.indice(a: temps)
        let m = p.morceaux[i]
        if m.trajet { return "t\(i)" }
        if p.sousEtapesVisibles(p.arrets[m.arret], a: temps) { return "s\(m.arret)" }
        return nil
    }

    private func cadrer(_ cle: String?) {
        guard let p = parcours, let cle, let n = Int(cle.dropFirst()) else { return }
        var points: [CLLocationCoordinate2D] = []
        if cle.hasPrefix("t"), n < p.morceaux.count {
            let m = p.morceaux[n]
            points = m.points
            // L'étape d'arrivée et ses sous-étapes, si elle en a.
            if m.arret + 1 < p.arrets.count { points += p.arrets[m.arret + 1].sous.map(\.coordonnee) }
        } else if cle.hasPrefix("s"), n < p.arrets.count {
            points = [p.arrets[n].coordonnee] + p.arrets[n].sous.map(\.coordonnee)
        }
        guard let region = ParcoursJour.region(points) else { return }
        withAnimation(.easeInOut(duration: min(0.9, max(0.35, 6 / max(p.vitesse, 1))))) { camera = .region(region) }
    }
}

private extension Color {
    static var fondParcours: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// MARK: - Ciel

/// Le bandeau du haut : le ciel de l'heure (nuit, aube, jour, crépuscule, assombri par les nuages), la course du soleil
/// entre son lever et son coucher réels au lieu où l'on est, et la météo heure par heure.
private struct CielDuParcours: View {
    let parcours: ParcoursJour
    let temps: Double
    let jour: Date
    let zone: TimeZone
    let meteo: [MeteoHeure]

    var body: some View {
        let lieu = parcours.position(a: temps) ?? parcours.arrets.first?.coordonnee ?? CLLocationCoordinate2D()
        let instant = ParcoursJour.instant(jour, temps, zone: zone)
        let hauteur = Soleil.hauteur(instant, lieu)
        let actuelle = MeteoHoraire.a(instant, dans: meteo)
        let couleurs = Soleil.couleursCiel(hauteur: hauteur, gris: actuelle?.gris ?? 0)
        let soleil = Soleil.leverCoucher(jour: jour, lieu, zone: zone)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let horizon = h * 0.74
            let haut: CGFloat = 16
            // Hauteur du soleil le long de la journée affichée, pour tracer sa course.
            let echantillons: [(x: CGFloat, e: Double)] = (0...60).map { k in
                let m = parcours.debut + (parcours.fin - parcours.debut) * Double(k) / 60
                return (w * CGFloat(k) / 60, Soleil.hauteur(ParcoursJour.instant(jour, m, zone: zone), lieu))
            }
            let maxi = max(echantillons.map(\.e).max() ?? 10, 10)
            let y: (Double) -> CGFloat = { e in horizon - CGFloat(e / maxi) * (horizon - haut) }
            let x: (Double) -> CGFloat = { m in w * CGFloat((m - parcours.debut) / max(parcours.fin - parcours.debut, 1)) }
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [couleurs.haut, couleurs.bas], startPoint: .top, endPoint: .bottom)
                // Étoiles, la nuit.
                Canvas { ctx, taille in
                    var hasard = UInt64(42)
                    for _ in 0..<28 {
                        hasard = hasard &* 6364136223846793005 &+ 1442695040888963407
                        let px = Double((hasard >> 33) % 1000) / 1000 * taille.width
                        hasard = hasard &* 6364136223846793005 &+ 1442695040888963407
                        let py = Double((hasard >> 33) % 1000) / 1000 * taille.height * 0.65
                        ctx.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.8)))
                    }
                }
                .opacity(min(max((-hauteur - 4) / 8, 0), 1))
                // La course du soleil et l'horizon.
                Path { p in
                    for (k, s) in echantillons.enumerated() {
                        let pt = CGPoint(x: s.x, y: min(y(s.e), h + 20))
                        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                Rectangle().fill(.white.opacity(0.3)).frame(height: 1).offset(y: horizon)
                // Le sol, qui cache le soleil couché.
                LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
                    .frame(height: h - horizon).offset(y: horizon)
                // Lever et coucher, posés sur l'horizon.
                if let soleil {
                    let lever = minutes(soleil.lever), coucher = minutes(soleil.coucher)
                    ForEach([(lever, "sunrise.fill"), (coucher, "sunset.fill")], id: \.1) { m, symbole in
                        if m >= parcours.debut, m <= parcours.fin {
                            Label(ParcoursJourView.heure(m), systemImage: symbole)
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                                .labelStyle(.titleAndIcon)
                                .fixedSize()
                                .position(x: min(max(x(m), 34), w - 34), y: horizon + (h - horizon) / 2)
                        }
                    }
                }
                // Changements de temps dans la journée.
                ForEach(changements, id: \.date) { c in
                    Image(systemName: c.symbole).symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                        .opacity(0.85)
                        .position(x: min(max(x(minutes(c.date)), 8), w - 8), y: haut - 6)
                }
                // Le soleil (ou la lune).
                let sx = x(temps)
                if hauteur > -3 {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 1, green: 0.78, blue: 0.3)], center: .center, startRadius: 1, endRadius: 11))
                        .frame(width: 22, height: 22)
                        .shadow(color: .yellow.opacity(0.8), radius: 10)
                        .opacity((actuelle?.gris ?? 0) > 0.5 ? 0.6 : 1)
                        .position(x: sx, y: y(hauteur))
                } else {
                    Image(systemName: "moon.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.9))
                        .position(x: sx, y: haut + 14)
                }
                // Le temps qu'il fait.
                HStack(spacing: 6) {
                    if let soleil {
                        Text("↑ \(ParcoursJourView.heure(minutes(soleil.lever)))  ↓ \(ParcoursJourView.heure(minutes(soleil.coucher)))")
                    }
                    Spacer()
                    if let actuelle {
                        Image(systemName: actuelle.symbole).symbolRenderingMode(.multicolor)
                            .contentTransition(.symbolEffect(.replace))
                        Text(actuelle.temperature.isNaN ? actuelle.libelle : "\(Int(actuelle.temperature.rounded()))° · \(actuelle.libelle)")
                            .contentTransition(.opacity)
                    }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2)
                .padding(.horizontal, 10)
                .offset(y: horizon - 22)
                .animation(.easeInOut(duration: 0.4), value: actuelle?.code)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .animation(.easeInOut(duration: 0.3), value: actuelle?.code)
    }

    /// Minutes depuis minuit (heure locale du jour) d'un instant.
    private func minutes(_ date: Date) -> Double {
        date.timeIntervalSince(ParcoursJour.instant(jour, 0, zone: zone)) / 60
    }

    /// Les heures où le temps change, dans la plage affichée (la première comprise).
    private var changements: [MeteoHeure] {
        var r: [MeteoHeure] = []
        for h in meteo {
            let m = minutes(h.date)
            guard m >= parcours.debut - 59, m <= parcours.fin else { continue }
            if r.last?.symbole != h.symbole { r.append(h) }
        }
        return r.count > 1 ? r.filter { minutes($0.date) >= parcours.debut } : []
    }
}

// MARK: - Étapes qui défilent

/// En bas de l'écran : les étapes défilent avec le temps ; entre deux étapes, les deux sont visibles.
private struct BandeEtapes: View {
    let parcours: ParcoursJour
    let temps: Double
    let couleur: Color

    var body: some View {
        GeometryReader { geo in
            let largeur = min(260, geo.size.width * 0.42)
            let espace: CGFloat = 40
            let curseur = parcours.curseur(a: temps)
            let actuel = Int(curseur.rounded())
            let sous = parcours.sousArret(a: temps)
            HStack(spacing: espace) {
                ForEach(Array(parcours.arrets.enumerated()), id: \.element.id) { i, a in
                    carte(a, sousActuelle: sous?.arret == i ? sous.map { a.sous[$0.sous] } : nil, active: i == actuel)
                        .frame(width: largeur)
                        .overlay(alignment: .trailing) {
                            if i + 1 < parcours.arrets.count {
                                Image(systemName: a.modeSuivant?.symbole ?? "arrow.right")
                                    .font(.caption.bold()).foregroundStyle(couleur)
                                    .frame(width: 28, height: 28)
                                    .background(couleur.opacity(0.15), in: Circle())
                                    .offset(x: (espace + 28) / 2)
                            }
                        }
                }
            }
            .fixedSize()
            .offset(x: geo.size.width / 2 - largeur / 2 - CGFloat(curseur) * (largeur + espace))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .clipped()
    }

    private func carte(_ a: ParcoursJour.Arret, sousActuelle: ParcoursJour.SousArret?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Group {
                    if let rang = a.rang {
                        Text("\(rang)").font(.system(size: 12, weight: .bold))
                    } else {
                        Image(systemName: a.symbole).font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(couleur, in: Circle())
                Text(a.titre).font(.subheadline.bold()).lineLimit(2)
            }
            Text(horaires(a)).font(.caption).foregroundStyle(.secondary)
            if let s = sousActuelle {
                Label(s.titre, systemImage: "arrow.turn.down.right")
                    .font(.caption.weight(.medium)).foregroundStyle(couleur).lineLimit(1)
            } else if !a.sous.isEmpty {
                Text("\(a.sous.count) sous-étape\(a.sous.count > 1 ? "s" : "")").font(.caption).foregroundStyle(.tertiary)
            } else if !a.detail.isEmpty {
                Text(a.detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(active ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(couleur.opacity(active ? 0.9 : 0), lineWidth: 2))
        .opacity(active ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private func horaires(_ a: ParcoursJour.Arret) -> String {
        switch (a.heureArrivee, a.heureDepart) {
        case let (d?, f?): "\(ParcoursJourView.heure(d)) – \(ParcoursJourView.heure(f))"
        case let (nil, f?): "Départ \(ParcoursJourView.heure(f))"
        case let (d?, nil): "Arrivée \(ParcoursJourView.heure(d))"
        default: ""
        }
    }
}
