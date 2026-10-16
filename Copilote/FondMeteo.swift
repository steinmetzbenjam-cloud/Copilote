import SwiftUI
import CoreLocation

/// Fond d'une carte de jour à l'image de la météo prévue : un dégradé léger aux couleurs du temps
/// et le symbole du temps en grand, très estompé, dans le coin bas : il ne gêne pas la lecture des étapes.
struct FondMeteo: View {
    let meteo: MeteoJour
    /// Hauteur (depuis le haut) où poser le symbole ; nil : dans le coin bas (carte de l'Itinéraire).
    var hauteurSymbole: CGFloat? = nil
    @Environment(\.colorScheme) private var schema

    /// Deux teintes par temps : celle du haut (le ciel) et celle du bas.
    private var teintes: (haut: Color, bas: Color) {
        switch meteo.code {
        case 0: (Color(red: 1.0, green: 0.62, blue: 0.2), Color(red: 1.0, green: 0.85, blue: 0.35))
        case 1, 2: (Color(red: 0.3, green: 0.62, blue: 0.98), Color(red: 1.0, green: 0.82, blue: 0.4))
        case 3: (Color(red: 0.45, green: 0.52, blue: 0.62), Color(red: 0.62, green: 0.68, blue: 0.76))
        case 45, 48: (Color(red: 0.6, green: 0.63, blue: 0.67), Color(red: 0.78, green: 0.8, blue: 0.82))
        case 51...57, 61...67, 80...82: (Color(red: 0.2, green: 0.42, blue: 0.9), Color(red: 0.38, green: 0.36, blue: 0.85))
        case 71...77, 85, 86: (Color(red: 0.35, green: 0.75, blue: 0.95), Color(red: 0.75, green: 0.88, blue: 1.0))
        case 95...99: (Color(red: 0.45, green: 0.3, blue: 0.85), Color(red: 0.25, green: 0.25, blue: 0.55))
        default: (Color(red: 0.5, green: 0.58, blue: 0.68), Color(red: 0.68, green: 0.74, blue: 0.8))
        }
    }

    var body: some View {
        let force = schema == .dark ? 0.26 : 0.17
        ZStack(alignment: hauteurSymbole == nil ? .bottomTrailing : .topTrailing) {
            LinearGradient(colors: [teintes.haut.opacity(force), teintes.bas.opacity(force * 0.35)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            // Soleil : un halo chaud en haut à droite.
            if meteo.code <= 2 {
                RadialGradient(colors: [teintes.bas.opacity(force * 1.4), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            }
            Image(systemName: meteo.symbole)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 130, weight: .light))
                .foregroundStyle(teintes.haut.opacity(schema == .dark ? 0.16 : 0.12))
                .offset(x: 22, y: hauteurSymbole ?? 26)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Petite étiquette du temps prévu : symbole, températures et risque de pluie.
struct EtiquetteMeteo: View {
    let meteo: MeteoJour

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: meteo.symbole).symbolRenderingMode(.multicolor)
            Text("\(Int(meteo.tMax.rounded()))° / \(Int(meteo.tMin.rounded()))°").monospacedDigit()
            if let p = meteo.pluie, p >= 30 {
                Label("\(p) %", systemImage: "drop.fill").labelStyle(.titleAndIcon).foregroundStyle(.blue)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meteo.libelle), \(Int(meteo.tMax.rounded())) degrés")
    }
}

extension Voyage {
    /// Où prévoir la météo d'un jour : le milieu de ses étapes et de ses hébergements placés sur la carte,
    /// sinon de ses lieux de référence (hors pays entiers). nil : rien de précis ce jour-là.
    func lieuMeteo(du jour: Date) -> CLLocationCoordinate2D? {
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: jour) ?? jour
        var points = (etapes(du: jour) + hebergements(apres: jour)).compactMap(\.coordonnee)
        if points.isEmpty { points = (infos(du: jour)?.lieux ?? []).filter { !$0.estPays }.map(\.coordonnee) }
        if points.isEmpty { points = hebergements(apres: veille).compactMap(\.coordonnee) }
        guard !points.isEmpty else { return nil }
        return CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                      longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
    }
}

extension Voyage {
    /// Les jours couverts par les prévisions (aujourd'hui et les 15 suivants).
    var joursPrevisibles: [Date] {
        let cal = Calendar.current
        let aujourdhui = cal.startOfDay(for: .now)
        let limite = cal.date(byAdding: .day, value: 15, to: aujourdhui) ?? aujourdhui
        return jours.filter { $0 >= aujourdhui && $0 <= limite }
    }

    /// Change quand les lieux des jours à prévoir changent : la météo est alors à recharger.
    var cleMeteo: String {
        joursPrevisibles.map { j in lieuMeteo(du: j).map { Meteo.cle($0) } ?? "-" }.joined(separator: "|")
    }
}

extension Meteo {
    /// Recharge les prévisions (si elles ont plus de trois heures) de chaque lieu des jours à venir du voyage.
    /// `lieuVoyage` : pour les jours sans lieu précis.
    func chargerJours(de voyage: Voyage, lieuVoyage: CLLocationCoordinate2D?) async {
        var lieux: [String: CLLocationCoordinate2D] = [:]
        for j in voyage.joursPrevisibles {
            if let lieu = voyage.lieuMeteo(du: j) ?? lieuVoyage { lieux[Self.cle(lieu)] = lieu }
        }
        for lieu in lieux.values { await actualiserSiAncienne(lieu) }
    }

    /// La prévision d'un jour du voyage, à l'endroit où l'on est ce jour-là.
    func prevision(_ jour: Date, de voyage: Voyage, lieuVoyage: CLLocationCoordinate2D?) -> MeteoJour? {
        guard let lieu = voyage.lieuMeteo(du: jour) ?? lieuVoyage else { return nil }
        return prevision(jour, en: lieu)
    }

    /// La prévision d'un jour en ce lieu, si elle est connue.
    func prevision(_ jour: Date, en lieu: CLLocationCoordinate2D) -> MeteoJour? {
        jours(pour: lieu).first { Calendar.current.isDate($0.date, inSameDayAs: jour) }
    }

    /// Actualise seulement si la dernière prévision pour ce lieu a plus de trois heures.
    func actualiserSiAncienne(_ lieu: CLLocationCoordinate2D) async {
        _ = jours(pour: lieu)
        if let date = misAJour[Self.cle(lieu)], Date.now.timeIntervalSince(date) < 3 * 3600 { return }
        await actualiser(lieu)
    }
}
