import SwiftUI
import CoreLocation

/// Fond d'une carte de jour à l'image du ciel prévu, dans l'esprit de l'app Météo d'Apple : un ciel en dégradé,
/// le halo du soleil, des nuages flous, des traits de pluie ou des flocons. Le contenu posé dessus s'affiche en clair
/// (voir `cielMeteo(_:)`), comme dans Météo, pour rester lisible.
struct FondMeteo: View {
    let meteo: MeteoJour
    /// Hauteur (depuis le haut) où placer le soleil ; nil : en haut de la carte. Sert à la colonne du Timing, très haute.
    var hauteurSymbole: CGFloat? = nil
    /// Force du ciel : 1 pour une carte entière ; moins quand il passe sous d'autres couleurs (Timing).
    var intensite: Double = 1

    enum Ciel { case soleil, voile, couvert, brouillard, bruine, pluie, orage, neige }

    var ciel: Ciel {
        switch meteo.code {
        case 0: .soleil
        case 1, 2: .voile
        case 45, 48: .brouillard
        case 51...57: .bruine
        case 61...67, 80...82: .pluie
        case 71...77, 85, 86: .neige
        case 95...99: .orage
        default: .couvert
        }
    }

    /// Le ciel, du haut vers le bas, d'après l'app Météo : bleu pur au soleil, bleu vif aux éclaircies,
    /// gris clair bleuté par temps nuageux, gris-bleu sous la bruine, gris neutre sous la pluie.
    private var couleurs: [Color] {
        switch ciel {
        case .soleil: [Color(red: 0.22, green: 0.44, blue: 0.76), Color(red: 0.36, green: 0.58, blue: 0.86)]
        case .voile: [Color(red: 0.25, green: 0.50, blue: 0.84), Color(red: 0.40, green: 0.62, blue: 0.90)]
        case .couvert: [Color(red: 0.55, green: 0.59, blue: 0.65), Color(red: 0.47, green: 0.51, blue: 0.57)]
        case .brouillard: [Color(red: 0.62, green: 0.65, blue: 0.69), Color(red: 0.54, green: 0.57, blue: 0.61)]
        case .bruine: [Color(red: 0.45, green: 0.50, blue: 0.58), Color(red: 0.38, green: 0.44, blue: 0.52)]
        case .pluie: [Color(red: 0.45, green: 0.47, blue: 0.51), Color(red: 0.38, green: 0.40, blue: 0.45)]
        case .orage: [Color(red: 0.36, green: 0.36, blue: 0.43), Color(red: 0.29, green: 0.29, blue: 0.36)]
        case .neige: [Color(red: 0.60, green: 0.66, blue: 0.74), Color(red: 0.52, green: 0.58, blue: 0.67)]
        }
    }

    var body: some View {
        LinearGradient(colors: couleurs, startPoint: .top, endPoint: .bottom)
            .overlay { decor }
            .opacity(intensite)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Un nuage bien dessiné (cumulus) : une base allongée surmontée de bosses rondes.
    private static func cumulus(_ ctx: inout GraphicsContext, centre: CGPoint, largeur: Double, couleur: Color, hasard: inout Hasard) {
        let base = CGRect(x: centre.x - largeur / 2, y: centre.y - largeur * 0.12, width: largeur, height: largeur * 0.3)
        ctx.fill(Path(roundedRect: base, cornerRadius: largeur * 0.15), with: .color(couleur))
        let bosses = 4
        for i in 0..<bosses {
            let r = largeur * hasard.entre(0.14, 0.24)
            let x = centre.x - largeur * 0.38 + largeur * 0.76 * Double(i) / Double(bosses - 1)
            let y = centre.y - largeur * 0.08 - r * hasard.entre(0.4, 0.9)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.5, width: r * 2, height: r * 2)), with: .color(couleur))
        }
    }

    /// Le soleil, les nuages et les précipitations, dessinés une fois pour toutes (toujours les mêmes pour un jour donné).
    private var decor: some View {
        Canvas { ctx, taille in
            var hasard = Hasard(graine: UInt64(max(meteo.date.timeIntervalSince1970, 1)) &+ UInt64(meteo.code))
            let w = taille.width, h = taille.height
            let ySoleil = min(hauteurSymbole ?? 0, h)
            let zone = min(h - ySoleil, 380)

            // Soleil : un cœur éclatant en haut à droite, un grand halo, un anneau irisé et quelques reflets (comme Météo).
            if ciel == .soleil || ciel == .voile {
                let centre = CGPoint(x: w * 0.8, y: ySoleil + 6)
                let rayon = min(max(w, 260), 520) * 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: centre.x - rayon, y: centre.y - rayon, width: rayon * 2, height: rayon * 2)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(ciel == .soleil ? 0.5 : 0.3), .white.opacity(0.08), .clear]),
                                               center: centre, startRadius: 0, endRadius: rayon))
                ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 30, y: centre.y - 30, width: 60, height: 60)),
                         with: .radialGradient(Gradient(colors: [.white, .white.opacity(0.7), .white.opacity(0)]), center: centre, startRadius: 0, endRadius: 30))
                if ciel == .soleil {
                    ctx.drawLayer { couche in
                        couche.addFilter(.blur(radius: 3))
                        let anneau = 78.0
                        couche.stroke(Path(ellipseIn: CGRect(x: centre.x - anneau, y: centre.y - anneau, width: anneau * 2, height: anneau * 2)),
                                      with: .color(.white.opacity(0.16)), lineWidth: 5)
                        // Reflets : de petits disques le long d'une ligne qui part du soleil vers le centre de la carte.
                        for (t, r) in [(0.35, 12.0), (0.55, 7.0), (0.8, 16.0)] {
                            let p = CGPoint(x: centre.x + (w * 0.45 - centre.x) * t, y: centre.y + (min(h, ySoleil + 200) - centre.y) * t)
                            couche.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.10)))
                        }
                    }
                }
            }

            // Éclaircies : des nuages blancs bien dessinés, surtout sur la droite et en bas, là où il y a peu de texte,
            // et assez transparents pour que le texte blanc reste lisible quand il passe dessus.
            if ciel == .voile {
                ctx.drawLayer { couche in
                    couche.addFilter(.blur(radius: 9))
                    for i in 0..<3 {
                        let centre = CGPoint(x: hasard.entre(i == 0 ? 0.1 : 0.55, 0.95) * w, y: ySoleil + hasard.entre(0.35, 1.0) * zone)
                        FondMeteo.cumulus(&couche, centre: centre, largeur: min(w * hasard.entre(0.22, 0.32), 200),
                                          couleur: .white.opacity(0.38), hasard: &hasard)
                    }
                }
            }

            // Nuageux, bruine, neige : un ciel voilé de nuages clairs et étirés.
            if ciel == .couvert || ciel == .bruine || ciel == .neige {
                ctx.drawLayer { couche in
                    couche.addFilter(.blur(radius: 12))
                    for _ in 0..<9 {
                        let largeur = w * hasard.entre(0.35, 0.7)
                        let hauteur = largeur * hasard.entre(0.12, 0.22)
                        let x = hasard.entre(-0.25, 0.9) * w
                        let y = ySoleil + hasard.entre(-0.1, 0.7) * zone
                        couche.fill(Path(ellipseIn: CGRect(x: x, y: y, width: largeur, height: hauteur)),
                                    with: .color(.white.opacity(ciel == .couvert ? 0.16 : 0.24)))
                    }
                }
            }

            // Pluie et orage : de grosses masses nuageuses grises en haut, plus sombres que le ciel.
            if ciel == .pluie || ciel == .orage {
                ctx.drawLayer { couche in
                    couche.addFilter(.blur(radius: 14))
                    for _ in 0..<7 {
                        let centre = CGPoint(x: hasard.entre(0, 1) * w, y: ySoleil + hasard.entre(0, 0.5) * zone)
                        let sombre = Color(white: ciel == .orage ? 0.18 : 0.26).opacity(ciel == .orage ? 0.45 : 0.35)
                        FondMeteo.cumulus(&couche, centre: centre, largeur: w * hasard.entre(0.3, 0.5), couleur: sombre, hasard: &hasard)
                    }
                    for _ in 0..<4 {
                        let centre = CGPoint(x: hasard.entre(0, 1) * w, y: ySoleil + hasard.entre(-0.05, 0.35) * zone)
                        FondMeteo.cumulus(&couche, centre: centre, largeur: w * hasard.entre(0.2, 0.35), couleur: .white.opacity(0.10), hasard: &hasard)
                    }
                }
            }

            // Brouillard : des bandes horizontales floues.
            if ciel == .brouillard {
                ctx.drawLayer { couche in
                    couche.addFilter(.blur(radius: 14))
                    var y = 10.0
                    while y < h {
                        couche.fill(Path(CGRect(x: -20, y: y, width: w + 40, height: 18)), with: .color(.white.opacity(hasard.entre(0.12, 0.22))))
                        y += hasard.entre(38, 60)
                    }
                }
            }

            // Bruine : quelques rayons de lumière qui percent les nuages, en éventail depuis le haut.
            if ciel == .bruine {
                ctx.drawLayer { couche in
                    couche.addFilter(.blur(radius: 18))
                    let origine = CGPoint(x: w * 0.55, y: ySoleil - 40)
                    for i in 0..<5 {
                        let angle = Double(i - 2) * 0.22 + hasard.entre(-0.05, 0.05)
                        let longueur = zone + 40
                        let fin = CGPoint(x: origine.x + sin(angle) * longueur, y: origine.y + cos(angle) * longueur)
                        var rayon = Path()
                        rayon.move(to: CGPoint(x: origine.x - 6, y: origine.y))
                        rayon.addLine(to: CGPoint(x: origine.x + 6, y: origine.y))
                        rayon.addLine(to: CGPoint(x: fin.x + 26, y: fin.y))
                        rayon.addLine(to: CGPoint(x: fin.x - 26, y: fin.y))
                        rayon.closeSubpath()
                        couche.fill(rayon, with: .linearGradient(Gradient(colors: [.white.opacity(0.14), .clear]), startPoint: origine, endPoint: fin))
                    }
                }
            }

            // Gouttes fines et verticales : clairsemées pour la bruine, denses pour la pluie, les averses et l'orage.
            // Neige : des flocons ronds.
            let surface = w * h
            if ciel == .bruine || ciel == .pluie || ciel == .orage {
                let dense = ciel != .bruine
                let n = Int(surface / (dense ? 220 : 1100))
                for _ in 0..<n {
                    let x = hasard.entre(0, 1) * w, y = hasard.entre(0, 1) * h
                    let longueur = dense ? hasard.entre(8, 20) : hasard.entre(5, 12)
                    var trait = Path()
                    trait.move(to: CGPoint(x: x, y: y))
                    trait.addLine(to: CGPoint(x: x - longueur * 0.03, y: y + longueur))
                    ctx.stroke(trait, with: .color(.white.opacity(dense ? hasard.entre(0.10, 0.28) : hasard.entre(0.08, 0.2))),
                               lineWidth: dense ? hasard.entre(0.7, 1.2) : 1)
                }
            }
            if ciel == .neige {
                let n = Int(surface / 700)
                for _ in 0..<n {
                    let r = hasard.entre(1, 2.8)
                    let x = hasard.entre(0, 1) * w, y = hasard.entre(0, 1) * h
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(hasard.entre(0.4, 0.85))))
                }
            }
        }
    }
}

/// Un tirage pseudo-aléatoire reproductible : le même jour donne toujours le même ciel.
private struct Hasard {
    var etat: UInt64
    init(graine: UInt64) { etat = graine &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func suivant() -> Double {
        etat = etat &* 6364136223846793005 &+ 1442695040888963407
        return Double((etat >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
    mutating func entre(_ a: Double, _ b: Double) -> Double { a + (b - a) * suivant() }
}

extension Color {
    /// La couleur rapprochée du blanc (`part` de 0 à 1) : une couleur de jour qui reste lisible sur un ciel sombre.
    func eclaircie(_ part: Double) -> Color {
        let c = resolve(in: EnvironmentValues())
        let m = Float(part)
        return Color(red: Double(c.red + (1 - c.red) * m), green: Double(c.green + (1 - c.green) * m),
                     blue: Double(c.blue + (1 - c.blue) * m), opacity: Double(c.opacity))
    }
}

extension View {
    /// Sur un ciel, un panneau dépoli et un peu sombre sous le contenu (comme les cadres de l'app Météo) :
    /// le détail d'une étape reste lisible quel que soit le temps. Sans ciel, rien ne change.
    @ViewBuilder func cadreSurCiel(_ actif: Bool) -> some View {
        if actif {
            self
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.18)))
                }
        } else {
            self
        }
    }

    /// Pose le ciel du temps prévu sous une carte (aux coins arrondis) et en affiche le contenu en clair, comme l'app Météo.
    /// Sans prévision : la carte reste comme avant.
    @ViewBuilder func cielMeteo(_ meteo: MeteoJour?, rayon: CGFloat = 16) -> some View {
        if let meteo {
            self
                .environment(\.colorScheme, .dark)
                // Une ombre légère sous le texte, comme dans Météo : lisible même sur un nuage clair.
                .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                .background { FondMeteo(meteo: meteo).clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous)) }
        } else {
            self
        }
    }
}

/// Petite étiquette du temps prévu : symbole, températures et risque de pluie.
struct EtiquetteMeteo: View {
    let meteo: MeteoJour
    @Environment(\.colorScheme) private var schema

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: meteo.symbole).symbolRenderingMode(.multicolor)
            Text("\(Int(meteo.tMax.rounded()))° / \(Int(meteo.tMin.rounded()))°").monospacedDigit()
            if let p = meteo.pluie, p >= 30 {
                // Bleu clair sur un ciel ou en mode sombre, comme dans l'app Météo ; bleu franc sur fond clair.
                Label("\(p) %", systemImage: "drop.fill").labelStyle(.titleAndIcon)
                    .foregroundStyle(schema == .dark ? Color(red: 0.45, green: 0.80, blue: 1.0) : .blue)
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
