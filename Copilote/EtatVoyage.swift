import SwiftUI
import SwiftData
import MapKit
import Network
import Observation

/// Où en est le voyage : avant le départ, en cours, ou terminé.
enum EtatVoyage {
    case avant(jours: Int)
    case pendant(jour: Int, sur: Int)
    case apres(jours: Int)
}

extension Voyage {
    var etat: EtatVoyage {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: .now)
        let debut = cal.startOfDay(for: self.debut), fin = cal.startOfDay(for: self.fin)
        if aujourdhui < debut { return .avant(jours: cal.dateComponents([.day], from: aujourdhui, to: debut).day ?? 0) }
        if aujourdhui > fin { return .apres(jours: cal.dateComponents([.day], from: fin, to: aujourdhui).day ?? 0) }
        return .pendant(jour: (cal.dateComponents([.day], from: debut, to: aujourdhui).day ?? 0) + 1, sur: nombreDeJours)
    }

    /// « J-34 », « Jour 3/8 », « Terminé ».
    var compteARebours: String {
        switch etat {
        case .avant(let j): j == 0 ? "Départ demain" : "J-\(j)"
        case .pendant(let j, let n): "Jour \(j)/\(n)"
        case .apres: "Terminé"
        }
    }

    /// Le jour du voyage à mettre en avant : aujourd'hui s'il est en cours, sinon le premier jour (avant le départ).
    var jourEnAvant: (jour: Date, aujourdhui: Bool)? {
        let cal = Calendar.current
        switch etat {
        case .pendant: return (cal.startOfDay(for: .now), true)
        case .avant: return jours.first.map { ($0, false) }
        case .apres: return nil
        }
    }

    /// Où prévoir la météo : la moyenne des étapes localisées, sinon le centre du premier pays.
    func lieuMeteo() async -> CLLocationCoordinate2D? {
        let points = etapes.compactMap(\.coordonnee)
        if !points.isEmpty {
            return CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                          longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
        }
        if let code = pays.first { return await Pays.region(de: code)?.center }
        return nil
    }
}

// MARK: - Réseau

/// Surveille la connexion : sert à dire quand l'app travaille hors ligne.
@MainActor @Observable
final class Reseau {
    static let shared = Reseau()
    private(set) var enLigne = true
    @ObservationIgnored private let moniteur = NWPathMonitor()

    private init() {
        moniteur.pathUpdateHandler = { chemin in
            let ok = chemin.status == .satisfied
            Task { @MainActor in Reseau.shared.enLigne = ok }
        }
        moniteur.start(queue: DispatchQueue(label: "copilote.reseau"))
    }
}

// MARK: - Météo

struct MeteoJour: Codable, Identifiable {
    var date: Date
    var tMin: Double
    var tMax: Double
    var code: Int
    var pluie: Int?
    /// Le temps qu'il a fait (relevé), et non une prévision : il ne changera plus.
    var observe: Bool? = nil
    var id: Date { date }

    var symbole: String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    var libelle: String {
        switch code {
        case 0: "Ensoleillé"
        case 1, 2: "Peu nuageux"
        case 3: "Couvert"
        case 45, 48: "Brouillard"
        case 51...57: "Bruine"
        case 61...67: "Pluie"
        case 71...77, 85, 86: "Neige"
        case 80...82: "Averses"
        case 95...99: "Orage"
        default: "Nuageux"
        }
    }

    var couleur: Color {
        switch code {
        case 0: .orange
        case 1, 2: .yellow
        case 61...67, 80...82, 51...57: .blue
        case 95...99: .purple
        case 71...77, 85, 86: .cyan
        default: .gray
        }
    }
}

/// Prévisions sur 16 jours, et le temps qu'il a fait les 14 derniers jours, via Open-Meteo (gratuit, sans clé).
/// Tout est gardé sur l'appareil, pour le hors-ligne et pour retrouver la météo des jours passés longtemps après.
@MainActor @Observable
final class Meteo {
    static let shared = Meteo()
    private(set) var prevision: [String: [MeteoJour]] = [:]
    private(set) var misAJour: [String: Date] = [:]
    private var archivesEnCours: Set<String> = []

    nonisolated static func cle(_ c: CLLocationCoordinate2D) -> String { String(format: "%.1f,%.1f", c.latitude, c.longitude) }

    private init() {}

    func jours(pour c: CLLocationCoordinate2D) -> [MeteoJour] {
        let cle = Self.cle(c)
        if let v = prevision[cle] { return v }
        if let donnees = UserDefaults.standard.data(forKey: "meteo-\(cle)"),
           let v = try? Self.decodeur.decode([MeteoJour].self, from: donnees) {
            prevision[cle] = v
            misAJour[cle] = UserDefaults.standard.object(forKey: "meteoDate-\(cle)") as? Date
            return v
        }
        return []
    }

    func actualiser(_ c: CLLocationCoordinate2D) async {
        let cle = Self.cle(c)
        var composants = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        composants.queryItems = [
            URLQueryItem(name: "latitude", value: String(c.latitude)),
            URLQueryItem(name: "longitude", value: String(c.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16"),
            // Les jours passés du voyage : leur prévision est remplacée par le temps qu'il a fait.
            URLQueryItem(name: "past_days", value: "14"),
        ]
        guard let url = composants.url,
              let (donnees, reponse) = try? await URLSession.shared.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let jour = json["daily"] as? [String: Any],
              let dates = jour["time"] as? [String],
              let codes = jour["weather_code"] as? [Any],
              let maxi = jour["temperature_2m_max"] as? [Any],
              let mini = jour["temperature_2m_min"] as? [Any] else { return }
        let pluie = jour["precipitation_probability_max"] as? [Any]
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.locale = Locale(identifier: "en_US_POSIX")
        let aujourdhui = Calendar.current.startOfDay(for: .now)
        var liste: [MeteoJour] = []
        for (i, texte) in dates.enumerated() {
            guard let date = format.date(from: texte), i < codes.count, i < maxi.count, i < mini.count,
                  let code = (codes[i] as? NSNumber)?.intValue,
                  let tmax = (maxi[i] as? NSNumber)?.doubleValue, let tmin = (mini[i] as? NSNumber)?.doubleValue else { continue }
            let jour = Calendar.current.startOfDay(for: date)
            liste.append(MeteoJour(date: jour, tMin: tmin, tMax: tmax, code: code,
                                   pluie: pluie.flatMap { i < $0.count ? ($0[i] as? NSNumber)?.intValue : nil },
                                   observe: jour < aujourdhui))
        }
        guard !liste.isEmpty else { return }
        garder(liste, cle: cle, c: c)
    }

    /// Le temps qu'il a fait des jours plus anciens que ceux que donnent les prévisions (archive d'Open-Meteo, relevés),
    /// demandé une fois pour toutes : ils remplacent la prévision gardée à l'époque.
    func completerPasse(_ c: CLLocationCoordinate2D, jours: [Date]) async {
        let cle = Self.cle(c)
        guard let premier = jours.min(), let dernier = jours.max(), !archivesEnCours.contains(cle) else { return }
        archivesEnCours.insert(cle)
        defer { archivesEnCours.remove(cle) }
        let texte = DateFormatter()
        texte.dateFormat = "yyyy-MM-dd"
        texte.locale = Locale(identifier: "en_US_POSIX")
        var composants = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
        composants.queryItems = [
            URLQueryItem(name: "latitude", value: String(c.latitude)),
            URLQueryItem(name: "longitude", value: String(c.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: texte.string(from: premier)),
            URLQueryItem(name: "end_date", value: texte.string(from: dernier)),
        ]
        guard let url = composants.url,
              let (donnees, reponse) = try? await URLSession.shared.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let jour = json["daily"] as? [String: Any],
              let dates = jour["time"] as? [String],
              let codes = jour["weather_code"] as? [Any],
              let maxi = jour["temperature_2m_max"] as? [Any],
              let mini = jour["temperature_2m_min"] as? [Any] else { return }
        var liste: [MeteoJour] = []
        for (i, t) in dates.enumerated() {
            guard let date = texte.date(from: t), i < codes.count, i < maxi.count, i < mini.count,
                  let code = (codes[i] as? NSNumber)?.intValue,
                  let tmax = (maxi[i] as? NSNumber)?.doubleValue, let tmin = (mini[i] as? NSNumber)?.doubleValue else { continue }
            liste.append(MeteoJour(date: Calendar.current.startOfDay(for: date), tMin: tmin, tMax: tmax, code: code, observe: true))
        }
        guard !liste.isEmpty else { return }
        garder(liste, cle: cle, c: c, date: misAJour[cle])
    }

    /// Ajoute ces jours à ceux déjà gardés pour ce lieu (sans rien perdre), sur l'appareil.
    private func garder(_ nouveaux: [MeteoJour], cle: String, c: CLLocationCoordinate2D, date: Date? = .now) {
        var liste = nouveaux
        // Les jours déjà gardés qui ne sont plus dans la réponse (passés depuis plus de 14 jours) restent :
        // le temps qu'il a fait pendant le voyage se retrouve même longtemps après.
        var parJour: [Date: MeteoJour] = [:]
        for j in jours(pour: c) { parJour[j.date] = j }
        // Une journée finie garde le temps relevé : une prévision ne le remplace jamais.
        for j in liste where !(parJour[j.date]?.observe == true && j.observe != true) { parJour[j.date] = j }
        liste = parJour.values.sorted { $0.date < $1.date }
        prevision[cle] = liste
        misAJour[cle] = date
        if let d = try? JSONEncoder().encode(liste) {
            UserDefaults.standard.set(d, forKey: "meteo-\(cle)")
            UserDefaults.standard.set(date, forKey: "meteoDate-\(cle)")
        }
    }

    private static let decodeur = JSONDecoder()
}
