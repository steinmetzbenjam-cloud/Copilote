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
    /// Vrai pendant qu'on tire la poignée entre la carte et la liste : la carte ne se recadre qu'une fois la poignée lâchée.
    var cadrageFige = false
    /// Étape dont le détail est ouvert : la carte zoome sur son lieu et grossit son repère.
    var etapeFocus: Etape? = nil
    /// Reçoit un point d'intérêt de la carte (restaurant, musée, plage…) choisi pour devenir une étape ; nil : points non sélectionnables.
    var onLieu: ((LieuCarte) -> Void)? = nil
    /// Fiche d'une étape ouverte : un point d'intérêt touché peut aussi devenir une de ses sous-étapes (nom de l'étape, et l'ajout).
    var ajoutSousEtape: (nom: String, ajouter: (LieuCarte) -> Void)? = nil
    var onEtape: (Etape) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var regionPays: MKCoordinateRegion?
    /// Ce sur quoi la carte s'est cadrée la dernière fois : à la fermeture du détail d'une étape, on ne recadre pas.
    @State private var dernierCadrage: Signature?
    /// Point d'intérêt de la carte touché : une petite fiche propose d'en faire une étape.
    @State private var lieuChoisi: LieuCarte?
    /// Étapes (uid) dont les sous-étapes sont affichées : on touche l'étape pour les montrer, puis à nouveau pour les cacher.
    @State private var deplies: Set<String> = []
    /// Fond de carte choisi (plan, satellite, mixte), retenu d'une ouverture à l'autre et commun aux deux cartes.
    @AppStorage("fondDeCarte") private var fond = FondCarte.plan
    /// Fond « Transports » : la zone affichée et les stations qu'on y a trouvées.
    @State private var regionVisible: MKCoordinateRegion?
    @State private var stations: [StationCarte] = []
    /// Mode voyage : ma position affichée sur la carte (bouton « Ma position »), et l'alerte quand elle n'est pas autorisée.
    @State private var maPosition = false
    @State private var positionRefusee = false
    @Environment(\.openURL) private var ouvrirURL
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
        var marge: CGFloat
        var fige: Bool
        var pays: [String]
        var etape: String?
        var latitude: Double?
        var longitude: Double?
        /// Nombre de points des tracés du jour : un itinéraire qui arrive peut agrandir le cadre.
        var traces: Int
        /// Sous-étapes localisées de l'étape ouverte : le cadre les englobe.
        var sousEtapes: Int
    }

    private func estEtapeFocus(_ etape: Etape) -> Bool { etapeFocus === etape }

    private func signature(_ taille: CGSize) -> Signature {
        let somme = points(du: nil).reduce(0.0) { $0 + $1.latitude * 3 + $1.longitude }
        // Poignée tirée : la taille n'entre pas dans la signature, pour ne pas recadrer à chaque déplacement du doigt.
        return Signature(jour: jourFocus, empreinte: somme + Double(points(du: nil).count),
                         largeur: cadrageFige ? 0 : taille.width.rounded(), hauteur: cadrageFige ? 0 : taille.height.rounded(),
                         marge: cadrageFige ? 0 : margeGauche.rounded(), fige: cadrageFige, pays: voyage.pays,
                         etape: etapeFocus?.uid, latitude: etapeFocus?.latitude, longitude: etapeFocus?.longitude,
                         traces: tracesDuFocus.count, sousEtapes: etapeFocus?.sousEtapes.filter { $0.coordonnee != nil }.count ?? 0)
    }

    /// Les points des transports du jour choisi (aller et retour exceptés) : le cadrage les fait tenir dans la carte.
    private var tracesDuFocus: [CLLocationCoordinate2D] {
        guard let jourFocus else { return [] }
        return segments(du: jourFocus, avecExtremites: false).flatMap(\.points)
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

    /// Couples d'éléments consécutifs d'un jour, hébergement compris, avec le transport prévu entre eux ; puis ceux des sous-étapes.
    private var paires: [(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, mode: ModeTransport)] {
        let parSousEtapes = Dictionary(grouping: voyage.etapes.filter { $0.parentUID != nil }, by: { $0.parentUID ?? "" })
            .values.map { $0.sorted { ($0.ordre, $0.creeLe) < ($1.ordre, $1.creeLe) } }
        return (voyage.jours.flatMap { jour in liens(du: jour) + departDeLaVeille(pour: jour) }
                + parSousEtapes.flatMap { Array(zip($0, $0.dropFirst())) })
            .compactMap { d, a in
                guard let mode = d.transport?.mode, let ca = d.coordonnee, let cb = a.coordonnee else { return nil }
                return (ca, cb, mode)
            }
    }

    /// Chaque élément du jour avec sa suivante : les étapes, puis l'hébergement visé par la dernière (la nuit peut en avoir plusieurs).
    private func liens(du jour: Date) -> [(Etape, Etape)] {
        let etapes = voyage.etapes(du: jour)
        var r = Array(zip(etapes, etapes.dropFirst()))
        if let derniere = etapes.last, let h = voyage.hebergementVise(depuis: derniere, apres: jour) { r.append((derniere, h)) }
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

    /// Chaque hôtel de la veille vers la première étape de ce jour : ces trajets ouvrent la journée.
    private func departDeLaVeille(pour jour: Date) -> [(Etape, Etape)] {
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: jour) ?? jour
        return voyage.hebergements(apres: veille).compactMap { h in voyage.suivante(de: h).map { (h, $0) } }
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
    private func segments(du jour: Date, avecExtremites: Bool = true) -> [Segment] {
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
        for e in extremites where avecExtremites {
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
            let trajet = transport?.itineraireGoogle(a, b)?.trajet ?? Itineraires.shared.trajet(a, b, mode!)
            return [Segment(id: id, points: trajet?.points ?? [a, b], tirets: mode == .voiture ? [] : [1, 6])]
        case .bateau:
            // Route par la mer, le long des côtes ; tant qu'elle n'est pas calculée, une ligne droite.
            return [Segment(id: id, points: Itineraires.shared.trajet(a, b, .bateau)?.points ?? [a, b], tirets: [6, 4])]
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
                // Vue d'ensemble : les repères se superposent ; un jour choisi : les siens qui se chevauchent se rangent côte à côte.
                carte(proxy, ecarts: ecartsDesReperes(taille: geo.size))
                    .mapStyle(fond.style)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    // Le choix du fond de carte, en haut à gauche de la partie visible de la carte.
                    .overlay(alignment: .topLeading) {
                        VStack(spacing: 10) {
                            choixDuFond
                            if fond == .transports { boutonPlansTransports }
                            if voyage.mode == .voyage { boutonMaPosition }
                        }
                        .padding(.leading, margeGauche)
                        .padding(12)
                    }
                    .onMapCameraChange(frequency: .onEnd) { regionVisible = $0.region }
                    .task(id: CleStations(fond: fond, region: regionVisible)) {
                        await chercherStations()
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
                    // Fiche d'une étape à sous-étapes (ou d'une sous-étape) ouverte : ses sous-étapes s'affichent.
                    // (Aussi quand la fiche ouverte reçoit sa première sous-étape.)
                    .onChange(of: cleDepliage, initial: true) {
                        if let focus = etapeFocus {
                            let parente = focus.etapeParente ?? focus
                            if parente.aDesSousEtapes { deplies.insert(parente.uid) }
                        }
                    }
                    .task(id: signature(geo.size)) {
                        let nouvelle = signature(geo.size)
                        if nouvelle.fige { return }
                        defer { dernierCadrage = nouvelle }
                        // Détail d'une étape refermé, sur le même jour : la carte garde le zoom où elle est.
                        if let avant = dernierCadrage, avant.etape != nil, nouvelle.etape == nil, avant.jour == nouvelle.jour { return }
                        await recadrer(taille: geo.size)
                    }
            }
        }
    }

    @ViewBuilder private func carte(_ proxy: MapProxy, ecarts: [String: CGSize]) -> some View {
        #if os(iOS)
        Map(position: $position, selection: $pointSelectionne) { contenu(ecarts) }
            .mapFeatureSelectionDisabled { _ in onLieu == nil }
            .onChange(of: pointSelectionne) { _, f in lieuChoisi = f.map(LieuCarte.init(feature:)) }
        #else
        // Sur Mac, Plans ne laisse pas choisir ses points d'intérêt : on cherche le plus proche de l'endroit cliqué.
        Map(position: $position) { contenu(ecarts) }
            .onTapGesture { point in
                guard onLieu != nil, let c = proxy.convert(point, from: .local) else { return }
                let voisin = proxy.convert(CGPoint(x: point.x + 24, y: point.y), from: .local)
                let rayon = voisin.map { CLLocation(latitude: c.latitude, longitude: c.longitude)
                    .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) } ?? 50
                Task { lieuChoisi = await LieuCarte.plusProche(de: c, rayon: max(rayon, 25)) }
            }
        #endif
    }

    /// `ecarts` : décalage à l'écran des repères qui se chevauchent (voir `ecartsDesReperes`).
    @MapContentBuilder private func contenu(_ ecarts: [String: CGSize]) -> some MapContent {
        if maPosition { UserAnnotation() }
        if fond == .transports {
            ForEach(stations) { station in
                Annotation(station.nom, coordinate: station.coordonnee) {
                    Image(systemName: station.symbole)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(rouge: 0x00, vert: 0x7A, bleu: 0xC2), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5))
                }
            }
        }
        ForEach(voyage.etapesSansJour.filter { $0.coordonnee != nil }) { etape in
            Annotation(etape.titre, coordinate: etape.coordonnee!) {
                Button { toucher(etape) } label: {
                    Image(systemName: etape.categorie.symbole)
                        .font(.caption2).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.gray, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay(alignment: .bottomTrailing) { badgeSousEtapes(etape, couleur: .gray) }
                        .scaleEffect(estEtapeFocus(etape) ? 1.4 : 1)
                }
                .buttonStyle(.plain)
                .contextMenu { menuEtape(etape) }
                .offset(ecarts["e-\(etape.uid)"] ?? .zero)
            }
        }
        ForEach(voyage.etapesSansJour.filter { deplies.contains($0.uid) }) { etape in
            sousEtapesDessinees(de: etape, couleur: .gray, attenue: false)
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
                        .offset(ecarts["l-\(index)-\(lieu.id)"] ?? .zero)
                }
            }
            let etapes = voyage.etapes(du: jour).filter { $0.coordonnee != nil }
            ForEach(hebergementsAffiches(pour: jour)) { h in
                Annotation(h.titre, coordinate: h.coordonnee!) {
                    Button { toucher(h) } label: {
                        Image(systemName: "bed.double.fill")
                            .font(.caption2).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(voyage.couleurNuit(apres: h.jour ?? jour), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) { badgeSousEtapes(h, couleur: voyage.couleurNuit(apres: h.jour ?? jour)) }
                            .opacity(attenue && !precedeLeFocus(h) && !estEtapeFocus(h) ? 0.4 : 1)
                            .scaleEffect(estEtapeFocus(h) ? 1.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuEtape(h) }
                    .offset(ecarts["h-\(h.uid)"] ?? .zero)
                }
            }
            ForEach(hebergementsAffiches(pour: jour).filter { deplies.contains($0.uid) }) { h in
                sousEtapesDessinees(de: h, couleur: voyage.couleurNuit(apres: h.jour ?? jour), attenue: attenue)
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
            ForEach(voyage.etapes(du: jour).filter { deplies.contains($0.uid) }) { etape in
                sousEtapesDessinees(de: etape, couleur: Self.couleur(du: index), attenue: attenue && !estEtapeFocus(etape))
            }
            ForEach(Array(etapes.enumerated()), id: \.element.id) { rang, etape in
                Annotation(etape.titre, coordinate: etape.coordonnee!) {
                    Button { toucher(etape) } label: {
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
                            .overlay(alignment: .bottomTrailing) { badgeSousEtapes(etape, couleur: Self.couleur(du: index)) }
                            .opacity(attenue && !estEtapeFocus(etape) ? 0.4 : 1)
                            .scaleEffect(estEtapeFocus(etape) ? 1.4 : 1)
                            .shadow(color: .black.opacity(estEtapeFocus(etape) ? 0.35 : 0), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menuEtape(etape) }
                    .offset(ecarts["e-\(etape.uid)"] ?? .zero)
                }
            }
        }
    }

    // MARK: Sous-étapes

    /// Une étape qui a des sous-étapes : la toucher les montre ou les cache ; les autres ouvrent leur fiche.
    /// L'étape ouverte et le nombre de sous-étapes de son étape : quand l'un change, ses sous-étapes s'affichent.
    private var cleDepliage: String {
        guard let focus = etapeFocus else { return "" }
        return "\(focus.uid)#\((focus.etapeParente ?? focus).sousEtapes.count)"
    }

    private func toucher(_ etape: Etape) {
        guard etape.aDesSousEtapes else { onEtape(etape); return }
        withAnimation(.snappy) {
            if deplies.contains(etape.uid) { deplies.remove(etape.uid) } else { deplies.insert(etape.uid) }
        }
    }

    /// Un appui long sur une étape à sous-étapes ouvre quand même sa fiche.
    @ViewBuilder private func menuEtape(_ etape: Etape) -> some View {
        if etape.aDesSousEtapes {
            Button("Ouvrir la fiche", systemImage: "doc.text") { onEtape(etape) }
            Button(deplies.contains(etape.uid) ? "Cacher les sous-étapes" : "Montrer les sous-étapes",
                   systemImage: "point.3.connected.trianglepath.dotted") { toucher(etape) }
        }
    }

    /// Le signe d'une étape à sous-étapes, en bas à droite de son repère : plein quand elles sont cachées, inversé quand elles sont affichées.
    @ViewBuilder private func badgeSousEtapes(_ etape: Etape, couleur: Color) -> some View {
        if etape.aDesSousEtapes {
            let ouvert = deplies.contains(etape.uid)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ouvert ? Color.mint : .white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(ouvert ? Color.white : Color.mint))
                .overlay(Circle().stroke(ouvert ? Color.mint : .white, lineWidth: 1.5))
                .offset(x: 7, y: 7)
                .accessibilityLabel(ouvert ? "Sous-étapes affichées" : "Contient des sous-étapes")
        }
    }

    /// Les sous-étapes d'une étape dépliée : de petits repères numérotés, reliés par leurs transports (ou un trait fin).
    @MapContentBuilder private func sousEtapesDessinees(de parent: Etape, couleur: Color, attenue: Bool) -> some MapContent {
        let sous = parent.sousEtapes
        let placees = sous.enumerated().filter { $0.element.coordonnee != nil }.map { (rang: $0.offset + 1, etape: $0.element) }
        // Un fil discret de l'étape à sa première sous-étape.
        if let a = parent.coordonnee, let premiere = placees.first?.etape.coordonnee {
            MapPolyline(coordinates: [a, premiere])
                .stroke(couleur.opacity(attenue ? 0.15 : 0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
        }
        ForEach(segmentsSousEtapes(sous)) { s in
            MapPolyline(coordinates: s.points)
                .stroke((s.couleur ?? couleur).opacity(attenue ? 0.2 : 0.8),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: s.tirets))
        }
        ForEach(placees, id: \.etape.id) { rang, s in
            Annotation(s.titre, coordinate: s.coordonnee!) {
                Button { onEtape(s) } label: {
                    Text("\(rang)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(couleur)
                        .frame(width: 20, height: 20)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(couleur, lineWidth: 2))
                        .opacity(attenue && !estEtapeFocus(s) ? 0.4 : 1)
                        .scaleEffect(estEtapeFocus(s) ? 1.4 : 1)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sous-étape \(rang) : \(s.titre)")
            }
        }
    }

    /// Les traits entre sous-étapes localisées consécutives, selon le transport prévu (trait droit sans transport).
    private func segmentsSousEtapes(_ sous: [Etape]) -> [Segment] {
        var resultat: [Segment] = []
        for (i, depart) in sous.enumerated() {
            guard let a = depart.coordonnee,
                  let j = sous[(i + 1)...].firstIndex(where: { $0.coordonnee != nil }), let b = sous[j].coordonnee else { continue }
            let transport = j == i + 1 ? depart.transport : nil
            resultat += segment("s-\(depart.uid)-\(sous[j].uid)", a, b, transport?.mode, transport: transport)
        }
        return resultat
    }

    // MARK: Repères superposés

    /// Les repères du jour choisi (ses étapes, ses lieux de référence, les hôtels de la veille et du soir), chacun avec sa clé et son emplacement.
    /// Ceux des autres jours, estompés, restent à leur place.
    private var reperes: [(cle: String, coordonnee: CLLocationCoordinate2D)] {
        guard let jourFocus, let index = voyage.jours.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: jourFocus) }) else { return [] }
        let jour = voyage.jours[index]
        return (voyage.infos(du: jour)?.lieux ?? []).map { (cle: "l-\(index)-\($0.id)", coordonnee: $0.coordonnee) }
            + hotelsAutour(de: jour).compactMap { h in h.coordonnee.map { (cle: "h-\(h.uid)", coordonnee: $0) } }
            + voyage.etapes(du: jour).compactMap { e in e.coordonnee.map { (cle: "e-\(e.uid)", coordonnee: $0) } }
    }

    /// Décalage à l'écran des repères qui se chevauchent : ils se rangent côte à côte (par rangées de quatre) autour de leur centre commun.
    /// Suit le zoom : deux repères proches se séparent vus de loin et retrouvent leur place quand on s'approche.
    /// Seulement pour un jour choisi (voir `reperes`) : en vue d'ensemble, rien ne bouge.
    private func ecartsDesReperes(taille: CGSize) -> [String: CGSize] {
        let liste = reperes
        guard liste.count > 1 else { return [:] }
        // Écart entre deux repères voisins : un repère et un peu d'air.
        let pas: Double = 28
        // Points de carte par point d'écran ; sans zone affichée connue, seuls les repères à quelques mètres l'un de l'autre sont écartés.
        let echelle: Double
        if let r = regionVisible, taille.width > 0 {
            echelle = Self.rectangle(r).width / Double(taille.width)
        } else {
            echelle = 5 * MKMapPointsPerMeterAtLatitude(liste[0].coordonnee.latitude) / pas
        }
        guard echelle > 0 else { return [:] }
        let ecran = liste.map { r -> CGPoint in
            let m = MKMapPoint(r.coordonnee)
            return CGPoint(x: m.x / echelle, y: m.y / echelle)
        }

        // Groupes de repères qui se touchent, de proche en proche.
        var parent = Array(liste.indices)
        func racine(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in liste.indices {
            for j in liste.indices where j > i && hypot(ecran[i].x - ecran[j].x, ecran[i].y - ecran[j].y) < pas - 4 {
                parent[racine(j)] = racine(i)
            }
        }

        var ecarts: [String: CGSize] = [:]
        for groupe in Dictionary(grouping: liste.indices, by: racine).values where groupe.count > 1 {
            let centre = CGPoint(x: groupe.map { ecran[$0].x }.reduce(0, +) / Double(groupe.count),
                                 y: groupe.map { ecran[$0].y }.reduce(0, +) / Double(groupe.count))
            // Rangées de haut en bas, chacune de gauche à droite, pour garder à peu près la disposition réelle.
            let colonnes = min(groupe.count, 4)
            let parHauteur = groupe.sorted { (ecran[$0].y, ecran[$0].x) < (ecran[$1].y, ecran[$1].x) }
            let rangees = stride(from: 0, to: parHauteur.count, by: colonnes).map { debut in
                parHauteur[debut..<min(debut + colonnes, parHauteur.count)].sorted { ecran[$0].x < ecran[$1].x }
            }
            for (r, rangee) in rangees.enumerated() {
                for (c, i) in rangee.enumerated() {
                    let x = centre.x + (Double(c) - Double(rangee.count - 1) / 2) * pas
                    let y = centre.y + (Double(r) - Double(rangees.count - 1) / 2) * pas
                    ecarts[liste[i].cle] = CGSize(width: x - ecran[i].x, height: y - ecran[i].y)
                }
            }
        }
        return ecarts
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
        .help("Fond de carte : plan, transports, satellite ou mixte")
    }

    // MARK: Ma position

    /// La carte suit ma position (le bouton est alors plein ; le toucher à nouveau cache ma position).
    private var surMaPosition: Bool { maPosition && position.followsUserLocation }

    private var boutonMaPosition: some View {
        Button {
            Task { await basculerMaPosition() }
        } label: {
            Image(systemName: surMaPosition ? "location.fill" : "location")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surMaPosition ? "Cacher ma position" : "Ma position")
        .help(surMaPosition ? "Cacher ma position" : "Afficher ma position et centrer la carte dessus")
        .alert("Position non autorisée", isPresented: $positionRefusee) {
            Button("Ouvrir les réglages") { ouvrirURL(Self.reglagesLocalisation) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Autorisez Copilote à utiliser votre position dans les réglages pour la voir sur la carte.")
        }
    }

    private static var reglagesLocalisation: URL {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)!
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        #endif
    }

    /// Premier toucher : ma position s'affiche et la carte se centre dessus. Déjà centrée : ma position se cache, la carte reste où elle est.
    private func basculerMaPosition() async {
        if surMaPosition {
            withAnimation(.snappy) { maPosition = false }
            if let r = regionVisible { position = .region(r) }
            return
        }
        guard await Localisation.shared.demander() else {
            positionRefusee = Localisation.shared.refusee
            return
        }
        maPosition = true
        // Si Plans n'a pas encore ma position, la carte se centre quand même dessus, puis la suit.
        let repli: MapCameraPosition = await Localisation.shared.coordonnee()
            .map { .camera(MapCamera(centerCoordinate: $0, distance: 2500)) } ?? position
        withAnimation(.easeInOut(duration: 0.6)) { position = .userLocation(fallback: repli) }
    }

    // MARK: Transports

    /// Change quand il faut chercher de nouvelles stations : fond choisi ou zone (arrondie) affichée.
    private struct CleStations: Equatable {
        var fond: FondCarte
        var lat = 0, lon = 0, etendue = 0
        init(fond: FondCarte, region: MKCoordinateRegion?) {
            self.fond = fond
            guard let r = region else { return }
            lat = Int(r.center.latitude * 200); lon = Int(r.center.longitude * 200)
            etendue = Int(r.span.latitudeDelta * 200)
        }
    }

    /// Plans ne montre ses stations que de très près : on les cherche dans la zone affichée pour les dessiner à toute échelle de ville.
    private func chercherStations() async {
        guard fond == .transports, let region = regionVisible else { stations = []; return }
        // Au-delà d'une grande ville, il y en aurait trop pour que la carte reste lisible.
        guard region.span.latitudeDelta < 0.6 else { stations = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        var trouvees: [String: StationCarte] = [:]
        for mot in ["station de métro", "gare", "station de tramway", "RER", "subway station", "train station", "bus station"] {
            let requete = MKLocalSearch.Request()
            requete.naturalLanguageQuery = mot
            requete.region = region
            requete.resultTypes = .pointOfInterest
            requete.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
            guard let reponse = try? await MKLocalSearch(request: requete).start() else { continue }
            guard !Task.isCancelled else { return }
            for item in reponse.mapItems {
                let c = item.placemark.coordinate
                guard abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta,
                      abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta else { continue }
                let nom = item.name ?? mot
                let cle = "\(nom)|\(Int(c.latitude * 2000))|\(Int(c.longitude * 2000))"
                trouvees[cle] = StationCarte(nom: nom, coordonnee: c)
            }
            stations = Array(trouvees.values)
        }
    }

    /// Les lignes de métro, de tram et de bus : seule l'app Plans sait les dessiner, on l'ouvre sur la même zone.
    private var boutonPlansTransports: some View {
        Button {
            guard let r = regionVisible else { return }
            let lien = "https://maps.apple.com/?ll=\(r.center.latitude),\(r.center.longitude)&spn=\(r.span.latitudeDelta),\(r.span.longitudeDelta)&t=r"
            if let url = URL(string: lien) { ouvrirURL(url) }
        } label: {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.regularMaterial))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voir les lignes dans Plans")
        .help("Voir les lignes de transport dans Plans")
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
            if let ajout = ajoutSousEtape {
                // Une étape est ouverte : le lieu devient une étape à placer, ou une sous-étape de celle qui est ouverte.
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Sous-étape", systemImage: "point.3.connected.trianglepath.dotted") {
                        ajout.ajouter(lieu)
                        fermerFiche()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .help("Ajouter comme sous-étape de « \(ajout.nom) »")
                    Button("Étape", systemImage: "plus.circle.fill") {
                        onLieu(lieu)
                        fermerFiche()
                    }
                    .buttonStyle(.bordered)
                    .help("Créer une étape à placer")
                }
                .fixedSize()
            } else {
            Button("Créer une étape", systemImage: "plus.circle.fill") {
                onLieu(lieu)
                fermerFiche()
            }
            .buttonStyle(.borderedProminent)
            }
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
        // Détail d'une étape à sous-étapes ouvert : le cadre englobe l'étape et ses sous-étapes (un circuit).
        if let focus = etapeFocus {
            let pointsCircuit = ([focus] + focus.sousEtapes).compactMap(\.coordonnee)
            if pointsCircuit.count > 1 {
                var contenu = pointsCircuit.map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }.reduce(MKMapRect.null) { $0.union($1) }
                let minimum = 800 * MKMapPointsPerMeterAtLatitude(pointsCircuit[0].latitude)
                if contenu.width < minimum { contenu = contenu.insetBy(dx: (contenu.width - minimum) / 2, dy: 0) }
                if contenu.height < minimum { contenu = contenu.insetBy(dx: 0, dy: (contenu.height - minimum) / 2) }
                cadrer(contenu.insetBy(dx: -contenu.width * 0.2, dy: -contenu.height * 0.2), taille: taille)
                return
            }
        }
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
        for p in pts + tracesDuFocus {
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
        // Un jour choisi : cadre serré, ses étapes occupent presque toute la partie visible.
        let marge = jourFocus == nil ? 0.5 : 0.15
        contenu = contenu.insetBy(dx: -contenu.width * marge, dy: -contenu.height * marge)
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
