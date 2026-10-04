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

    static let couleurs: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .pink, .brown]
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
    }

    /// Couples d'étapes consécutives d'un jour, avec le transport prévu entre elles.
    private var paires: [(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] {
        voyage.jours.flatMap { jour -> [(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] in
            let liste = voyage.etapes(du: jour)
            return zip(liste, liste.dropFirst()).compactMap { d, a in
                guard let mode = d.transport?.mode, let ca = d.coordonnee, let cb = a.coordonnee else { return nil }
                return (ca, cb, mode)
            }
        }
    }

    private var clesItineraires: String {
        paires.filter { $0.mode.aUnItineraire }.map { Itineraires.cle($0.a, $0.b, $0.mode) }.joined(separator: ";")
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
            let id = "\(depart.uid)-\(liste[j].uid)"
            switch mode {
            case .avion:
                resultat.append(Segment(id: id, points: Itineraires.arc(a, b), tirets: [7, 6]))
            case .voiture, .pied, .velo:
                let trajet = Itineraires.shared.trajet(a, b, mode!)
                resultat.append(Segment(id: id, points: trajet?.points ?? [a, b], tirets: mode == .voiture ? [] : [1, 6]))
            case .commun:
                resultat.append(Segment(id: id, points: [a, b], tirets: [10, 5]))
            case nil:
                resultat.append(Segment(id: id, points: [a, b], tirets: []))
            }
        }
        return resultat
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
                    ForEach(segments(du: jour)) { s in
                        MapPolyline(coordinates: s.points)
                            .stroke(Self.couleur(du: index).opacity(attenue ? 0.2 : 0.65),
                                    style: StrokeStyle(lineWidth: focus && jourFocus != nil ? 4 : 3, lineCap: .round, dash: s.tirets))
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
