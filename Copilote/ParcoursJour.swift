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

    /// Le lieu arrondi au centième de degré (un kilomètre environ) : la même maille du modèle météo
    /// que la météo du jour demandée au même endroit.
    nonisolated static func lieu(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (c.latitude * 100).rounded() / 100, longitude: (c.longitude * 100).rounded() / 100)
    }

    private static func jourTexte(_ jour: Date, decalage: Int = 0) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: decalage, to: jour) ?? jour
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func cle(_ c: CLLocationCoordinate2D, _ jour: Date) -> String {
        let l = lieu(c)
        return String(format: "%.2f,%.2f|", l.latitude, l.longitude) + jourTexte(jour)
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
        guard !enCours.contains(cle) else { return }
        if !liste(c, jour: jour).isEmpty, !Self.aRedemander(jour, chargeLe: UserDefaults.standard.object(forKey: "meteoHeuresDate-\(cle)") as? Date) {
            return
        }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        let l = Self.lieu(c)
        // Au-delà de trois mois, l'archive (relevés) ; sinon les prévisions, qui donnent aussi le temps des jours passés.
        let ancien = jour < Date.now.addingTimeInterval(-86_400 * 80)
        var composants = URLComponents(string: ancien ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast")!
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
        if let d = try? JSONEncoder().encode(liste) {
            UserDefaults.standard.set(d, forKey: "meteoHeures-\(cle)")
            UserDefaults.standard.set(Date.now, forKey: "meteoHeuresDate-\(cle)")
        }
    }

    /// Ce qu'on a gardé n'est qu'une prévision tant qu'il a été chargé avant la fin de la journée (lendemain compris,
    /// pour les fuseaux en avance) : on le redemande, au plus toutes les trois heures, jusqu'à avoir le temps qu'il a fait.
    /// Rien à redemander pour un jour trop lointain (pas encore de prévision).
    private static func aRedemander(_ jour: Date, chargeLe: Date?) -> Bool {
        guard jour < Date.now.addingTimeInterval(86_400 * 16) else { return false }
        guard let chargeLe else { return true }
        let finDuJour = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: jour)) ?? jour
        return chargeLe < finDuJour && Date.now.timeIntervalSince(chargeLe) > 3 * 3600
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
        /// Où arrive le trajet qui mène à l'arrêt : sa première sous-étape s'il en a, sinon l'arrêt lui-même.
        var entree: CLLocationCoordinate2D { sous.first?.coordonnee ?? coordonnee }
        /// D'où part le trajet vers l'arrêt suivant : sa dernière sous-étape s'il en a, sinon l'arrêt lui-même.
        var sortie: CLLocationCoordinate2D { sous.last?.coordonnee ?? coordonnee }
        /// Les sous-étapes apparaissent quand l'icône approche de l'étape, et disparaissent quand elle l'a quittée.
        var visibleDe: Double = 0
        var visibleA: Double = 0
        /// Transport vers l'arrêt suivant.
        var modeSuivant: ModeTransport?
        var images = Images()
        /// Les photos s'affichent de la moitié du trajet qui y mène à la moitié du trajet suivant.
        var imagesDe: Double = 0
        var imagesA: Double = 0
    }

    struct SousArret: Identifiable {
        let id: String
        let titre: String
        let rang: Int
        let coordonnee: CLLocationCoordinate2D
        var images = Images()
    }

    /// Les images d'une étape : son album ; s'il est vide, les photos Google de son lieu (enregistrées, sinon celle en ligne).
    struct Images {
        var documents: [Document] = []
        var url: URL?
        var vide: Bool { documents.isEmpty && url == nil }

        init() {}

        @MainActor init(_ etape: Etape) {
            let album = etape.album
            documents = album.isEmpty ? etape.photosDuLieu.sorted { $0.nom < $1.nom } : album
            url = album.isEmpty ? etape.photoURL.flatMap(URL.init) : nil
        }
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

    /// Les lieux où demander la météo, faute de lieu pour la journée (un par étape).
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

    /// Les morceaux déjà parcourus en entier à cette heure.
    func finis(a t: Double) -> [Int] {
        morceaux.indices.filter { i in
            let m = morceaux[i]
            return m.bouge && m.debut <= t && m.points.count > 1 && Self.avancement(m, t) >= 1
        }
    }

    /// Le tracé du trajet en cours, de son départ jusqu'à l'icône.
    func traceEnCours(a t: Double) -> [CLLocationCoordinate2D]? {
        guard let m = morceaux.first(where: { $0.bouge && $0.debut <= t && $0.points.count > 1 && Self.avancement($0, t) < 1 })
        else { return nil }
        let f = Self.avancement(m, t)
        let d = f * (m.cumul.last ?? 0)
        var points = zip(m.points, m.cumul).prefix { $0.1 < d }.map(\.0)
        points.append(Self.point(m, f))
        return points.count > 1 ? points : nil
    }

    /// Les deux parcours ont le même tracé pour le morceau en cours : on peut passer de l'un à l'autre sans à-coup.
    static func memeTrace(_ a: ParcoursJour, _ b: ParcoursJour, a t: Double) -> Bool {
        guard a.morceaux.count == b.morceaux.count, !a.morceaux.isEmpty else { return false }
        let i = a.indice(a: t)
        let x = a.morceaux[i].points, y = b.morceaux[i].points
        return x.count == y.count && x.first?.latitude == y.first?.latitude && x.last?.longitude == y.last?.longitude
            && x.dropFirst(x.count / 2).first?.latitude == y.dropFirst(y.count / 2).first?.latitude
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
                                rang: nil, coordonnee: c, heureArrivee: nil, heureDepart: matin.fin, images: Images(h)))
            departs.append(transports.first { $0.extremite == nil && $0.etape === h })
        }
        for b in etapes {
            guard let e = b.etape, let c = e.coordonnee else { continue }
            let sous = e.sousEtapes.enumerated().compactMap { i, s in
                s.coordonnee.map { SousArret(id: s.uid, titre: s.titre.isEmpty ? "Sous-étape \(i + 1)" : s.titre, rang: i + 1, coordonnee: $0, images: Images(s)) }
            }
            arrets.append(Arret(id: e.uid, titre: b.titre, detail: b.detail, symbole: e.categorie.symbole, genre: .etape,
                                rang: rangs.firstIndex { $0 === e }.map { $0 + 1 }, coordonnee: c,
                                heureArrivee: b.debut, heureDepart: b.fin, sous: sous, images: Images(e)))
            departs.append(transports.first { $0.extremite == nil && $0.etape === e })
        }
        if let soir, let h = soir.etape, let c = h.coordonnee {
            arrets.append(Arret(id: "soir-\(h.uid)", titre: soir.titre, detail: soir.detail, symbole: "bed.double.fill", genre: .hotel,
                                rang: nil, coordonnee: c, heureArrivee: soir.debut, heureDepart: nil, images: Images(h)))
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
        // Le trajet qui mène à l'étape arrive directement à la première, celui qui en repart quitte la dernière.
        let sousEtapes: [String: [Etape]] = Dictionary(uniqueKeysWithValues: etapes.compactMap { b in
            b.etape.map { ($0.uid, $0.sousEtapes.filter { $0.coordonnee != nil }) }
        })

        var morceaux: [Morceau] = []
        var aCharger: [(CLLocationCoordinate2D, CLLocationCoordinate2D, ModeTransport)] = []
        let minimum = max(4, (fin - debut) * 0.02)
        var t = debut

        func ajouterSejour(_ i: Int, de d: Double, a f: Double) {
            let a = arrets[i]
            let sous = sousEtapes[a.id] ?? []
            guard !sous.isEmpty, f > d else {
                morceaux.append(Morceau(debut: d, fin: f, points: [sous.isEmpty ? a.coordonnee : a.entree], arret: i, sousArret: sous.isEmpty ? nil : 0))
                return
            }
            // Poids de chaque morceau : sous-étape → trajet → sous-étape… (on arrive directement à la première).
            var plan: [(poids: Double, morceau: Morceau)] = []
            var precedent: (c: CLLocationCoordinate2D, transport: Transport?)?
            for (k, s) in sous.enumerated() {
                let c = s.coordonnee!
                if let precedent {
                    let tr = precedent.transport
                    if let tr, tr.mode.aUnItineraire, tr.itineraireGoogle(precedent.c, c) == nil { aCharger.append((precedent.c, c, tr.mode)) }
                    plan.append((10, Morceau(debut: 0, fin: 0, points: trace(precedent.c, c, tr), mode: tr?.mode, trajetSous: true, arret: i, sousArret: k)))
                }
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
            // De la dernière sous-étape de l'arrêt (ou de l'arrêt) à la première sous-étape du suivant (ou à lui).
            let a = arrets[i].sortie, b = arrets[i + 1].entree
            let points = trace(a, b, bloc?.transport)
            if let tr = bloc?.transport, tr.mode.aUnItineraire, tr.itineraireGoogle(a, b) == nil {
                aCharger.append((a, b, tr.mode))
            }
            morceaux.append(Morceau(debut: depart, fin: arrivee, points: points, mode: bloc?.transport?.mode, trajet: true, arret: i))
            arrets[i].modeSuivant = bloc?.transport?.mode
            t = arrivee
        }
        fin = max(fin, t)

        for i in morceaux.indices { morceaux[i].cumul = cumul(morceaux[i].points) }
        // Les photos : de la moitié du trajet qui mène à l'arrêt à la moitié du suivant (du début ou jusqu'à la fin de la journée aux bouts).
        for i in arrets.indices {
            let entrant = morceaux.last { $0.trajet && $0.arret == i - 1 }
            let sortant = morceaux.first { $0.trajet && $0.arret == i }
            arrets[i].imagesDe = entrant.map { ($0.debut + $0.fin) / 2 } ?? debut
            arrets[i].imagesA = sortant.map { ($0.debut + $0.fin) / 2 } ?? fin
        }
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
    /// Vitesse de lecture (×1, ×2 ou ×0,5) : l'horloge, l'icône et la caméra suivent.
    @State private var facteur: Double = 1
    @State private var camera: MapCameraPosition = .automatic
    /// Change quand la carte bouge (glissée, zoomée, cadrage animé) : l'icône suit.
    @State private var mouvementsCarte = 0
    @State private var itineraires = Itineraires.shared
    @State private var meteo = MeteoHoraire.shared
    /// Le lieu de la météo du jour (celle de la carte du jour dans le Programme) : l'animation en montre le détail heure par heure.
    @State private var lieuMeteoJour: CLLocationCoordinate2D?
    /// Ce que montre la carte, et sa taille : sert à limiter la vitesse de l'icône à l'écran.
    @State private var regionVisible: MKCoordinateRegion?
    @State private var tailleCarte: CGSize = .zero
    /// Le mouvement de caméra en cours (zoom, dézoom, déplacement), animé image par image.
    @State private var mouvement: MouvementCamera?
    /// L'image précédente de l'horloge : l'icône et la caméra avancent du temps réellement écoulé.
    @State private var dernierTic: Date?
    /// Avant la lecture : itinéraires, météo, photos et fonds de carte se chargent, pour que tout soit prêt.
    @State private var preparation = false
    /// Les photos des étapes, déjà décodées : elles s'affichent sans à-coup.
    @State private var imagesPretes: [String: CGImage] = [:]
    /// Un itinéraire arrivé en pleine lecture et qui change le trajet en cours : appliqué au trajet suivant.
    @State private var parcoursEnAttente: ParcoursJour?
    /// Les coins où sont posées les photos de l'étape : choisis quand elles apparaissent, puis gardés
    /// (sauf si l'icône ou le tracé viennent les recouvrir et qu'un autre coin est libre).
    @State private var coinsPhotos = CoinsPhotos()
    /// Durée d'un zoom, d'un dézoom ou d'un déplacement de la carte (secondes), à vitesse ×1.
    private let dureeZoom: Double = 1.5
    /// Vitesse maximale de l'icône à l'écran (points par seconde), à vitesse ×1.
    private let vitesseMax: Double = 70

    private var couleur: Color { CarteDuVoyage.couleur(du: numero - 1) }
    private var zone: TimeZone { voyage.fuseau(du: jour) }

    var body: some View {
        VStack(spacing: 0) {
            entete
            if let parcours {
                let meteoIci = meteoActuelle(parcours)
                let ciel = etatCiel(parcours, meteo: meteoIci)
                // La carte est posée dans un cadre qui a la couleur du ciel et le temps qu'il fait.
                VStack(spacing: 16) {
                    CielDuParcours(parcours: parcours, temps: temps, jour: jour, zone: zone, meteo: meteoIci, ciel: ciel)
                        .frame(height: 92)
                        .allowsHitTesting(false)
                    carte(parcours)
                        .overlay(alignment: .bottom) {
                            if preparation {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Préparation du parcours…").font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.bottom, 40)
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: preparation)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                }
                .padding(24)
                .background {
                    CadreMeteo(etat: ciel, jour: jour)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 6)
                commandes(parcours)
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
        .background { horloge }
        .task { await preparer() }
        .onChange(of: lecture) { _, enLecture in
            dernierTic = nil
            if enLecture, let p = parcours, temps >= p.fin - 0.5 { temps = p.debut }
            if !enLecture, let attente = parcoursEnAttente { parcours = attente; parcoursEnAttente = nil }
        }
        .onChange(of: itineraires.trajets.count) {
            // Un itinéraire est arrivé : le tracé suit désormais la route (en pleine lecture, sans toucher au trajet en cours).
            guard let p = ParcoursJour.calculer(voyage: voyage, jour: jour) else { return }
            if lecture, let actuel = parcours, !ParcoursJour.memeTrace(actuel, p, a: temps) {
                parcoursEnAttente = p
            } else {
                parcours = p
                parcoursEnAttente = nil
            }
        }
        .onChange(of: cleCamera) { _, cle in cadrer(cle) }
        .onDisappear { mouvement = nil; lecture = false }
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
        let finis = p.finis(a: temps)
        let enCours = p.traceEnCours(a: temps)
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
            // Les trajets finis ; celui en cours est dessiné par-dessus la carte, avec l'icône : la carte n'a pas
            // à refaire un tracé à chaque image.
            ForEach(finis, id: \.self) { i in
                MapPolyline(coordinates: p.morceaux[i].points)
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
        .onMapCameraChange(frequency: .continuous) { contexte in
            mouvementsCarte += 1
            regionVisible = contexte.region
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tailleCarte = $0 }
        // Les cadrages laissent libre le haut de la carte, où s'affiche le nom de l'étape.
        .safeAreaPadding(.top, Disposition.hauteurBandeau + 12)
        // Par-dessus la carte : le nom de l'étape, ses photos dans les coins les plus libres, et l'icône,
        // qui reste ainsi au-dessus des repères des étapes.
        .overlay {
            GeometryReader { geo in
                let _ = mouvementsCarte
                let origine = geo.frame(in: .global).origin
                let ecran: (CLLocationCoordinate2D) -> CGPoint? = { c in
                    proxy.convert(c, to: .global).map { CGPoint(x: $0.x - origine.x, y: $0.y - origine.y) }
                }
                let pointIcone = position.flatMap(ecran)
                let images = imagesActuelles(p)
                let nombre = min(images?.nombre ?? 0, 2)
                let place = Disposition(taille: geo.size, aEviter: pointsAEviter(p, ecran), icone: pointIcone)
                let cle = images.map { "\($0.id)-\(nombre)" } ?? ""
                let choisis = coinsPhotos.cle == cle ? coinsPhotos.coins : place.meilleurs(nombre)
                let titre = cleTitre(p)
                ZStack(alignment: .topLeading) {
                    if let enCours {
                        traceEnCours(enCours.compactMap(ecran), reperes: p.arrets.compactMap { ecran($0.coordonnee) },
                                     reperesSous: p.arrets.filter { p.sousEtapesVisibles($0, a: temps) }.flatMap { $0.sous.compactMap { ecran($0.coordonnee) } })
                    }
                    if let images {
                        ForEach(choisis.filter { $0 < place.coins.count }, id: \.self) { coin in
                            let k = choisis.firstIndex(of: coin) ?? 0
                            photo(images, k, cadre: place.coins[coin])
                                .id("\(images.id)-\(k)-\(coin)")
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    titreEtape(p)
                        .id(titre)
                        .transition(.asymmetric(insertion: .modifier(active: Apparition(part: 1, echelle: 1.25), identity: Apparition(part: 0, echelle: 1)),
                                                removal: .modifier(active: Apparition(part: 1, echelle: 0.85), identity: Apparition(part: 0, echelle: 1))))
                        .frame(width: max(place.bandeau.width, 0), height: place.bandeau.height)
                        .position(x: place.bandeau.midX, y: place.bandeau.midY)
                    if let pointIcone { icone(mode).position(pointIcone) }
                }
                .animation(.easeInOut(duration: 0.35), value: "\(cle)|\(choisis)")
                .animation(.easeOut(duration: 0.45), value: titre)
                // Les coins sont choisis à l'apparition des photos, puis ne bougent plus…
                .onChange(of: cle, initial: true) { _, nouvelle in
                    coinsPhotos = CoinsPhotos(cle: nouvelle, coins: place.meilleurs(nombre))
                }
                // … sauf si l'un d'eux se retrouve couvert alors qu'un autre coin est libre.
                .onChange(of: place.aDeplacer(choisis)) { _, deplacer in
                    if deplacer { coinsPhotos = CoinsPhotos(cle: cle, coins: place.meilleurs(nombre)) }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        }
    }

    // MARK: Nom et photos de l'étape

    /// L'arrêt dont on montre le titre et les photos : de la moitié du trajet qui y mène à la moitié du trajet suivant.
    private func arretAffiche(_ p: ParcoursJour) -> Int? {
        guard !p.morceaux.isEmpty else { return nil }
        return p.arrets.indices.last { temps >= p.arrets[$0].imagesDe && temps <= p.arrets[$0].imagesA }
    }

    /// La sous-étape de cet arrêt où l'on se trouve (pas en chemin vers elle).
    private func sousAffichee(_ p: ParcoursJour, _ i: Int) -> Int? {
        let m = p.morceaux[p.indice(a: temps)]
        guard m.arret == i, !m.trajet, !m.trajetSous, let k = m.sousArret, k < p.arrets[i].sous.count else { return nil }
        return k
    }

    /// Change quand le titre change (autre étape, autre sous-étape).
    private func cleTitre(_ p: ParcoursJour) -> String {
        guard let i = arretAffiche(p) else { return "" }
        return "\(i)-\(sousAffichee(p, i) ?? -1)"
    }

    /// En haut de la carte, sans cadre : l'étape (et la sous-étape où l'on est), en même temps que ses photos.
    /// Pas de titre pour les trajets. Le texte est détouré du fond de la carte pour rester lisible.
    private func titreEtape(_ p: ParcoursJour) -> some View {
        VStack(spacing: 2) {
            if let i = arretAffiche(p) {
                let a = p.arrets[i]
                Text(a.titre).font(.title.bold()).lineLimit(1)
                if let k = sousAffichee(p, i) {
                    Label(a.sous[k].titre, systemImage: "arrow.turn.down.right")
                        .font(.headline).foregroundStyle(couleur).lineLimit(1)
                } else if !Self.horaires(a).isEmpty {
                    Text(Self.horaires(a)).font(.headline).foregroundStyle(.secondary)
                }
            }
        }
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.center)
        .shadow(color: Color.fondParcours, radius: 1)
        .shadow(color: Color.fondParcours, radius: 1)
        .shadow(color: Color.fondParcours, radius: 3)
        .shadow(color: Color.fondParcours.opacity(0.8), radius: 8)
        .padding(.horizontal, 8)
    }

    static func horaires(_ a: ParcoursJour.Arret) -> String {
        switch (a.heureArrivee, a.heureDepart) {
        case let (d?, f?): "\(heure(d)) – \(heure(f))"
        case let (nil, f?): "Départ \(heure(f))"
        case let (d?, nil): "Arrivée \(heure(d))"
        default: ""
        }
    }

    /// Les images de l'étape dont on approche, où l'on est ou que l'on quitte (de la moitié du trajet aller
    /// à la moitié du trajet suivant) ; celles de la sous-étape quand on s'y trouve et qu'elle en a.
    private func imagesActuelles(_ p: ParcoursJour) -> (id: String, images: ParcoursJour.Images, nombre: Int)? {
        guard let i = arretAffiche(p) else { return nil }
        let a = p.arrets[i]
        func resultat(_ id: String, _ images: ParcoursJour.Images) -> (id: String, images: ParcoursJour.Images, nombre: Int)? {
            images.vide ? nil : (id, images, max(images.documents.count, 1))
        }
        if let k = sousAffichee(p, i), let r = resultat(a.sous[k].id, a.sous[k].images) { return r }
        return resultat(a.id, a.images)
    }

    /// Le trajet en cours, de son départ à l'icône, à l'écran. Il s'efface sur les repères des étapes et des
    /// sous-étapes, que la carte dessine dessous (centrés sur leur lieu ; celui d'une sous-étape, au-dessus de son nom).
    private func traceEnCours(_ points: [CGPoint], reperes: [CGPoint], reperesSous: [CGPoint]) -> some View {
        Canvas { ctx, _ in
            guard let premier = points.first else { return }
            var chemin = Path()
            chemin.move(to: premier)
            for q in points.dropFirst() { chemin.addLine(to: q) }
            ctx.stroke(chemin, with: .color(couleur), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ctx.blendMode = .clear
            for q in reperes {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 14, y: q.y - 14, width: 28, height: 28)), with: .color(.black))
            }
            for q in reperesSous {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 12, y: q.y - 21, width: 24, height: 24)), with: .color(.black))
            }
        }
    }

    private static func clePhoto(_ d: Document) -> String { "doc-\(d.uid)-\(d.donnees.count)" }
    private static func clePhoto(_ url: URL) -> String { "url-\(url.absoluteString)" }

    private func photo(_ i: (id: String, images: ParcoursJour.Images, nombre: Int), _ k: Int, cadre: CGRect) -> some View {
        Group {
            if k < i.images.documents.count, let image = imagesPretes[Self.clePhoto(i.images.documents[k])] {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if k >= i.images.documents.count, let url = i.images.url, let image = imagesPretes[Self.clePhoto(url)] {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if k < i.images.documents.count {
                VignetteDocument(document: i.images.documents[k], cote: 300)
            } else if let url = i.images.url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
            }
        }
        .frame(width: cadre.width, height: cadre.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white, lineWidth: 3))
        .overlay(alignment: .bottomTrailing) {
            // Plus de photos qu'il n'y a de place : leur nombre.
            if k == 1, i.nombre > 2 {
                Text("+\(i.nombre - 2)").font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        .rotationEffect(.degrees(k == 0 ? -3 : 3))
        .position(x: cadre.midX, y: cadre.midY)
    }

    /// Les points à l'écran du parcours affiché (tracés, repères), resserrés le long des lignes droites :
    /// le nom et les photos se placent là où il y en a le moins.
    private func pointsAEviter(_ p: ParcoursJour, _ ecran: (CLLocationCoordinate2D) -> CGPoint?) -> [CGPoint] {
        var r: [CGPoint] = []
        func ligne(_ coords: [CLLocationCoordinate2D]) {
            guard !coords.isEmpty else { return }
            let pas = max(1, coords.count / 40)
            var indices = Array(stride(from: 0, to: coords.count, by: pas))
            if indices.last != coords.count - 1 { indices.append(coords.count - 1) }
            var precedent: CGPoint?
            for k in indices {
                guard let q = ecran(coords[k]) else { precedent = nil; continue }
                if let a = precedent {
                    let n = min(Int(hypot(q.x - a.x, q.y - a.y) / 12), 80)
                    if n > 1 {
                        for j in 1..<n {
                            let f = CGFloat(j) / CGFloat(n)
                            r.append(CGPoint(x: a.x + (q.x - a.x) * f, y: a.y + (q.y - a.y) * f))
                        }
                    }
                }
                r.append(q)
                precedent = q
            }
        }
        for m in p.morceaux where m.points.count > 1 {
            if m.trajet || (m.trajetSous && p.sousEtapesVisibles(p.arrets[m.arret], a: temps)) { ligne(m.points) }
        }
        for a in p.arrets {
            if let q = ecran(a.coordonnee) { r.append(q) }
            if p.sousEtapesVisibles(a, a: temps) { r += a.sous.compactMap { ecran($0.coordonnee) } }
        }
        return r
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
            // ×1 → ×2 → ×0,5 → ×1… À vitesse normale, le bouton propose ×2.
            Button {
                facteur = facteur == 1 ? 2 : facteur == 2 ? 0.5 : 1
            } label: {
                Text(facteur == 0.5 ? "×0,5" : "×2")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(facteur != 1 ? .white : couleur)
                    .frame(width: 52, height: 32)
                    .background(facteur != 1 ? couleur : couleur.opacity(0.15), in: Capsule())
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: facteur)
            .accessibilityLabel(facteur == 1 ? "Accélérer deux fois" : facteur == 2 ? "Ralentir de moitié" : "Vitesse normale")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    static func heure(_ minutes: Double) -> String {
        let m = Int(minutes.rounded(.down)) % (24 * 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    // MARK: Météo

    /// La météo heure par heure au même endroit que la météo de la carte du jour : la carte résume ce que montre l'animation.
    /// Sans ce lieu, celle de l'étape la plus proche.
    private func meteoActuelle(_ p: ParcoursJour) -> [MeteoHeure] {
        if let lieuMeteoJour { return meteo.liste(lieuMeteoJour, jour: jour) }
        guard let position = p.position(a: temps) else { return [] }
        let lieux = p.lieuxMeteo
        guard let proche = lieux.min(by: { distance($0, position) < distance($1, position) }) else { return [] }
        return meteo.liste(proche, jour: jour)
    }

    /// Le ciel de l'heure au lieu où l'on est : ses couleurs et le temps qu'il fait.
    private func etatCiel(_ p: ParcoursJour, meteo liste: [MeteoHeure]) -> EtatCiel {
        let lieu = p.position(a: temps) ?? p.arrets.first?.coordonnee ?? CLLocationCoordinate2D()
        let instant = ParcoursJour.instant(jour, temps, zone: zone)
        let hauteur = Soleil.hauteur(instant, lieu)
        let actuelle = MeteoHoraire.a(instant, dans: liste)
        let couleurs = Soleil.couleursCiel(hauteur: hauteur, gris: actuelle?.gris ?? 0)
        return EtatCiel(haut: couleurs.haut, bas: couleurs.bas, hauteur: hauteur, code: actuelle?.code)
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = a.longitude - b.longitude, dy = a.latitude - b.latitude
        return dx * dx + dy * dy
    }

    // MARK: Lecture et caméra

    private func preparer() async {
        guard parcours == nil else { return }
        lieuMeteoJour = voyage.lieuMeteo(du: jour)
        let p = ParcoursJour.calculer(voyage: voyage, jour: jour)
        parcours = p
        pret = true
        guard let p else { return }
        temps = p.debut
        // On part de la première étape (ou de l'hôtel de la veille), de près.
        if let premier = p.arrets.first {
            camera = .region(MKCoordinateRegion(center: premier.coordonnee, latitudinalMeters: 1800, longitudinalMeters: 1800))
        }
        // On prépare tout avant de lancer la lecture (au plus 8 secondes : le reste arrivera pendant).
        preparation = true
        let debut = Date.now
        let travail = Task { @MainActor in
            async let routes: Void = chargerItineraires(p)
            async let ciel: Void = chargerMeteo(p)
            async let photos: Void = chargerPhotos(p)
            async let fonds: Void = chargerFondsDeCarte(p)
            _ = await (routes, ciel, photos, fonds)
            preparation = false
        }
        while preparation, Date.now.timeIntervalSince(debut) < 8, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let reste = 0.8 - Date.now.timeIntervalSince(debut)
        if reste > 0 { try? await Task.sleep(for: .seconds(reste)) }
        preparation = false
        if Task.isCancelled { travail.cancel(); return }
        lecture = true
    }

    /// Décode d'avance les photos qui s'afficheront (deux par étape au plus).
    private func chargerPhotos(_ p: ParcoursJour) async {
        let toutes = p.arrets.flatMap { [$0.images] + $0.sous.map(\.images) }
        for images in toutes {
            for d in images.documents.prefix(2) {
                let cle = Self.clePhoto(d)
                guard imagesPretes[cle] == nil else { continue }
                let donnees = d.donnees, ext = d.extensionFichier, uid = d.uid
                let image = await Task.detached(priority: .userInitiated) {
                    VignettesDocuments.image(de: donnees, extensionFichier: ext, cle: uid, cote: 300)
                }.value
                if let image { imagesPretes[cle] = image }
            }
            if images.documents.isEmpty, let url = images.url, imagesPretes[Self.clePhoto(url)] == nil,
               let (donnees, _) = try? await URLSession.shared.data(from: url) {
                let image = await Task.detached(priority: .userInitiated) { PhotoAlbum.vignette(donnees, cle: url.absoluteString, cote: 300) }.value
                if let image { imagesPretes[Self.clePhoto(url)] = image }
            }
        }
    }

    /// Fait venir d'avance les fonds de carte des cadrages de la journée (ils restent ensuite en cache).
    private func chargerFondsDeCarte(_ p: ParcoursJour) async {
        var regions: [MKCoordinateRegion] = []
        for m in p.morceaux where m.trajet {
            var points = m.points
            if m.arret + 1 < p.arrets.count { points += p.arrets[m.arret + 1].sous.map(\.coordonnee) }
            if let r = ParcoursJour.region(points) { regions.append(r) }
        }
        for a in p.arrets where !a.sous.isEmpty {
            if let r = ParcoursJour.region([a.coordonnee] + a.sous.map(\.coordonnee)) { regions.append(r) }
        }
        let taille = tailleCarte.width > 0 ? tailleCarte : CGSize(width: 360, height: 480)
        for region in regions.prefix(16) {
            guard !Task.isCancelled else { return }
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.size = taille
            options.pointOfInterestFilter = .excludingAll
            _ = try? await MKMapSnapshotter(options: options).start()
        }
    }

    private func chargerItineraires(_ p: ParcoursJour) async {
        for (a, b, mode) in p.aCharger { await Itineraires.shared.charger(a, b, mode) }
    }

    private func chargerMeteo(_ p: ParcoursJour) async {
        if let lieuMeteoJour { await meteo.charger(lieuMeteoJour, jour: jour); return }
        for lieu in p.lieuxMeteo { await meteo.charger(lieu, jour: jour) }
    }

    /// L'horloge de la lecture, calée sur l'affichage (60 images par seconde) : l'icône et la caméra avancent
    /// ensemble, à chaque image, du temps réellement écoulé.
    private var horloge: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !lecture && mouvement == nil)) { contexte in
            Color.clear.onChange(of: contexte.date) { _, date in tic(date) }
        }
        .allowsHitTesting(false)
    }

    private func tic(_ maintenant: Date) {
        // Après une image manquée, on ne saute pas : au plus 1/20 de seconde d'un coup.
        let dt = dernierTic.map { min(max(maintenant.timeIntervalSince($0), 0), 0.05) }
        dernierTic = maintenant
        if let m = mouvement {
            let (region, fini) = m.region(a: maintenant)
            var sansAnimation = Transaction()
            sansAnimation.disablesAnimations = true
            withTransaction(sansAnimation) { camera = .region(region) }
            if fini { mouvement = nil }
        }
        guard lecture, let dt, dt > 0, let p = parcours else { return }
        if let attente = parcoursEnAttente, ParcoursJour.memeTrace(p, attente, a: temps) {
            parcours = attente
            parcoursEnAttente = nil
        }
        var avance = dt * p.vitesse * facteur
        // L'icône ne dépasse pas la vitesse maximale à l'écran : l'horloge ralentit pendant les trajets rapides.
        if let a = p.position(a: temps), let b = p.position(a: min(p.fin, temps + avance)),
           let r = regionVisible, r.span.longitudeDelta > 0, r.span.latitudeDelta > 0, tailleCarte.width > 0 {
            let dx = (b.longitude - a.longitude) / r.span.longitudeDelta * tailleCarte.width
            let dy = (b.latitude - a.latitude) / r.span.latitudeDelta * tailleCarte.height
            let ecran = (dx * dx + dy * dy).squareRoot()
            let permis = vitesseMax * facteur * dt
            if ecran > permis { avance *= permis / ecran }
        }
        temps = min(p.fin, temps + avance)
        if temps >= p.fin { lecture = false }
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
        animerCamera(vers: region)
    }

    /// Mène la caméra jusqu'à la région en `dureeZoom` secondes, image par image (à chaque tic de l'horloge) :
    /// la carte de Plans ne respecte pas la durée d'une animation SwiftUI.
    private func animerCamera(vers arrivee: MKCoordinateRegion) {
        guard let depart = regionVisible else { camera = .region(arrivee); return }
        mouvement = MouvementCamera(depart: depart, arrivee: arrivee, debut: .now, duree: max(dureeZoom / facteur, 0.1))
    }
}

/// Un mouvement de la caméra d'une région à une autre : l'échelle change de façon régulière (interpolée
/// en logarithme), le centre glisse en même temps ; départ et arrivée en douceur.
private struct MouvementCamera {
    var depart: MKCoordinateRegion
    var arrivee: MKCoordinateRegion
    var debut: Date
    var duree: Double

    func region(a date: Date) -> (MKCoordinateRegion, fini: Bool) {
        let f = min(max(date.timeIntervalSince(debut) / duree, 0), 1)
        let e = f < 0.5 ? 2 * f * f : 1 - pow(-2 * f + 2, 2) / 2
        func melange(_ a: Double, _ b: Double) -> Double { a + (b - a) * e }
        func echelle(_ a: Double, _ b: Double) -> Double { exp(melange(log(max(a, 1e-6)), log(max(b, 1e-6)))) }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: melange(depart.center.latitude, arrivee.center.latitude),
                                           longitude: melange(depart.center.longitude, arrivee.center.longitude)),
            span: MKCoordinateSpan(latitudeDelta: echelle(depart.span.latitudeDelta, arrivee.span.latitudeDelta),
                                   longitudeDelta: echelle(depart.span.longitudeDelta, arrivee.span.longitudeDelta)))
        return (region, f >= 1)
    }
}

/// Les coins choisis pour les photos d'une étape (`cle` : l'étape et le nombre de photos).
private struct CoinsPhotos: Equatable {
    var cle = ""
    var coins: [Int] = []
}

/// L'effet du titre : il apparaît en se précisant (flou, grossi, transparent → net) et disparaît de même.
private struct Apparition: ViewModifier {
    var part: Double
    var echelle: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: 12 * part)
            .opacity(1 - part)
            .scaleEffect(echelle)
    }
}

/// Où poser, sur la carte, le titre de l'étape (toujours en haut) et ses photos : les quatre coins,
/// classés selon le nombre de points du parcours qui y passent (et jamais sur l'icône).
private struct Disposition: Equatable {
    static let hauteurBandeau: CGFloat = 64
    static let cotePhoto: CGFloat = 92
    var bandeau: CGRect
    var coins: [CGRect]
    var encombrements: [Int]

    init(taille: CGSize, aEviter: [CGPoint], icone: CGPoint?) {
        let marge: CGFloat = 10, hb = Self.hauteurBandeau, cote = Self.cotePhoto
        // En bas à gauche : le logo et les mentions de Plans.
        let pied: CGFloat = 30
        let w = taille.width, h = taille.height
        bandeau = CGRect(x: marge, y: 6, width: max(w - 2 * marge, 0), height: hb)
        guard w > cote * 2 + marge * 3, h > cote * 2 + hb + pied else { coins = []; encombrements = []; return }
        let yHaut = bandeau.maxY + 6, yBas = h - pied - cote
        // Ordre de préférence à égalité : en haut à droite, en haut à gauche, en bas à droite, en bas à gauche.
        coins = [CGRect(x: w - marge - cote, y: yHaut, width: cote, height: cote),
                 CGRect(x: marge, y: yHaut, width: cote, height: cote),
                 CGRect(x: w - marge - cote, y: yBas, width: cote, height: cote),
                 CGRect(x: marge, y: yBas, width: cote, height: cote)]
        encombrements = coins.map { r in
            let zone = r.insetBy(dx: -6, dy: -6)
            var n = aEviter.reduce(0) { $0 + (zone.contains($1) ? 1 : 0) }
            if let icone, r.insetBy(dx: -24, dy: -24).contains(icone) { n += 1000 }
            return n
        }
    }

    /// Les `nombre` coins les plus libres.
    func meilleurs(_ nombre: Int) -> [Int] {
        guard nombre > 0 else { return [] }
        return encombrements.indices.sorted { (encombrements[$0], $0) < (encombrements[$1], $1) }.prefix(nombre).map { $0 }
    }

    /// Un coin choisi est couvert (par l'icône, ou franchement par le tracé) alors qu'un coin libre reste disponible.
    func aDeplacer(_ choisis: [Int]) -> Bool {
        guard choisis.allSatisfy({ $0 < encombrements.count }) else { return false }
        let couvert = choisis.contains { encombrements[$0] >= 1000 || encombrements[$0] >= 12 }
        let libre = encombrements.indices.contains { !choisis.contains($0) && encombrements[$0] == 0 }
        return couvert && libre
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

// MARK: - Cadre météo

/// Le ciel de l'heure : ses couleurs, la hauteur du soleil et le code météo (WMO).
struct EtatCiel: Equatable {
    var haut: Color
    var bas: Color
    var hauteur: Double
    var code: Int?
}

/// Le pourtour de la carte : le même ciel que le fond des cartes de jour du Programme (`FondMeteo`), au temps de l'heure,
/// assombri la nuit. Sans météo, la couleur du ciel selon le soleil.
struct CadreMeteo: View {
    let etat: EtatCiel
    let jour: Date

    var body: some View {
        // De 0 (soleil levé) à 1 (nuit noire, soleil à 12° sous l'horizon).
        let nuit = min(max(-etat.hauteur / 12, 0), 1)
        ZStack {
            if let code = etat.code {
                FondMeteo(meteo: MeteoJour(date: jour, tMin: 0, tMax: 0, code: code))
                    .id(code)
                    .transition(.opacity)
                Color(red: 0.02, green: 0.04, blue: 0.14).opacity(0.62 * nuit)
            } else {
                LinearGradient(colors: [etat.haut, etat.bas], startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: etat.code)
    }
}

// MARK: - Ciel

/// Le bandeau du haut : le même fond météo que le cadre de la carte (assombri la nuit), la course du soleil
/// entre son lever et son coucher réels au lieu où l'on est, et la météo heure par heure.
private struct CielDuParcours: View {
    let parcours: ParcoursJour
    let temps: Double
    let jour: Date
    let zone: TimeZone
    let meteo: [MeteoHeure]
    /// Le même fond que le cadre autour de la carte.
    let ciel: EtatCiel

    var body: some View {
        let lieu = parcours.position(a: temps) ?? parcours.arrets.first?.coordonnee ?? CLLocationCoordinate2D()
        let instant = ParcoursJour.instant(jour, temps, zone: zone)
        let hauteur = Soleil.hauteur(instant, lieu)
        let actuelle = MeteoHoraire.a(instant, dans: meteo)
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
                CadreMeteo(etat: ciel, jour: jour)
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
}
