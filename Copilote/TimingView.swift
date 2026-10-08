import SwiftUI
import SwiftData
import CoreLocation

/// Onglet « Timing » : les journées comme dans un agenda. Chaque jour est une colonne de couleur avec ses heures ;
/// les étapes, les transports et les nuits d'hôtel s'y posent à leur heure, avec une hauteur proportionnelle à leur durée.
struct TimingView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var hauteurHeure: CGFloat = 56
    @State private var etapeEnEdition: Etape?
    @State private var transportEnEdition: PaireTransport?
    @State private var extremiteEnEdition: ExtremiteTransport?
    @State private var nuitEnAjout: NuitAjout?
    @State private var aPlacerOuvert = false
    @State private var deplacement: Deplacement?
    @State private var redimension: Redimension?
    @State private var confirmation: DeplacementEnAttente?
    @State private var itineraires = Itineraires.shared
    /// Vrai pour dessiner l'agenda hors écran (contrôles du système remplacés par de simples images).
    var rendu = false

    struct PaireTransport: Identifiable {
        let depart: Etape, arrivee: Etape
        var id: String { depart.uid }
    }

    enum ExtremiteTransport: String, Identifiable {
        case aller, retour
        var id: String { rawValue }
    }

    private struct Deplacement: Equatable { var id: String; var dx: CGFloat; var dy: CGFloat }
    private struct Redimension: Equatable { var id: String; var dy: CGFloat }

    private struct DeplacementEnAttente: Identifiable {
        let id = UUID()
        let etape: Etape
        let jour: Date
        let minutes: Double
        let duree: Double?
        let perdus: [Etape]
    }

    // MARK: Blocs d'une journée

    private struct Bloc: Identifiable {
        enum Genre { case etape, transport, hotelSoir, hotelMatin }
        let id: String
        var genre: Genre
        var debut: Double
        var fin: Double
        var titre: String
        var detail = ""
        var symbole: String
        var etape: Etape?
        /// Heure ou durée estimées (pas encore réglées).
        var estime = false
        var transport: Transport?
        var arrivee: Etape?
        var extremite: ExtremiteTransport?
    }

    private func minutes(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func date(_ jour: Date, _ minutes: Double) -> Date {
        let cal = Calendar.current
        let m = min(max(Int(minutes), 0), 24 * 60 - 1)
        return cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: cal.startOfDay(for: jour)) ?? jour
    }

    private func dureeParDefaut(_ c: CategorieEtape) -> Double {
        switch c {
        case .repas: 75
        case .visite: 90
        case .activite: 120
        case .transport: 60
        case .hebergement: 60
        case .autre: 60
        }
    }

    /// Durée d'un transport : horaires saisis, sinon itinéraire enregistré ou calculé, sinon une durée type.
    private func dureeTransport(_ t: Transport, de depart: Etape?, vers arrivee: Etape?) -> (minutes: Double, estimee: Bool) {
        if let d = t.depart, let a = t.arrivee, minutes(a) > minutes(d) { return (minutes(a) - minutes(d), false) }
        if let s = t.itineraireCommun?.secondes, s > 0 { return (Double(s) / 60, false) }
        if t.mode.aUnItineraire, let a = depart?.coordonnee, let b = arrivee?.coordonnee,
           let duree = itineraires.trajet(a, b, t.mode)?.duree { return (max(duree / 60, 5), false) }
        switch t.mode {
        case .avion: return (120, true)
        case .voiture: return (30, true)
        case .pied, .velo: return (20, true)
        case .commun: return (30, true)
        }
    }

    /// « Métro », « Train »… pour les transports en commun, sinon le mode.
    private func nomTransport(_ t: Transport) -> String { t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt }

    private func blocs(du jour: Date) -> [Bloc] {
        var r: [Bloc] = []
        let cal = Calendar.current
        let jours = voyage.jours
        let veille = cal.date(byAdding: .day, value: -1, to: jour) ?? jour
        var curseur = 9.0 * 60

        // Matin : fin de la nuit d'hôtel de la veille, puis le transport qui en part.
        if let h = voyage.hebergements(apres: veille).first {
            let depart = h.heureFin.map(minutes) ?? 8 * 60
            r.append(Bloc(id: "matin-\(h.uid)", genre: .hotelMatin, debut: 0, fin: depart, titre: h.titre.isEmpty ? "Hébergement" : h.titre,
                          detail: h.lieu, symbole: "bed.double.fill", etape: h, estime: h.heureFin == nil))
            if let t = h.transport {
                let arrivee = voyage.suivante(de: h)
                let d = dureeTransport(t, de: h, vers: arrivee)
                let debut = t.depart.map(minutes) ?? depart
                r.append(Bloc(id: "t-\(h.uid)", genre: .transport, debut: debut, fin: debut + d.minutes, titre: nomTransport(t),
                              detail: t.descriptif, symbole: t.mode.symbole, etape: h, estime: d.estimee, transport: t, arrivee: arrivee))
                curseur = max(curseur, debut + d.minutes)
            } else {
                curseur = max(curseur, depart)
            }
        }

        // Aller : seulement s'il a des horaires.
        if let premier = jours.first, cal.isDate(premier, inSameDayAs: jour), let t = voyage.transportAller, let d = t.depart, let a = t.arrivee {
            let debut = minutes(d)
            r.append(Bloc(id: "aller", genre: .transport, debut: debut, fin: max(minutes(a), debut + 15), titre: "Aller · \(nomTransport(t))",
                          detail: t.descriptif, symbole: t.mode.symbole, transport: t, extremite: .aller))
            curseur = max(curseur, minutes(a))
        }

        // Les étapes : à leur heure, sinon à la suite de la précédente (estimé).
        for e in voyage.etapes(du: jour) {
            let debut = e.heure.map(minutes) ?? curseur
            var fin = debut + dureeParDefaut(e.categorie)
            var estime = e.heure == nil
            if let f = e.heureFin, e.heure != nil, minutes(f) > debut { fin = minutes(f) } else if e.heure != nil { estime = false }
            r.append(Bloc(id: e.uid, genre: .etape, debut: debut, fin: fin, titre: e.titre.isEmpty ? e.categorie.libelle : e.titre,
                          detail: e.lieu, symbole: e.categorie.symbole, etape: e, estime: estime))
            curseur = fin
            if let t = e.transport {
                let arrivee = voyage.suivante(de: e)
                let d = dureeTransport(t, de: e, vers: arrivee)
                let td = t.depart.map(minutes) ?? fin
                r.append(Bloc(id: "t-\(e.uid)", genre: .transport, debut: td, fin: td + d.minutes, titre: nomTransport(t),
                              detail: t.descriptif, symbole: t.mode.symbole, etape: e, estime: d.estimee, transport: t, arrivee: arrivee))
                curseur = max(curseur, td + d.minutes)
            }
        }

        // Retour : seulement s'il a des horaires.
        if let dernier = jours.last, cal.isDate(dernier, inSameDayAs: jour), let t = voyage.transportRetour, let d = t.depart, let a = t.arrivee {
            let debut = minutes(d)
            r.append(Bloc(id: "retour", genre: .transport, debut: debut, fin: max(minutes(a), debut + 15), titre: "Retour · \(nomTransport(t))",
                          detail: t.descriptif, symbole: t.mode.symbole, transport: t, extremite: .retour))
        }

        // Soir : la nuit d'hôtel commence (20 h par défaut) et se prolonge le lendemain matin.
        if let h = voyage.hebergements(apres: jour).first {
            let arrivee = h.heure.map(minutes) ?? 20 * 60
            r.append(Bloc(id: "soir-\(h.uid)", genre: .hotelSoir, debut: arrivee, fin: 24 * 60, titre: h.titre.isEmpty ? "Hébergement" : h.titre,
                          detail: h.lieu, symbole: "bed.double.fill", etape: h, estime: h.heure == nil))
        }
        return r
    }

    /// Voies côte à côte pour les blocs qui se chevauchent (étapes et hôtels ; les transports restent en travers).
    private func voies(_ blocs: [Bloc]) -> [String: (voie: Int, total: Int)] {
        let triees = blocs.filter { $0.genre != .transport }.sorted { ($0.debut, $0.fin) < ($1.debut, $1.fin) }
        var resultat: [String: (Int, Int)] = [:]
        var groupe: [Bloc] = []
        var finGroupe = -Double.infinity

        func clore() {
            var fins: [Double] = []
            var affectation: [String: Int] = [:]
            for b in groupe {
                if let i = fins.firstIndex(where: { $0 <= b.debut }) { fins[i] = max(b.fin, b.debut + 20); affectation[b.id] = i }
                else { fins.append(max(b.fin, b.debut + 20)); affectation[b.id] = fins.count - 1 }
            }
            for b in groupe { resultat[b.id] = (affectation[b.id] ?? 0, max(fins.count, 1)) }
        }
        for b in triees {
            if b.debut >= finGroupe { clore(); groupe = [] }
            groupe.append(b)
            finGroupe = max(finGroupe, max(b.fin, b.debut + 20))
        }
        clore()
        return resultat.mapValues { (voie: $0.0, total: $0.1) }
    }

    // MARK: Dimensions

    /// Largeur du défilement ; la colonne d'un jour la remplit, jusqu'à 760 pt.
    @State private var largeurDisponible: CGFloat = 700
    private var largeurColonne: CGFloat { min(max(largeurDisponible, 300), 760) - gouttiere }
    private let gouttiere: CGFloat = 38
    private let enTete: CGFloat = 54

    private func couleurJour(_ i: Int) -> Color { CarteDuVoyage.couleur(du: i) }

    private func couleurCategorie(_ c: CategorieEtape) -> Color {
        switch c {
        case .repas: .orange
        case .hebergement: .indigo
        case .transport: .blue
        case .visite: .pink
        case .activite: .green
        case .autre: .gray
        }
    }

    // MARK: Corps

    var body: some View {
        VStack(spacing: 0) {
            barre
            ScrollViewReader { lecteur in
                ScrollView(.vertical, showsIndicators: true) {
                    // Les jours se suivent de haut en bas ; l'en-tête du jour reste collé en haut pendant qu'on le parcourt.
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ligneExtremite(.aller)
                        ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                            Section {
                                colonne(i, jour)
                                    .overlay(alignment: .topLeading) {
                                        Color.clear.frame(width: 1, height: 1).offset(y: premiereHeure(jour) * hauteurHeure).id("ancre-\(i)")
                                    }
                            } header: {
                                entete(i, jour)
                            }
                        }
                        ligneExtremite(.retour)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeurDisponible = $0 }
                .onAppear {
                    let cal = Calendar.current
                    let i = voyage.jours.firstIndex { cal.isDateInToday($0) } ?? 0
                    DispatchQueue.main.async { lecteur.scrollTo("ancre-\(i)", anchor: .top) }
                }
            }
        }
        .background(FondDePage.couleur)
        .task(id: clesItineraires) {
            for e in voyage.etapes {
                if let t = e.transport, t.mode.aUnItineraire, let a = e.coordonnee, let b = voyage.suivante(de: e)?.coordonnee {
                    await Itineraires.shared.charger(a, b, t.mode)
                }
            }
        }
        .confirmationDialog("Effacer le transport ?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible, presenting: confirmation) { c in
            Button("Déplacer et effacer le transport", role: .destructive) { appliquer(c) }
            Button("Annuler", role: .cancel) {}
        } message: { c in
            Text(c.perdus.count == 1 ? "Ce déplacement efface le transport prévu après « \(c.perdus[0].titre) »." : "Ce déplacement efface \(c.perdus.count) transports prévus entre des étapes.")
        }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
        .sheet(item: $transportEnEdition) { TransportEditView(depart: $0.depart, arrivee: $0.arrivee) }
        .sheet(item: $extremiteEnEdition) { extremite($0) }
        .sheet(item: $nuitEnAjout, onDismiss: nettoyer) { NuitAjoutView(voyage: voyage, nuit: $0) }
        .sheet(isPresented: $aPlacerOuvert) { APlacerView(voyage: voyage) }
    }

    /// Le transport avant le premier jour (aller) ou après le dernier (retour) : toujours visible, même sans horaires.
    private func ligneExtremite(_ ex: ExtremiteTransport) -> some View {
        let t = ex == .aller ? voyage.transportAller : voyage.transportRetour
        let teinte = Color.indigo
        let duree = t.map { dureeTransport($0, de: nil, vers: nil) }
        return Button { extremiteEnEdition = ex } label: {
            HStack(spacing: 10) {
                Image(systemName: t?.mode.symbole ?? "plus").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Circle().fill(teinte))
                VStack(alignment: .leading, spacing: 1) {
                    if let t {
                        Text("\(ex == .aller ? "Aller" : "Retour") · \(nomTransport(t))").font(.subheadline.weight(.semibold))
                        Text([t.descriptif, t.itineraireCommun != nil || (t.depart != nil && t.arrivee != nil) ? duree.map { dureeTexte($0.minutes) } : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(ex == .aller ? "Ajouter le transport avant le premier jour" : "Ajouter le transport après le dernier jour")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(teinte)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(teinte.opacity(0.6))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous).inset(by: -0))
            .padding(6)
            .frame(width: largeurColonne + gouttiere - 24)
            .background {
                if let t {
                    FondTransport(mode: t.mode, sousType: t.sousType).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(teinte.opacity(0.10))
                        Hachures(couleur: teinte.opacity(0.25), espace: 7).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t == nil ? teinte.opacity(0.7) : .white.opacity(0.9),
                                                                                           style: StrokeStyle(lineWidth: t == nil ? 1.2 : 1.5, dash: t == nil ? [5, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(FondDePage.couleur)
    }

    private func dureeTexte(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }

    /// Les jours les uns sous les autres, sans défilement (aussi utilisés pour vérifier le rendu).
    var agenda: some View {
        VStack(spacing: 0) {
            ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                entete(i, jour)
                colonne(i, jour)
            }
        }
    }

    private var clesItineraires: String {
        voyage.etapes.compactMap { e in e.transport.map { "\(e.uid)\($0.mode.rawValue)" } }.joined(separator: ",")
    }

    /// L'heure à laquelle ouvrir un jour : une heure avant sa première activité, ou 7 h.
    private func premiereHeure(_ jour: Date) -> CGFloat {
        let debuts = blocs(du: jour).filter { $0.genre == .etape }.map(\.debut)
        return CGFloat(max(((debuts.min() ?? 8 * 60) / 60) - 1, 0))
    }

    private var barre: some View {
        HStack(spacing: 12) {
            Button { aPlacerOuvert = true } label: {
                Label("À placer\(voyage.etapesSansJour.isEmpty ? "" : " (\(voyage.etapesSansJour.count))")", systemImage: "tray.full")
            }
            .buttonStyle(.bordered)
            Spacer()
            legende
            Spacer()
            HStack(spacing: 4) {
                Button("Réduire", systemImage: "minus.magnifyingglass") { hauteurHeure = max(36, hauteurHeure - 14) }
                Button("Agrandir", systemImage: "plus.magnifyingglass") { hauteurHeure = min(130, hauteurHeure + 14) }
            }
            .labelStyle(.iconOnly).buttonStyle(.bordered)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var legende: some View {
        HStack(spacing: 10) {
            pastille("Étape", "mappin.and.ellipse", .pink)
            pastille("Transport", "tram.fill", .indigo)
            pastille("Hôtel", "moon.zzz.fill", Color(rouge: 0x3B, vert: 0x2A, bleu: 0x8C))
        }
        .font(.caption2.weight(.semibold))
    }

    private func pastille(_ texte: String, _ symbole: String, _ c: Color) -> some View {
        Label(texte, systemImage: symbole).foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 3).background(c.opacity(0.12), in: Capsule())
    }

    // MARK: En-tête et colonne d'un jour

    private func entete(_ i: Int, _ jour: Date) -> some View {
        let c = couleurJour(i)
        let aujourdhui = Calendar.current.isDateInToday(jour)
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("JOUR \(i + 1)").font(.caption.bold()).foregroundStyle(.white.opacity(0.85))
                    if aujourdhui { Text("Aujourd'hui").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.white.opacity(0.28), in: Capsule()).foregroundStyle(.white) }
                }
                Text(jour.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.headline).foregroundStyle(.white)
            }
            Spacer()
            if rendu { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.white) } else { Menu {
                Button("Ajouter une étape", systemImage: "plus.circle") { ajouter(jour: jour) }
                if voyage.hebergements(apres: jour).isEmpty {
                    Button("Ajouter un hébergement ou un transport de nuit", systemImage: "moon.zzz") { ajouterHebergement(apres: jour) }
                }
                if i == 0 { Button("Transport d'aller", systemImage: "airplane.departure") { extremiteEnEdition = .aller } }
                if i == voyage.jours.count - 1 { Button("Transport de retour", systemImage: "airplane.arrival") { extremiteEnEdition = .retour } }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(voyage.lectureSeule) }
        }
        .padding(.horizontal, 12)
        .frame(width: largeurColonne + gouttiere, height: enTete, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(c)
    }

    private func colonne(_ i: Int, _ jour: Date) -> some View {
        let c = couleurJour(i)
        let liste = blocs(du: jour)
        let placement = voies(liste)
        let hauteur = hauteurHeure * 24
        let contenu = largeurColonne - 8
        return ZStack(alignment: .topLeading) {
            // Fond du jour : sa couleur, plus soutenue la nuit.
            Rectangle().fill(c.opacity(0.10))
            Rectangle().fill(c.opacity(0.10)).frame(height: hauteurHeure * 6)
            Rectangle().fill(c.opacity(0.10)).frame(height: hauteurHeure * 4).offset(y: hauteurHeure * 20)
            // Lignes des heures.
            ForEach(0..<24, id: \.self) { h in
                Rectangle().fill(c.opacity(h % 6 == 0 ? 0.65 : 0.38)).frame(height: h % 6 == 0 ? 1.5 : 1).offset(y: CGFloat(h) * hauteurHeure)
                // Heure sur une pastille opaque, en texte foncé : lisible quelle que soit la couleur du jour.
                Text(String(format: "%02d h", h)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.background))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(c.opacity(0.7), lineWidth: 1))
                    .frame(width: gouttiere, alignment: .center).offset(y: CGFloat(h) * hauteurHeure + (h == 0 ? 3 : -8))
                if hauteurHeure >= 80 {
                    Rectangle().fill(c.opacity(0.22)).frame(height: 1).offset(y: CGFloat(h) * hauteurHeure + hauteurHeure / 2)
                }
            }
            if Calendar.current.isDateInToday(jour) { maintenant(hauteur) }
            ForEach(liste.filter { $0.genre != .transport }) { b in
                let p = placement[b.id] ?? (0, 1)
                bloc(b, jourIndex: i, jour: jour, voie: p.voie, total: p.total, largeur: contenu)
            }
            ForEach(liste.filter { $0.genre == .transport }) { b in
                bloc(b, jourIndex: i, jour: jour, voie: 0, total: 1, largeur: contenu)
            }
        }
        .frame(width: largeurColonne + gouttiere, height: hauteur, alignment: .topLeading)
        .clipped()
        .frame(maxWidth: .infinity)
        .background(c.opacity(0.06))
        .modifier(DepotSurJour(actif: !rendu) { elements in
            // On peut lâcher ici une étape « à placer » ou venue d'un autre jour.
            guard !voyage.lectureSeule, let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count),
                  let etape = voyage.etapes.first(where: { $0.uid == String(uid) }) else { return false }
            return voyage.deplacer(etape, vers: jour, avant: nil)
        })
    }

    private static let prefixe = "copilote-etape:"

    private func maintenant(_ hauteur: CGFloat) -> some View {
        let m = minutes(.now)
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .offset(y: CGFloat(m) / 60 * hauteurHeure - 4)
        .allowsHitTesting(false)
    }

    // MARK: Un bloc

    @ViewBuilder private func bloc(_ b: Bloc, jourIndex: Int, jour: Date, voie: Int, total: Int, largeur: CGFloat) -> some View {
        let enDeplacement = deplacement?.id == b.id ? deplacement : nil
        let enRedim = redimension?.id == b.id ? redimension : nil
        let dy = (enDeplacement?.dy ?? 0)
        let debut = b.debut + Double(dy / hauteurHeure) * 60
        let fin = b.fin + Double((enDeplacement?.dy ?? 0) / hauteurHeure) * 60 + Double((enRedim?.dy ?? 0) / hauteurHeure) * 60
        let hauteur = max(CGFloat(fin - debut) / 60 * hauteurHeure, b.genre == .transport ? 30 : 30)
        let inset: CGFloat = b.genre == .transport ? 14 : 3
        let w = (largeur - inset * 2) / CGFloat(total)
        let x = gouttiere + inset + CGFloat(voie) * w

        Group {
            switch b.genre {
            case .etape: carteEtape(b, hauteur: hauteur, debut: debut, fin: fin, jourIndex: jourIndex, actif: enDeplacement != nil || enRedim != nil)
            case .transport: carteTransport(b, hauteur: hauteur)
            case .hotelSoir, .hotelMatin: carteHotel(b, hauteur: hauteur)
            }
        }
        .frame(width: w - 2, height: hauteur)
        .offset(x: x, y: CGFloat(debut) / 60 * hauteurHeure + 1)
        .zIndex(enDeplacement != nil || enRedim != nil ? 10 : (b.genre == .transport ? 2 : 1))
    }

    private func heureTexte(_ m: Double) -> String {
        let v = Int(m.rounded()) % (24 * 60 + 1)
        return String(format: "%02d:%02d", min(v / 60, 24), v % 60)
    }

    /// Une étape : carte claire, liseré de la couleur de sa catégorie, contour de la couleur du jour.
    private func carteEtape(_ b: Bloc, hauteur: CGFloat, debut: Double, fin: Double, jourIndex: Int, actif: Bool) -> some View {
        let c = couleurJour(jourIndex)
        let cat = couleurCategorie(b.etape?.categorie ?? .autre)
        let haut = hauteur >= 56
        let quelconque = b.etape.map { !$0.photos.isEmpty } ?? false
        return ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Rectangle().fill(cat).frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: b.symbole).font(.caption).foregroundStyle(cat)
                        Text(b.titre).font(.caption.weight(.semibold)).lineLimit(haut ? 2 : 1)
                        if b.estime { Image(systemName: "clock.badge.questionmark").font(.caption2).foregroundStyle(.orange) }
                    }
                    if hauteur >= 44 {
                        Text("\(heureTexte(debut)) → \(heureTexte(fin))").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.primary.opacity(0.8))
                    }
                    if haut, !b.detail.isEmpty { Text(b.detail).font(.caption2).foregroundStyle(.primary.opacity(0.65)).lineLimit(hauteur > 90 ? 2 : 1) }
                    if hauteur >= 96, let budget = b.etape?.resumeBudget { Label(budget, systemImage: "eurosign.circle").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if quelconque == false, !(b.etape?.voyage?.lectureSeule ?? true), b.etape != nil {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 28, height: 4).padding(.bottom, 2)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background))
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(c.opacity(0.16)))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(c, style: StrokeStyle(lineWidth: actif ? 2.5 : 1.5, dash: b.estime ? [4, 3] : [])))
        .shadow(color: .black.opacity(actif ? 0.35 : 0.12), radius: actif ? 8 : 2, y: actif ? 4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if let e = b.etape { etapeEnEdition = e } }
        .gesture(deplacementGeste(b, jourIndex: jourIndex))
        .overlay(alignment: .bottom) { poignee(b) }
        .contextMenu { menuEtape(b) }
        .accessibilityLabel("\(b.titre), \(heureTexte(debut)) à \(heureTexte(fin))")
    }

    /// La poignée du bas : la tirer règle l'heure de fin.
    @ViewBuilder private func poignee(_ b: Bloc) -> some View {
        if b.etape != nil, !voyage.lectureSeule {
            Color.clear.frame(height: 14).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { redimension = Redimension(id: b.id, dy: $0.translation.height) }
                    .onEnded { v in terminerRedimension(b, dy: v.translation.height); redimension = nil })
        }
    }

    @ViewBuilder private func menuEtape(_ b: Bloc) -> some View {
        if let e = b.etape {
            Button("Modifier", systemImage: "pencil") { etapeEnEdition = e }
            if !voyage.lectureSeule {
                if e.heure != nil {
                    Button("Effacer les horaires", systemImage: "clock.badge.xmark") { e.heure = nil; e.heureFin = nil }
                }
                if let suivante = voyage.suivante(de: e) {
                    Button(e.transport == nil ? "Ajouter un transport après" : "Modifier le transport après", systemImage: "arrow.triangle.swap") {
                        transportEnEdition = PaireTransport(depart: e, arrivee: suivante)
                    }
                }
                Menu("Changer de jour", systemImage: "calendar") {
                    ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                        Button("Jour \(i + 1) · \(jour.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))") {
                            changerDeJour(b, vers: jour)
                        }
                        .disabled(e.jour.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? false)
                    }
                }
                Button("Retirer du jour", systemImage: "tray.and.arrow.up") { _ = voyage.retirerDuJour(e) }
                Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(e) }
            }
        }
    }

    /// Un transport : un décor à son image (ciel, route, rails, mer…) avec une étiquette lisible, ses couleurs bien visibles.
    private func carteTransport(_ b: Bloc, hauteur: CGFloat) -> some View {
        let duree = Int((b.fin - b.debut).rounded())
        let texteDuree = "\(duree >= 60 ? "\(duree / 60) h \(String(format: "%02d", duree % 60))" : "\(duree) min")\(b.estime ? " ?" : "")"
        let forme = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack(alignment: .leading) {
            FondTransport(mode: b.transport?.mode ?? .voiture, sousType: b.transport?.sousType ?? "")
                .clipShape(forme)
            EtiquetteTransport(symbole: b.symbole, titre: "\(b.titre) · \(texteDuree)", detail: hauteur >= 46 ? b.detail : "")
                .padding(.leading, 6)
        }
        .overlay(forme.strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
        .overlay(forme.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
        .contentShape(Rectangle())
        .onTapGesture { ouvrirTransport(b) }
    }

    private func ouvrirTransport(_ b: Bloc) {
        if let ex = b.extremite { extremiteEnEdition = ex; return }
        guard let depart = b.etape else { return }
        if let arrivee = b.arrivee ?? voyage.suivante(de: depart) ?? depart.jour.flatMap({ voyage.transportDeNuit(apres: $0)?.arrivee }) {
            transportEnEdition = PaireTransport(depart: depart, arrivee: arrivee)
        }
    }

    /// Une nuit d'hôtel : bloc nocturne dégradé, avec lune et étoiles ; il se prolonge d'un jour à l'autre.
    private func carteHotel(_ b: Bloc, hauteur: CGFloat) -> some View {
        let soir = b.genre == .hotelSoir
        let nuit = [Color(rouge: 0x14, vert: 0x18, bleu: 0x4A), Color(rouge: 0x3B, vert: 0x2A, bleu: 0x8C)]
        let rayon: CGFloat = 12
        let forme = UnevenRoundedRectangle(topLeadingRadius: soir ? rayon : 3, bottomLeadingRadius: soir ? 3 : rayon,
                                           bottomTrailingRadius: soir ? 3 : rayon, topTrailingRadius: soir ? rayon : 3, style: .continuous)
        return ZStack(alignment: .topLeading) {
            forme.fill(LinearGradient(colors: soir ? nuit : nuit.reversed() + [Color(rouge: 0xE0, vert: 0x7A, bleu: 0x5F)],
                                      startPoint: .top, endPoint: .bottom))
            if hauteur > 60 {
                ForEach(0..<6, id: \.self) { i in
                    Image(systemName: "sparkle").font(.system(size: CGFloat(5 + i % 3 * 2))).foregroundStyle(.white.opacity(0.6))
                        .offset(x: CGFloat((i * 47) % 160) + 70, y: CGFloat((i * 31) % Int(max(hauteur - 20, 30))) + 8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: soir ? "moon.zzz.fill" : "sunrise.fill").foregroundStyle(soir ? .yellow : .orange)
                    Text(b.titre).font(.caption.weight(.bold)).lineLimit(1)
                    if b.estime { Image(systemName: "clock.badge.questionmark").font(.caption2).foregroundStyle(.white.opacity(0.7)) }
                }
                Text(soir ? "Arrivée \(heureTexte(b.debut))" : "Départ \(heureTexte(b.fin))").font(.caption.weight(.semibold).monospacedDigit())
                if hauteur > 90, !b.detail.isEmpty { Text(b.detail).font(.caption2).opacity(0.75).lineLimit(2) }
            }
            .foregroundStyle(.white)
            .padding(8)
        }
        .clipShape(forme)
        .overlay(forme.strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { if let e = b.etape { etapeEnEdition = e } }
        .contextMenu { if let e = b.etape {
            Button("Modifier l'hébergement", systemImage: "pencil") { etapeEnEdition = e }
            if !voyage.lectureSeule { Button("Retirer", systemImage: "tray.and.arrow.up") { _ = voyage.retirerDuJour(e) } }
        } }
    }

    // MARK: Gestes

    /// Appui prolongé puis glissé : l'étape change d'heure (haut/bas) et de jour (gauche/droite).
    private func deplacementGeste(_ b: Bloc, jourIndex: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { valeur in
                guard !voyage.lectureSeule, case .second(true, let drag?) = valeur else { return }
                deplacement = Deplacement(id: b.id, dx: drag.translation.width, dy: drag.translation.height)
            }
            .onEnded { valeur in
                defer { deplacement = nil }
                guard !voyage.lectureSeule, case .second(true, let drag?) = valeur else { return }
                terminerDeplacement(b, jourIndex: jourIndex, dx: drag.translation.width, dy: drag.translation.height)
            }
    }

    private func arrondi(_ m: Double) -> Double { (m / 15).rounded() * 15 }

    private func terminerDeplacement(_ b: Bloc, jourIndex: Int, dx: CGFloat, dy: CGFloat) {
        guard let e = b.etape else { return }
        let jours = voyage.jours
        let nouveauDebut = min(max(arrondi(b.debut + Double(dy / hauteurHeure) * 60), 0), 24 * 60 - 15)
        let cible = jourIndex
        let duree = e.heureFin != nil && e.heure != nil ? b.fin - b.debut : nil
        if cible != jourIndex {
            let perdus = voyage.transportsPerdus(deplacant: e, vers: jours[cible], avant: nil)
            let c = DeplacementEnAttente(etape: e, jour: jours[cible], minutes: nouveauDebut, duree: duree, perdus: perdus)
            if perdus.isEmpty { appliquer(c) } else { confirmation = c }
        } else {
            appliquer(DeplacementEnAttente(etape: e, jour: jours[cible], minutes: nouveauDebut, duree: duree, perdus: []))
        }
    }

    /// Même heure, un autre jour (avec confirmation si un transport entre étapes serait effacé).
    private func changerDeJour(_ b: Bloc, vers jour: Date) {
        guard let e = b.etape else { return }
        let perdus = voyage.transportsPerdus(deplacant: e, vers: jour, avant: nil)
        let duree = e.heureFin != nil && e.heure != nil ? b.fin - b.debut : nil
        let c = DeplacementEnAttente(etape: e, jour: jour, minutes: b.debut, duree: duree, perdus: perdus)
        if perdus.isEmpty { appliquer(c) } else { confirmation = c }
    }

    private func appliquer(_ c: DeplacementEnAttente) {
        withAnimation(.snappy) {
            for e in c.perdus { e.transport = nil }
            let ancien = c.etape.jour
            if ancien == nil || !Calendar.current.isDate(ancien!, inSameDayAs: c.jour) { _ = voyage.deplacer(c.etape, vers: c.jour, avant: nil) }
            c.etape.heure = date(c.jour, c.minutes)
            if let duree = c.duree { c.etape.heureFin = date(c.jour, min(c.minutes + duree, 24 * 60 - 1)) }
            // L'ordre suit les heures, sauf si des transports entre étapes en dépendent.
            if voyage.etapes(du: c.jour).allSatisfy({ $0.transport == nil }) { voyage.trierParHeure(c.jour) }
        }
    }

    private func terminerRedimension(_ b: Bloc, dy: CGFloat) {
        guard let e = b.etape, let jour = e.jour else { return }
        let fin = min(max(arrondi(b.fin + Double(dy / hauteurHeure) * 60), b.debut + 15), 24 * 60 - 1)
        withAnimation(.snappy) {
            if e.heure == nil { e.heure = date(jour, b.debut) }
            e.heureFin = date(jour, fin)
        }
    }

    // MARK: Création et nettoyage

    private func ajouter(jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.ordre = (voyage.etapes(du: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    private func ajouterHebergement(apres jour: Date) {
        let etape = Etape(titre: "", jour: jour, categorie: .hebergement)
        etape.apresJour = true
        etape.ordre = (voyage.hebergements(apres: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        nuitEnAjout = NuitAjout(etape: etape, jour: jour)
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }

    private func extremite(_ ex: ExtremiteTransport) -> some View {
        let elements = voyage.elementsDuVoyage
        let etape = ex == .aller ? elements.first : elements.last
        let nom = etape.map { $0.titre.isEmpty ? "Étape" : $0.titre } ?? "Étape"
        let jours = voyage.jours
        return TransportEditView(
            trajet: ex == .aller ? "Départ → \(nom)" : "\(nom) → Retour",
            jour: (ex == .aller ? jours.first : jours.last) ?? .now,
            coordonnees: nil,
            existant: ex == .aller ? voyage.transportAller : voyage.transportRetour,
            lieuxExtremites: true,
            voyage: voyage,
            enregistrer: { nouveau in
                if ex == .aller { voyage.transportAller = nouveau } else { voyage.transportRetour = nouveau }
            })
    }
}

private struct DepotSurJour: ViewModifier {
    var actif: Bool
    var action: ([String]) -> Bool

    @ViewBuilder func body(content: Content) -> some View {
        if actif { content.dropDestination(for: String.self) { elements, _ in action(elements) } } else { content }
    }
}

/// Fines diagonales, pour reconnaître d'un coup d'œil un transport.
private struct Hachures: View {
    var couleur: Color
    var espace: CGFloat

    var body: some View {
        Canvas { contexte, taille in
            var x = -taille.height
            while x < taille.width {
                var trait = Path()
                trait.move(to: CGPoint(x: x, y: taille.height))
                trait.addLine(to: CGPoint(x: x + taille.height, y: 0))
                contexte.stroke(trait, with: .color(couleur), lineWidth: 1.4)
                x += espace
            }
        }
        .allowsHitTesting(false)
    }
}

/// Les étapes préparées sans jour : on les range sur un jour d'un geste.
struct APlacerView: View {
    @Bindable var voyage: Voyage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var etape: Etape?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voyage.etapesSansJour) { e in
                        HStack(spacing: 10) {
                            Image(systemName: e.categorie.symbole).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(e.titre.isEmpty ? "Sans titre" : e.titre)
                                if !e.lieu.isEmpty { Text(e.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { etape = e }
                            Spacer()
                            Menu("Placer…") {
                                ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                                    Button("Jour \(i + 1) · \(jour.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))") {
                                        _ = voyage.deplacer(e, vers: jour, avant: nil)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                            .disabled(voyage.lectureSeule)
                        }
                    }
                    .onDelete { for i in $0 { contexte.delete(voyage.etapesSansJour[i]) } }
                } footer: {
                    Text(voyage.etapesSansJour.isEmpty ? "Aucune étape en attente. Prépare ici des idées, puis place-les sur un jour." : "Choisis un jour : l'étape apparaît dans l'agenda, à l'heure que tu règles ensuite.")
                }
                Section {
                    Button("Ajouter une idée", systemImage: "plus.circle.fill") {
                        let e = Etape(titre: "", jour: nil)
                        e.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
                        e.voyage = voyage
                        contexte.insert(e)
                        etape = e
                    }
                    .disabled(voyage.lectureSeule)
                }
            }
            .navigationTitle("À placer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(item: $etape, onDismiss: {
                for e in voyage.etapes where e.titre.trimmingCharacters(in: .whitespaces).isEmpty && e.lieu.isEmpty { contexte.delete(e) }
            }) { e in
                EtapeEditView(etape: e, jours: voyage.jours) { contexte.delete(e) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}
