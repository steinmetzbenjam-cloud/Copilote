import SwiftUI
import MapKit
import SwiftData

/// Les fonds de carte proposés par Plans.
enum FondCarte: String, CaseIterable, Identifiable {
    case plan, transports, satellite, mixte, relief
    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .plan: "Plan"
        case .transports: "Transports"
        case .satellite: "Satellite"
        case .mixte: "Satellite avec noms"
        case .relief: "Plan en relief"
        }
    }

    var symbole: String {
        switch self {
        case .plan: "map"
        case .transports: "tram.fill"
        case .satellite: "globe.europe.africa.fill"
        case .mixte: "square.2.layers.3d"
        case .relief: "mountain.2"
        }
    }

    var style: MapStyle {
        switch self {
        case .plan: .standard
        // Le plan, avec seulement les gares, stations de métro, de tram et de bus (et les aéroports) : on les repère d'un coup d'œil.
        case .transports: .standard(emphasis: .muted, pointsOfInterest: .including([.publicTransport, .airport]))
        case .satellite: .imagery(elevation: .realistic)
        case .mixte: .hybrid(elevation: .realistic)
        case .relief: .standard(elevation: .realistic, emphasis: .muted)
        }
    }
}

/// Une gare ou une station (métro, tram, bus) trouvée dans la zone affichée.
struct StationCarte: Identifiable {
    var nom: String
    var coordonnee: CLLocationCoordinate2D
    var id: String { "\(nom)|\(coordonnee.latitude)|\(coordonnee.longitude)" }

    var symbole: String {
        let n = nom.lowercased()
        if n.contains("gare") || n.contains("station") && n.contains("train") || n.contains("rer") { return "train.side.front.car" }
        if n.contains("tram") { return "lightrail.fill" }
        if n.contains("bus") || n.contains("arrêt") { return "bus.fill" }
        return "tram.fill"
    }
}

/// Un point d'intérêt de la carte (restaurant, musée, plage…) qui peut devenir une étape.
struct LieuCarte: Identifiable {
    let id = UUID()
    var nom: String
    var coordonnee: CLLocationCoordinate2D
    var categorie: CategorieEtape
    /// Adresse et site, quand Plans les donne.
    var adresse: String?
    var site: String?
    #if os(iOS)
    var feature: MapFeature?

    init(feature f: MapFeature) {
        nom = f.title ?? "Lieu"
        coordonnee = f.coordinate
        categorie = CategorieEtape(pointDInteret: f.pointOfInterestCategory)
        feature = f
    }
    #endif

    init(item: MKMapItem) {
        nom = item.name ?? "Lieu"
        coordonnee = item.placemark.coordinate
        categorie = CategorieEtape(pointDInteret: item.pointOfInterestCategory)
        let morceaux = [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }
        adresse = morceaux.isEmpty ? nil : morceaux.joined(separator: ", ")
        site = item.url?.absoluteString
    }

    /// Le point d'intérêt le plus proche d'un endroit cliqué, dans un rayon en mètres.
    static func plusProche(de c: CLLocationCoordinate2D, rayon: CLLocationDistance) async -> LieuCarte? {
        let requete = MKLocalPointsOfInterestRequest(center: c, radius: rayon)
        guard let reponse = try? await MKLocalSearch(request: requete).start() else { return nil }
        let ici = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let proche = reponse.mapItems.min {
            ici.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                < ici.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
        }
        return proche.map(LieuCarte.init(item:))
    }
}

extension Voyage {
    /// Crée une étape à partir d'un point d'intérêt de la carte (nom, position, catégorie, adresse, site) :
    /// à la fin du jour donné, ou « à placer » sans jour.
    @discardableResult
    func creerEtape(depuis lieu: LieuCarte, jour: Date?, dans contexte: ModelContext) -> Etape {
        let etape = Etape(titre: lieu.nom, jour: jour.map { Calendar.current.startOfDay(for: $0) }, categorie: lieu.categorie)
        etape.lieu = lieu.adresse.map { "\(lieu.nom), \($0)" } ?? lieu.nom
        etape.latitude = lieu.coordonnee.latitude
        etape.longitude = lieu.coordonnee.longitude
        etape.siteWeb = lieu.site
        if let jour {
            etape.ordre = prochainOrdre(du: jour)
            // Un hébergement va dans la nuit qui suit le jour.
            if lieu.categorie == .hebergement { placerEntreJours(etape, apres: jour) }
        } else {
            etape.ordre = (etapesSansJour.map(\.ordre).max() ?? -1) + 1
        }
        etape.voyage = self
        contexte.insert(etape)
        // iPhone, iPad : l'adresse complète, quand Plans la donne pour ce point (iOS 18).
        #if os(iOS)
        if #available(iOS 18.0, *), let feature = lieu.feature {
            Task {
                guard let item = try? await MKMapItemRequest(feature: feature).mapItem else { return }
                let complet = LieuCarte(item: item)
                if let adresse = complet.adresse, etape.lieu == lieu.nom { etape.lieu = "\(lieu.nom), \(adresse)" }
                if etape.siteWeb == nil { etape.siteWeb = complet.site }
            }
        }
        #endif
        return etape
    }
}

extension Color {
    /// Couleur sRGB à partir de valeurs de 0 à 255.
    init(rouge: Int, vert: Int, bleu: Int) {
        self.init(.sRGB, red: Double(rouge) / 255, green: Double(vert) / 255, blue: Double(bleu) / 255, opacity: 1)
    }
}

extension Voyage {
    /// Couleur de la nuit qui suit `jour` : menthe, puis orange une nuit sur deux, pour mieux distinguer les hôtels.
    func couleurNuit(apres jour: Date) -> Color {
        let rang = jours.firstIndex { Calendar.current.isDate($0, inSameDayAs: jour) } ?? 0
        return rang % 2 == 0 ? .mint : .orange
    }
}

/// Un rond de la couleur du jour avec le numéro en blanc, entouré d'une fourchette à gauche et d'un couteau à droite.
/// Sert sur la carte et dans la liste des jours de l'Itinéraire.
struct PionRepas: View {
    let numero: Int
    let couleur: Color
    let taille: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Fourchette().fill(couleur, outline: .white)
                .frame(width: taille * 0.4, height: taille * 1.05)
            Text("\(numero)")
                .font(.system(size: taille * 0.46, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: taille, height: taille)
                .background(couleur, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Couteau().fill(couleur, outline: .white)
                .frame(width: taille * 0.4, height: taille * 1.05)
        }
    }

    /// Fourchette : trois dents épaisses, une base arrondie et un manche.
    private struct Fourchette: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let dent = r.width * 0.2
            for i in 0..<3 {
                let x = r.minX + CGFloat(i) * (r.width - dent) / 2
                p.addRoundedRect(in: CGRect(x: x, y: r.minY, width: dent, height: r.height * 0.5),
                                 cornerSize: CGSize(width: dent / 2, height: dent / 2))
            }
            p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + r.height * 0.3, width: r.width, height: r.height * 0.26),
                             cornerSize: CGSize(width: r.width * 0.3, height: r.width * 0.3))
            p.addRoundedRect(in: CGRect(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.45, width: r.width * 0.24, height: r.height * 0.55),
                             cornerSize: CGSize(width: r.width * 0.12, height: r.width * 0.12))
            return p
        }
    }

    /// Couteau : une lame large au dos droit et au tranchant arrondi, puis un manche.
    private struct Couteau: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let dos = r.midX + r.width * 0.05
            p.move(to: CGPoint(x: dos, y: r.minY))
            p.addCurve(to: CGPoint(x: dos - r.width * 0.5, y: r.minY + r.height * 0.55),
                       control1: CGPoint(x: dos - r.width * 0.55, y: r.minY + r.height * 0.02),
                       control2: CGPoint(x: dos - r.width * 0.6, y: r.minY + r.height * 0.3))
            p.addLine(to: CGPoint(x: dos, y: r.minY + r.height * 0.55))
            p.closeSubpath()
            p.addRoundedRect(in: CGRect(x: dos - r.width * 0.12, y: r.minY + r.height * 0.5, width: r.width * 0.3, height: r.height * 0.5),
                             cornerSize: CGSize(width: r.width * 0.12, height: r.width * 0.12))
            return p
        }
    }
}

private extension Shape {
    /// Rempli d'une couleur et cerné d'un liseré, pour rester lisible sur la carte.
    func fill(_ couleur: Color, outline: Color) -> some View {
        ZStack {
            stroke(outline, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            fill(couleur)
        }
    }
}
