import SwiftUI
import MapKit
import SwiftData

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
    /// Étape dont le détail est ouvert : la carte zoome sur son lieu et grossit son repère.
    var etapeFocus: Etape? = nil
    /// Reçoit un point d'intérêt de la carte (restaurant, musée, plage…) choisi pour devenir une étape ; nil : points non sélectionnables.
    var onLieu: ((LieuCarte) -> Void)? = nil
    var onEtape: (Etape) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var regionPays: MKCoordinateRegion?
    /// Point d'intérêt de la carte touché : une petite fiche propose d'en faire une étape.
    @State private var lieuChoisi: LieuCarte?
    /// Fond de carte choisi (plan, satellite, mixte), retenu d'une ouverture à l'autre et commun aux deux cartes.
    @AppStorage("fondDeCarte") private var fond = FondCarte.plan
    #if os(iOS)
    /// iPhone, iPad : le point d'intérêt sélectionné par Plans lui-même.
    @State private var pointSelectionne: MapFeature?
    #endif

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
                + (jour == nil ? [] : hotelsAutour(de: j).compactMap(\.coordonnee))
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
        var etape: String?
        var latitude: Double?
        var longitude: Double?
    }

    private func estEtapeFocus(_ etape: Etape) -> Bool { etapeFocus === etape }

    private func signature(_ taille: CGSize) -> Signature {
        let somme = points(du: nil).reduce(0.0) { $0 + $1.latitude * 3 + $1.longitude }
        return Signature(jour: jourFocus, empreinte: somme + Double(points(du: nil).count),
                         largeur: taille.width.rounded(), hauteur: taille.height.rounded(), pays: voyage.pays,
                         etape: etapeFocus?.uid, latitude: etapeFocus?.latitude, longitude: etapeFocus?.longitude)
    }

    // MARK: Tracés entre étapes

    private struct Segment: Identifiable {
        let id: String
        let points: [CLLocationCoordinate2D]
        let tirets: [CGFloat]
        var avion = false
        /// Couleur propre au trait (ligne de métro, par exemple) ; sinon celle du jour.
        var couleur: Color?
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
            (liens(du: jour) + departDeLaVeille(pour: jour)).compactMap { d, a in
                guard let mode = d.transport?.mode, let ca = d.coordonnee, let cb = a.coordonnee else { return nil }
                return (ca, cb, mode)
            }
        }
    }

    /// Chaque élément du jour avec sa suivante : les étapes, puis l'hébergement, puis la première étape du lendemain.
    private func liens(du jour: Date) -> [(Etape, Etape)] {
        let liste = voyage.etapes(du: jour) + (voyage.hebergements(apres: jour).first.map { [$0] } ?? [])
        var r = Array(zip(liste, liste.dropFirst()))
        // Le transport après l'hôtel appartient au jour suivant (voir `departDeLaVeille`).
        if voyage.hebergements(apres: jour).isEmpty, let (depart, arrivee) = voyage.transportDeNuit(apres: jour) { r.append((depart, arrivee)) }
        return r
    }

    /// L'hôtel de la nuit juste avant le jour sélectionné : toujours bien visible, même dessiné avec la veille.
    private func precedeLeFocus(_ h: Etape) -> Bool {
        guard let focus = jourFocus, let j = h.jour, h.apresJour else { return false }
        return Calendar.current.date(byAdding: .day, value: 1, to: j).map { Calendar.current.isDate($0, inSameDayAs: focus) } ?? false
    }

    /// Les hôtels de la nuit d'avant et de la nuit d'après un jour : le cadrage les inclut toujours.
    private func hotelsAutour(de jour: Date) -> [Etape] {
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: jour) ?? jour
        return voyage.hebergements(apres: veille) + voyage.hebergements(apres: jour)
    }

    /// Hôtels visibles pour un jour : celui de la nuit qui suit, et celui de la veille quand le jour d'avant n'est pas dessiné.
    private func hebergementsAffiches(pour jour: Date) -> [Etape] {
        let cal = Calendar.current
        let veille = cal.date(byAdding: .day, value: -1, to: jour) ?? jour
        let veilleDessinee = joursDessines.contains { cal.isDate($0.jour, inSameDayAs: veille) }
        let avant = veilleDessinee ? [] : voyage.hebergements(apres: veille)
        return (avant + voyage.hebergements(apres: jour)).filter { $0.coordonnee != nil }
    }

    /// Hôtel de la veille vers la première étape de ce jour : ce trajet ouvre la journée.
    private func departDeLaVeille(pour jour: Date) -> [(Etape, Etape)] {
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: jour) ?? jour
        guard let h = voyage.hebergements(apres: veille).first, let premiere = voyage.suivante(de: h) else { return [] }
        return [(h, premiere)]
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
            resultat += segment("\(depart.uid)-\(liste[j].uid)", a, b, mode, transport: j == i + 1 ? depart.transport : nil)
        }
        // Liaisons avec l'hébergement : tracées seulement quand un transport est prévu.
        for (d, s) in liens(du: jour) + departDeLaVeille(pour: jour) where d.apresJour || s.apresJour || !Calendar.current.isDate(d.jour ?? jour, inSameDayAs: s.jour ?? jour) {
            guard let mode = d.transport?.mode, let a = d.coordonnee, let b = s.coordonnee else { continue }
            resultat += segment("\(d.uid)-\(s.uid)", a, b, mode, transport: d.transport)
        }
        // L'aller se rattache au premier jour du voyage, le retour au dernier.
        for e in extremites {
            let jourCible = e.id == "aller" ? voyage.jours.first : voyage.jours.last
            if let jourCible, Calendar.current.isDate(jourCible, inSameDayAs: jour) {
                let t = e.id == "aller" ? voyage.transportAller : voyage.transportRetour
                resultat += segment(e.id, e.a, e.b, e.mode, transport: t).map { var trait = $0; trait.grandAvion = true; return trait }
            }
        }
        return resultat
    }

    private func segment(_ id: String, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ mode: ModeTransport?, transport: Transport? = nil) -> [Segment] {
        switch mode {
        case .avion:
            return [Segment(id: id, points: Itineraires.arc(a, b), tirets: [7, 6], avion: true)]
        case .voiture, .pied, .velo:
            let trajet = Itineraires.shared.trajet(a, b, mode!)
            return [Segment(id: id, points: trajet?.points ?? [a, b], tirets: mode == .voiture ? [] : [1, 6])]
        case .commun:
            // Itinéraire enregistré : un trait par tronçon, à la couleur de la ligne (marche en pointillés).
            if let it = transport?.itineraireCommun, !it.etapes.isEmpty {
                return it.etapes.enumerated().compactMap { i, e in
                    let points = PolylineGoogle.decoder(e.trace)
                    guard points.count >= 2 else { return nil }
                    var s = Segment(id: "\(id)-\(i)", points: points, tirets: e.estMarche ? [1, 6] : [])
                    s.couleur = e.estMarche ? nil : e.teinte
                    return s
                }
            }
            return [Segment(id: id, points: [a, b], tirets: [10, 5])]
        case nil:
            return [Segment(id: id, points: [a, b], tirets: [])]
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Lu ici pour que la carte soit redessinée dès qu'un itinéraire arrive (le contenu de la carte n'est pas observé seul).
            let _ = Itineraires.shared.trajets.count
            MapReader { proxy in
                carte(proxy)
                    .mapStyle(fond.style)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    // Le choix du fond de carte, en haut à gauche de la partie visible de la carte.
                    .overlay(alignment: .topLeading) {
                        choixDuFond
                            .padding(.leading, margeGauche)
                            .padding(12)
                    }
                    .overlay(alignment: .bottom) {
                        if let lieu = lieuChoisi, let onLieu {
                            ficheLieu(lieu, onLieu: onLieu)
                                // Dans la partie de la carte que le panneau de gauche ne recouvre pas.
                                .padding(.leading, margeGauche)
                                .padding(14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: lieuChoisi?.id)
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
    }

    @ViewBuilder private func carte(_ proxy: MapProxy) -> some View {
        #if os(iOS)
        Map(position: $position, selection: $pointSelectionne) { contenu }
            .mapFeatureSelectionDisabled { _ in onLieu == nil }
            .onChange(of: pointSelectionne) { _, f in lieuChoisi = f.map(LieuCarte.init(feature:)) }
        #else
        // Sur Mac, Plans ne laisse pas choisir ses points d'intérêt : on cherche le plus proche de l'endroit cliqué.
        Map(position: $position) { contenu }
            .onTapGesture { point in
                guard onLieu != nil, let c = proxy.convert(point, from: .local) else { return }
                let voisin = proxy.convert(CGPoint(x: point.x + 24, y: point.y), from: .local)
                let rayon = voisin.map { CLLocation(latitude: c.latitude, longitude: c.longitude)
                    .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) } ?? 50
                Task { lieuChoisi = await LieuCarte.plusProche(de: c, rayon: max(rayon, 25)) }
            }
        #endif
    }

    @MapContentBuilder private var contenu: some MapContent {
        ForEach(voyage.etapesSansJour.filter { $0.coordonnee != nil }) { etape in
            Annotation(etape.titre, coordinate: etape.coordonnee!) {
                Button { onEtape(etape) } label: {
                    Image(systemName: etape.categorie.symbole)
                        .font(.caption2).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.gray, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .scaleEffect(estEtapeFocus(etape) ? 1.4 : 1)
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
            ForEach(hebergementsAffiches(pour: jour)) { h in
                Annotation(h.titre, coordinate: h.coordonnee!) {
                    Button { onEtape(h) } label: {
                        Image(systemName: "bed.double.fill")
                            .font(.caption2).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(voyage.couleurNuit(apres: h.jour ?? jour), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2))
                            .opacity(attenue && !precedeLeFocus(h) && !estEtapeFocus(h) ? 0.4 : 1)
                            .scaleEffect(estEtapeFocus(h) ? 1.4 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            let traits = segments(du: jour)
            ForEach(traits) { s in
                MapPolyline(coordinates: s.points)
                    .stroke((s.couleur ?? Self.couleur(du: index)).opacity(attenue ? 0.2 : (s.couleur == nil ? 0.65 : 0.9)),
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
                        let taille: CGFloat = focus && jourFocus != nil ? 30 : 26
                        Group {
                            if etape.categorie == .repas {
                                // Un repas : une assiette ronde avec le numéro au milieu, une fourchette et un couteau de chaque côté.
                                PionRepas(numero: rang + 1, couleur: Self.couleur(du: index), taille: taille)
                            } else if etape.categorie == .hebergement {
                                // Un hébergement parmi les étapes du jour : le lit, comme pour les nuits, avec son numéro.
                                Image(systemName: "bed.double.fill")
                                    .font(.system(size: taille * 0.42)).foregroundStyle(.white)
                                    .frame(width: taille, height: taille)
                                    .background(Self.couleur(du: index), in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2))
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(rang + 1)")
                                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Self.couleur(du: index))
                                            .frame(minWidth: 15, minHeight: 15)
                                            .background(.white, in: Circle())
                                            .overlay(Circle().stroke(Self.couleur(du: index), lineWidth: 1.5))
                                            .offset(x: 6, y: -6)
                                    }
                            } else {
                                Text("\(rang + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: taille, height: taille)
                                    .background(Self.couleur(du: index), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                            .opacity(attenue && !estEtapeFocus(etape) ? 0.4 : 1)
                            .scaleEffect(estEtapeFocus(etape) ? 1.4 : 1)
                            .shadow(color: .black.opacity(estEtapeFocus(etape) ? 0.35 : 0), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Fond de carte

    private var choixDuFond: some View {
        Menu {
            Picker("Fond de carte", selection: $fond) {
                ForEach(FondCarte.allCases) { f in
                    Label(f.libelle, systemImage: f.symbole).tag(f)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: fond.symbole)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Fond de carte : \(fond.libelle)")
        .help("Fond de carte : plan, satellite ou mixte")
    }

    // MARK: Point d'intérêt

    private func ficheLieu(_ lieu: LieuCarte, onLieu: @escaping (LieuCarte) -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: lieu.categorie.symbole)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(lieu.nom).font(.headline).lineLimit(2)
                Text(lieu.categorie.libelle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Créer une étape", systemImage: "plus.circle.fill") {
                onLieu(lieu)
                fermerFiche()
            }
            .buttonStyle(.borderedProminent)
            Button { fermerFiche() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28).background(Circle().fill(Color.secondary.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(12)
        .frame(maxWidth: 460)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private func fermerFiche() {
        lieuChoisi = nil
        #if os(iOS)
        pointSelectionne = nil
        #endif
    }

    // MARK: Cadrage

    private func recadrer(taille: CGSize) async {
        guard taille.width > 50, taille.height > 50 else { return }
        // Détail d'une étape ouvert : un cadre serré (environ 1,5 km) centré sur son lieu.
        if let coord = etapeFocus?.coordonnee {
            let centre = MKMapPoint(coord)
            let cote = 1_500 * MKMapPointsPerMeterAtLatitude(coord.latitude)
            cadrer(MKMapRect(x: centre.x - cote / 2, y: centre.y - cote / 2, width: cote, height: cote), taille: taille)
            return
        }
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
        cadrer(contenu, taille: taille)
    }

    /// Place `contenu` au centre de la partie de la carte que le panneau de gauche ne recouvre pas.
    private func cadrer(_ contenu: MKMapRect, taille: CGSize) {
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

/// Les fonds de carte proposés par Plans.
enum FondCarte: String, CaseIterable, Identifiable {
    case plan, satellite, mixte, relief
    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .plan: "Plan"
        case .satellite: "Satellite"
        case .mixte: "Satellite avec noms"
        case .relief: "Plan en relief"
        }
    }

    var symbole: String {
        switch self {
        case .plan: "map"
        case .satellite: "globe.europe.africa.fill"
        case .mixte: "square.2.layers.3d"
        case .relief: "mountain.2"
        }
    }

    var style: MapStyle {
        switch self {
        case .plan: .standard
        case .satellite: .imagery(elevation: .realistic)
        case .mixte: .hybrid(elevation: .realistic)
        case .relief: .standard(elevation: .realistic, emphasis: .muted)
        }
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
