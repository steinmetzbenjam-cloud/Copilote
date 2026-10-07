import SwiftUI
import MapKit

/// La carte d'un voyage : étapes numérotées par jour, tracés, et lieux de référence des journées.
/// Utilisée telle quelle par l'onglet Carte et, en arrière-plan, par l'Itinéraire.
struct CarteDuVoyage: View {
    var voyage: Voyage
    /// Jour sur lequel la carte se cadre ; nil = tout le voyage.
    var jourFocus: Date?
    /// true : seules les étapes du jour sont dessinées ; false : les autres jours restent visibles, estompés.
    var masquerAutresJours = false
    /// Largeur recouverte à gauche par un panneau : la carte cadre le contenu dans la partie visible.
    var margeGauche: CGFloat = 0
    var onEtape: (Etape) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var regionPays: MKCoordinateRegion?

    /// Une couleur par jour, modernes et bien distinctes : indigo, corail, émeraude, ambre, violet, cyan, rose, ardoise.
    static let couleurs: [Color] = [
        Color(rouge: 0x5B, vert: 0x6C, bleu: 0xFF), Color(rouge: 0xFF, vert: 0x7A, bleu: 0x59),
        Color(rouge: 0x10, vert: 0xB9, bleu: 0x81), Color(rouge: 0xF5, vert: 0x9E, bleu: 0x0B),
        Color(rouge: 0x8B, vert: 0x5C, bleu: 0xF6), Color(rouge: 0x06, vert: 0xB6, bleu: 0xD4),
        Color(rouge: 0xEC, vert: 0x48, bleu: 0x99), Color(rouge: 0x64, vert: 0x74, bleu: 0x8B),
    ]
    static func couleur(du index: Int) -> Color { couleurs[index % couleurs.count] }

    private func estJourFocus(_ jour: Date) -> Bool {
        jourFocus.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? true
    }

    private var joursDessines: [(index: Int, jour: Date)] {
        voyage.jours.enumerated()
            .map { (index: $0.offset, jour: $0.element) }
            .filter { !masquerAutresJours || estJourFocus($0.jour) }
    }

    /// Tout ce qui est placé sur la carte pour un jour : étapes localisées et lieux de référence.
    private func points(du jour: Date?) -> [CLLocationCoordinate2D] {
        let jours = voyage.jours.filter { jour == nil || Calendar.current.isDate($0, inSameDayAs: jour!) }
        return jours.flatMap { j in
            voyage.etapes(du: j).compactMap(\.coordonnee) + (voyage.infos(du: j)?.lieux ?? []).map(\.coordonnee)
        }
    }

    private var lieuxPaysSeuls: [LieuReference] {
        let jours = voyage.jours.filter { estJourFocus($0) || jourFocus == nil }
        return jours.flatMap { voyage.infos(du: $0)?.lieux ?? [] }.filter(\.estPays)
    }

    /// Change quand il faut recadrer : jour choisi, points placés, taille de la carte.
    private struct Signature: Equatable {
        var jour: Date?
        var empreinte: Double
        var largeur: CGFloat
        var hauteur: CGFloat
        var pays: [String]
    }

    private func signature(_ taille: CGSize) -> Signature {
        let somme = points(du: nil).reduce(0.0) { $0 + $1.latitude * 3 + $1.longitude }
        return Signature(jour: jourFocus, empreinte: somme + Double(points(du: nil).count),
                         largeur: taille.width.rounded(), hauteur: taille.height.rounded(), pays: voyage.pays)
    }

    // MARK: Tracés entre étapes

    private struct Segment: Identifiable {
        let id: String
        let points: [CLLocationCoordinate2D]
        let tirets: [CGFloat]
        var avion = false
        /// Aller et retour : l'avion est plus grand.
        var grandAvion = false

        /// Milieu du trait et direction du vol (angle SwiftUI, en radians, pour un symbole tourné vers la droite).
        var milieuAvion: (coordonnee: CLLocationCoordinate2D, angle: Double)? {
            guard avion, points.count >= 3 else { return nil }
            let m = points.count / 2
            let avant = points[m - 1], apres = points[m + 1 < points.count ? m + 1 : m]
            let dx = (apres.longitude - avant.longitude) * cos(points[m].latitude * .pi / 180)
            let dy = apres.latitude - avant.latitude
            return (points[m], atan2(-dy, dx))
        }
    }

    /// Couples d'éléments consécutifs d'un jour, hébergement compris, avec le transport prévu entre eux.
    private var paires: [(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] {
        voyage.jours.flatMap { jour -> [(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] in
            liens(du: jour).compactMap { d, a in
                guard let mode = d.transport?.mode, let ca = d.coordonnee, let cb = a.coordonnee else { return nil }
                return (ca, cb, mode)
            }
        }
    }

    /// Chaque élément du jour avec sa suivante : les étapes, puis l'hébergement, puis la première étape du lendemain.
    private func liens(du jour: Date) -> [(Etape, Etape)] {
        let liste = voyage.etapes(du: jour) + (voyage.hebergements(apres: jour).first.map { [$0] } ?? [])
        var r = Array(zip(liste, liste.dropFirst()))
        if let h = voyage.hebergements(apres: jour).first, let suivante = voyage.suivante(de: h) { r.append((h, suivante)) }
        return r
    }

    /// Transport d'aller et de retour : un trait entre leur lieu de départ et leur lieu d'arrivée.
    /// Ces lieux n'entrent pas dans le cadrage : la carte ne s'élargit pas, on n'en voit que la partie proche du voyage.
    private var extremites: [(id: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] {
        var liste: [(id: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] = []
        if let t = voyage.transportAller, let depart = t.departCoordonnee, let arrivee = t.arriveeCoordonnee {
            liste.append(("aller", depart, arrivee, t.mode))
        }
        // Le retour n'est tracé que si le dernier jour a au moins une étape.
        if let t = voyage.transportRetour, let depart = t.departCoordonnee, let arrivee = t.arriveeCoordonnee,
           let dernierJour = voyage.jours.last, !voyage.etapes(du: dernierJour).isEmpty {
            liste.append(("retour", depart, arrivee, t.mode))
        }
        return liste
    }

    private var clesItineraires: String {
        (paires.map { ($0.a, $0.b, $0.mode) } + extremites.map { ($0.a, $0.b, $0.mode) })
            .filter { $0.2.aUnItineraire }.map { Itineraires.cle($0.0, $0.1, $0.2) }.joined(separator: ";")
    }

    /// Une ligne entre chaque étape localisée : arc pour l'avion, itinéraire pour la voiture, la marche et le vélo,
    /// pointillés pour les transports en commun, trait droit sans transport.
    private func segments(du jour: Date) -> [Segment] {
        let liste = voyage.etapes(du: jour)
        var resultat: [Segment] = []
        for (i, depart) in liste.enumerated() {
            guard let a = depart.coordonnee else { continue }
            // Prochaine étape localisée ; le transport ne compte que si c'est la suivante directe.
            guard let j = liste[(i + 1)...].firstIndex(where: { $0.coordonnee != nil }), let b = liste[j].coordonnee else { continue }
            let mode = j == i + 1 ? depart.transport?.mode : nil
            resultat.append(segment("\(depart.uid)-\(liste[j].uid)", a, b, mode))
        }
        // Liaisons avec l'hébergement : tracées seulement quand un transport est prévu.
        for (d, s) in liens(du: jour) where d.apresJour || s.apresJour {
            guard let mode = d.transport?.mode, let a = d.coordonnee, let b = s.coordonnee else { continue }
            resultat.append(segment("\(d.uid)-\(s.uid)", a, b, mode))
        }
        // L'aller se rattache au premier jour du voyage, le retour au dernier.
        for e in extremites {
            let jourCible = e.id == "aller" ? voyage.jours.first : voyage.jours.last
            if let jourCible, Calendar.current.isDate(jourCible, inSameDayAs: jour) {
                var trait = segment(e.id, e.a, e.b, e.mode)
                trait.grandAvion = true
                resultat.append(trait)
            }
        }
        return resultat
    }

    private func segment(_ id: String, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport?) -> Segment {
        switch mode {
        case .avion:
            return Segment(id: id, points: Itineraires.arc(a, b), tirets: [7, 6], avion: true)
        case .voiture, .pied, .velo:
            let trajet = Itineraires.shared.trajet(a, b, mode!)
            return Segment(id: id, points: trajet?.points ?? [a, b], tirets: mode == .voiture ? [] : [1, 6])
        case .commun:
            return Segment(id: id, points: [a, b], tirets: [10, 5])
        case nil:
            return Segment(id: id, points: [a, b], tirets: [])
        }
    }

    var body: some View {
        GeometryReader { geo in
            Map(position: $position) {
                ForEach(voyage.etapesSansJour.filter { $0.coordonnee != nil }) { etape in
                    Annotation(etape.titre, coordinate: etape.coordonnee!) {
                        Button { onEtape(etape) } label: {
                            Image(systemName: etape.categorie.symbole)
                                .font(.caption2).foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(.gray, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(joursDessines, id: \.jour) { index, jour in
                    let focus = estJourFocus(jour)
                    let attenue = jourFocus != nil && !focus
                    ForEach(voyage.infos(du: jour)?.lieux ?? []) { lieu in
                        Annotation(lieu.nom, coordinate: lieu.coordonnee) {
                            Image(systemName: lieu.estPays ? "flag.fill" : "scope")
                                .font(.caption)
                                .foregroundStyle(Self.couleur(du: index))
                                .padding(5)
                                .background(.background, in: Circle())
                                .overlay(Circle().stroke(Self.couleur(du: index), lineWidth: 1.5))
                                .opacity(attenue ? 0.35 : 1)
                        }
                    }
                    let etapes = voyage.etapes(du: jour).filter { $0.coordonnee != nil }
                    ForEach(voyage.hebergements(apres: jour).filter { $0.coordonnee != nil }) { h in
                        Annotation(h.titre, coordinate: h.coordonnee!) {
                            Button { onEtape(h) } label: {
                                Image(systemName: "bed.double.fill")
                                    .font(.caption2).foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(.mint, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2))
                                    .opacity(attenue ? 0.4 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    let traits = segments(du: jour)
                    ForEach(traits) { s in
                        MapPolyline(coordinates: s.points)
                            .stroke(Self.couleur(du: index).opacity(attenue ? 0.2 : 0.65),
                                    style: StrokeStyle(lineWidth: focus && jourFocus != nil ? 4 : 3, lineCap: .round, dash: s.tirets))
                    }
                    ForEach(traits.filter(\.avion)) { s in
                        if let milieu = s.milieuAvion {
                            Annotation("", coordinate: milieu.coordonnee, anchor: .center) {
                                Image(systemName: "airplane")
                                    .font(.system(size: s.grandAvion ? 32 : 17, weight: .semibold))
                                    .foregroundStyle(Self.couleur(du: index))
                                    .rotationEffect(.radians(milieu.angle))
                                    .shadow(color: .white, radius: 2)
                                    .opacity(attenue ? 0.35 : 1)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    ForEach(Array(etapes.enumerated()), id: \.element.id) { rang, etape in
                        Annotation(etape.titre, coordinate: etape.coordonnee!) {
                            Button { onEtape(etape) } label: {
                                Text("\(rang + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: focus && jourFocus != nil ? 30 : 26, height: focus && jourFocus != nil ? 30 : 26)
                                    .background(Self.couleur(du: index), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .opacity(attenue ? 0.4 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .task(id: clesItineraires) {
                for p in paires where p.mode.aUnItineraire {
                    await Itineraires.shared.charger(p.a, p.b, p.mode)
                }
                for p in extremites where p.mode.aUnItineraire {
                    await Itineraires.shared.charger(p.a, p.b, p.mode)
                }
            }
            .task(id: signature(geo.size)) {
                await recadrer(taille: geo.size)
            }
        }
    }

    // MARK: Cadrage

    private func recadrer(taille: CGSize) async {
        guard taille.width > 50, taille.height > 50 else { return }
        var rectangle: MKMapRect?

        func ajouter(_ r: MKMapRect) { rectangle = rectangle.map { $0.union(r) } ?? r }

        let pts = points(du: jourFocus)
        for p in pts {
            let m = MKMapPoint(p)
            ajouter(MKMapRect(origin: m, size: MKMapSize(width: 0, height: 0)))
        }
        // Un jour qui ne contient qu'un pays : on cadre le pays entier.
        if pts.count == lieuxPaysSeuls.count || pts.isEmpty {
            let codes = lieuxPaysSeuls.compactMap(\.codePays) + (pts.isEmpty && jourFocus == nil ? voyage.pays : [])
            for code in Set(codes) { if let region = await Pays.region(de: code) { ajouter(Self.rectangle(region)) } }
        }
        if rectangle == nil, jourFocus == nil, let region = await Pays.regionCarte(pour: voyage.pays) {
            ajouter(Self.rectangle(region))
        }
        guard var contenu = rectangle else { return }

        // Marge autour du contenu, et taille minimale (environ 3 km) pour un point isolé.
        let metres = MKMapPointsPerMeterAtLatitude(MKMapPoint(x: contenu.midX, y: contenu.midY).coordinate.latitude)
        let minimum = 4_000 * metres
        if contenu.width < minimum { contenu = contenu.insetBy(dx: (contenu.width - minimum) / 2, dy: 0) }
        if contenu.height < minimum { contenu = contenu.insetBy(dx: 0, dy: (contenu.height - minimum) / 2) }
        contenu = contenu.insetBy(dx: -contenu.width * 0.5, dy: -contenu.height * 0.5)

        // Échelle (points de carte par point d'écran) pour que le contenu tienne dans la partie visible.
        let visible = max(taille.width - margeGauche, taille.width * 0.4)
        let echelle = max(contenu.width / visible, contenu.height / taille.height)
        let centreEcranX = (taille.width - visible) + visible / 2
        let cadre = MKMapRect(x: contenu.midX - echelle * centreEcranX, y: contenu.midY - echelle * taille.height / 2,
                              width: echelle * taille.width, height: echelle * taille.height)
        withAnimation(.easeInOut(duration: 0.6)) { position = .rect(cadre) }
    }

    private static func rectangle(_ region: MKCoordinateRegion) -> MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

extension Color {
    /// Couleur sRGB à partir de valeurs de 0 à 255.
    init(rouge: Int, vert: Int, bleu: Int) {
        self.init(.sRGB, red: Double(rouge) / 255, green: Double(vert) / 255, blue: Double(bleu) / 255, opacity: 1)
    }
}
