import SwiftUI
import SwiftData

/// Le planning : une carte par jour, avec sa date, ses lieux de référence et ses étapes.
struct ItineraireView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?
    @State private var jourEnEdition: JourVoyage?
    /// Étape au-dessus de laquelle on s'apprête à déposer (trait d'insertion), ou jour survolé.
    @State private var etapeVisee: String?
    @State private var jourVise: Date?
    @State private var nuitVisee: Date?
    /// Jour sur lequel la carte est cadrée ; nil = tout le voyage.
    @State private var jourSelectionne: Date?
    /// Étape dont on affiche l'explication de l'avertissement d'horaire.
    @State private var avertissementOuvert: String?
    @State private var discussionOuverte = false
    /// Écran large : la discussion devient un cadre sur la carte au lieu d'une feuille.
    @State private var ecranLarge = false
    /// Hauteur du contenu de « Étapes à placer » (iPad), pour que son défilement ne couvre pas la carte.
    @State private var hauteurEtapesAPlacer: CGFloat = .infinity
    /// Déplacement qui effacerait des transports : en attente de confirmation.
    @State private var deplacementEnAttente: DeplacementEnAttente?

    private struct DeplacementEnAttente: Identifiable {
        let id = UUID()
        let etape: Etape
        let jour: Date?
        let cible: Etape?
        let perdus: [Etape]
        var nuit = false
    }

    private let cal = Calendar.current

    private var horsDates: [Etape] {
        voyage.etapes.filter { e in
            guard let jour = e.jour else { return false }
            return !voyage.jours.contains { cal.isDate($0, inSameDayAs: jour) }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let panneauLateral = geo.size.width >= 700
            if panneauLateral {
                // iPad, Mac : la carte en fond, les jours empilés dans un panneau à gauche.
                ZStack(alignment: .leading) {
                    fondDeCarte(margeGauche: Self.largeurPanneau)
                    ScrollView { listeDesJours(avecEtapesAPlacer: false).padding(12) }
                        .frame(width: Self.largeurPanneau)
                        .scrollIndicators(.hidden)
                    // À droite, sous le bouton : la discussion puis les étapes à placer. Seuls les cadres captent le toucher.
                    VStack(alignment: .trailing, spacing: 0) {
                        if discussionOuverte {
                            CommentairesView(voyage: voyage, enCadre: true, ouverte: $discussionOuverte)
                                .frame(width: 320, height: min(440, max(260, geo.size.height * 0.55)))
                                .padding(12)
                        }
                        if !voyage.etapesSansJour.isEmpty {
                            // Le défilement se limite à la hauteur du contenu : en dessous, le doigt agit sur la carte.
                            ScrollView {
                                etapesAPlacer.padding(12)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteurEtapesAPlacer = $0 }
                            }
                            .frame(width: 344)
                            .frame(maxHeight: hauteurEtapesAPlacer)
                            .scrollIndicators(.hidden)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            } else {
                // iPhone : la carte en haut, les jours dessous.
                VStack(spacing: 0) {
                    fondDeCarte(margeGauche: 0).frame(height: max(220, geo.size.height * 0.36))
                    ScrollView { listeDesJours(avecEtapesAPlacer: true).padding(12) }
                        .background(FondDePage.couleur)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { ecranLarge = $0 }
        // Déposer une étape en dehors d'une carte de jour : elle n'a plus de jour.
        .dropDestination(for: String.self) { elements, _ in
            guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count),
                  let etape = voyage.etapes.first(where: { $0.uid == String(uid) }) else { return false }
            return demander(etape, vers: nil, avant: nil)
        }
        .confirmationDialog("Effacer le transport ?", isPresented: Binding(get: { deplacementEnAttente != nil }, set: { if !$0 { deplacementEnAttente = nil } }), titleVisibility: .visible, presenting: deplacementEnAttente) { d in
            Button("Déplacer et effacer le transport", role: .destructive) { appliquer(d) }
            Button("Annuler", role: .cancel) {}
        } message: { d in
            Text(d.perdus.count == 1 ? "Ce déplacement efface le transport prévu après « \(d.perdus[0].titre) »." : "Ce déplacement efface \(d.perdus.count) transports prévus entre des étapes.")
        }
        .toolbar {
            // Préparation seulement : on échange sur le déroulé avec les autres voyageurs.
            if voyage.mode == .preparation {
                ToolbarItem(placement: .primaryAction) {
                    Button { discussionOuverte.toggle() } label: {
                        Label(voyage.commentaires.isEmpty ? "Discussion" : "Discussion (\(voyage.commentaires.count))",
                              systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { discussionOuverte && !ecranLarge }, set: { discussionOuverte = $0 })) { CommentairesView(voyage: voyage) }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
        .sheet(item: $jourEnEdition, onDismiss: nettoyerJours) { infos in
            JourEditView(jour: infos, voyage: voyage, numero: (voyage.jours.firstIndex { cal.isDate($0, inSameDayAs: infos.date) } ?? 0) + 1)
        }
    }

    private static let largeurPanneau: CGFloat = 404

    private func fondDeCarte(margeGauche: CGFloat) -> some View {
        CarteDuVoyage(voyage: voyage, jourFocus: jourSelectionne, masquerAutresJours: false, margeGauche: margeGauche) { etape in
            etapeEnEdition = etape
        }
    }

    /// Les jours, les uns au-dessus des autres.
    private func listeDesJours(avecEtapesAPlacer: Bool) -> some View {
        LazyVStack(spacing: 12) {
            // iPhone : les étapes sans jour passent au-dessus du jour 1.
            if avecEtapesAPlacer && !voyage.etapesSansJour.isEmpty { etapesAPlacer }
            ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                carte(numero: index + 1, jour: jour)
                nuit(apres: jour)
            }
            if !horsDates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hors des dates du voyage").font(.headline)
                    ForEach(horsDates) { ligne($0) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(FondDeCarte())
            }
        }
    }

    /// Étapes préparées sans jour : on les glisse sur la carte d'un jour pour les placer.
    private var etapesAPlacer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Étapes à placer", systemImage: "tray.full").font(.headline)
            Text("Glisse une étape sur un jour.").font(.footnote).foregroundStyle(.secondary)
            Divider()
            ForEach(voyage.etapesSansJour) { etape in
                ligne(etape)
                    .draggable(Self.prefixe + etape.uid) {
                        Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouterSansJour() }
                .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    private func ajouterSansJour() {
        let etape = Etape(titre: "", jour: nil)
        etape.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    // MARK: Hébergements entre deux jours

    private func texteNuit(_ jour: Date) -> String {
        let lendemain = cal.date(byAdding: .day, value: 1, to: jour) ?? jour
        return "Nuit du \(jour.formatted(.dateTime.day().month(.abbreviated))) au \(lendemain.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// Bande entre deux jours : les hébergements de la nuit, ou un bouton pour en ajouter un.
    private func nuit(apres jour: Date) -> some View {
        let hebergements = voyage.hebergements(apres: jour)
        let vise = nuitVisee.map { cal.isDate($0, inSameDayAs: jour) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Label(hebergements.isEmpty ? "Hébergement" : texteNuit(jour), systemImage: "moon.zzz.fill")
                .font(.caption.bold()).foregroundStyle(Self.couleurNuit)
            ForEach(hebergements) { h in
                VStack(alignment: .leading, spacing: 2) {
                    ligne(h)
                }
                .draggable(Self.prefixe + h.uid) {
                    Label(h.titre.isEmpty ? "Hébergement" : h.titre, systemImage: h.categorie.symbole)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if hebergements.isEmpty {
                Button("Ajouter un hébergement", systemImage: "plus.circle.fill") { ajouterHebergement(apres: jour) }
                    .buttonStyle(.borderless).tint(Self.couleurNuit).font(.footnote)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.couleurNuit.opacity(vise ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Self.couleurNuit.opacity(0.6), style: StrokeStyle(lineWidth: vise ? 2 : 1, dash: hebergements.isEmpty ? [5, 4] : [])))
        .dropDestination(for: String.self) { elements, _ in
            defer { nuitVisee = nil }
            guard let etape = etapeGlissee(elements), etape.categorie == .hebergement else { return false }
            return demanderNuit(etape, apres: jour)
        } isTargeted: { visee in
            if visee { nuitVisee = jour } else if let actuel = nuitVisee, cal.isDate(actuel, inSameDayAs: jour) { nuitVisee = nil }
        }
    }

    private static let couleurNuit = Color.mint

    private func etapeGlissee(_ elements: [String]) -> Etape? {
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count) else { return nil }
        return voyage.etapes.first { $0.uid == String(uid) }
    }

    private func ajouterHebergement(apres jour: Date) {
        let etape = Etape(titre: "", jour: jour, categorie: .hebergement)
        etape.apresJour = true
        etape.ordre = (voyage.hebergements(apres: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    private func estSelectionne(_ jour: Date) -> Bool {
        jourSelectionne.map { cal.isDate($0, inSameDayAs: jour) } ?? false
    }

    // MARK: Carte d'un jour

    private func carte(numero: Int, jour: Date) -> some View {
        let infos = voyage.infos(du: jour)
        let etapes = voyage.etapes(du: jour)
        // Même couleur et mêmes numéros que le tracé et les repères sur la carte.
        let couleur = CarteDuVoyage.couleur(du: numero - 1)
        let placees = etapes.filter { $0.coordonnee != nil }
        let incoherences = voyage.etapesAuxHorairesIncoherents(du: jour)
        let chevauchements = voyage.etapesEnChevauchement(du: jour)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { jourSelectionne = estSelectionne(jour) ? nil : jour }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(couleur)
                        Spacer()
                    }
                    Text(premiereLettreEnMajuscule(jour.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                        .font(.title3.bold()).foregroundStyle(.primary)
                    if let titre = infos?.titre, !titre.isEmpty {
                        Text(titre).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let lieux = infos?.lieux, !lieux.isEmpty {
                        FlowLayout(espacement: 6) {
                            ForEach(lieux) { lieu in
                                Label(lieu.etiquette, systemImage: lieu.estPays ? "flag.fill" : "mappin.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(couleur.opacity(0.14), in: Capsule())
                                    .foregroundStyle(couleur)
                            }
                        }
                    } else {
                        Label("Où se passe la journée ?", systemImage: "mappin.and.ellipse")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                    if let notes = infos?.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            if etapes.isEmpty {
                Text("Aucune étape").font(.footnote).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(etapes) { etape in
                        ligneGlissable(etape, jour: jour, couleur: couleur,
                                       rang: placees.firstIndex { $0 === etape }, incoherence: incoherences[etape.uid], chevauche: chevauchements[etape.uid])
                    }
                }
            }

            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(le: jour) }
                .buttonStyle(.borderless)
                .tint(couleur)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
        .overlay(alignment: .leading) {
            Capsule().fill(couleur).frame(width: 5).padding(.vertical, 16).padding(.leading, 5)
        }
        .overlay(alignment: .topTrailing) { menuDuJour(jour, infos: infos) }
        .overlay {
            if estSelectionne(jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2.5)
            }
        }
        .overlay {
            if let jourVise, cal.isDate(jourVise, inSameDayAs: jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2)
            }
        }
        .dropDestination(for: String.self) { elements, _ in
            recevoir(elements, jour: jour, avant: nil)
        } isTargeted: { visee in
            if visee { jourVise = jour } else if let actuel = jourVise, cal.isDate(actuel, inSameDayAs: jour) { jourVise = nil }
        }
    }

    // MARK: Glisser-déposer

    private static let prefixe = "copilote-etape:"

    private func ligneGlissable(_ etape: Etape, jour: Date, couleur: Color, rang: Int?, incoherence: Date?, chevauche: Etape? = nil) -> some View {
        ligne(etape, couleur: couleur, rang: rang, incoherence: incoherence, chevauche: chevauche)
            .draggable(Self.prefixe + etape.uid) {
                Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .top) {
                if etapeVisee == etape.uid {
                    Capsule().fill(.tint).frame(height: 3).offset(y: -7)
                }
            }
            .dropDestination(for: String.self) { elements, _ in
                recevoir(elements, jour: jour, avant: etape)
            } isTargeted: { visee in
                if visee { etapeVisee = etape.uid } else if etapeVisee == etape.uid { etapeVisee = nil }
            }
    }

    /// Menu de la carte : modifier le jour, ou remettre ses étapes dans l'ordre des heures.
    private func menuDuJour(_ jour: Date, infos: JourVoyage?) -> some View {
        Menu {
            Button("Modifier le jour", systemImage: "pencil") { jourEnEdition = infos ?? creerInfos(jour) }
            Button("Trier par heure", systemImage: "clock") { trierParHeure(jour) }
                .disabled(voyage.etapes(du: jour).count < 2)
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary).padding(12)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func recevoir(_ elements: [String], jour: Date, avant cible: Etape?) -> Bool {
        defer { etapeVisee = nil; jourVise = nil }
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count) else { return false }
        // Un hébergement lâché sur un jour va à la fin de ce jour, entre lui et le suivant.
        if let etape = voyage.etapes.first(where: { $0.uid == String(uid) }), etape.categorie == .hebergement {
            return demanderNuit(etape, apres: jour)
        }
        return deplacer(String(uid), vers: jour, avant: cible)
    }

    private func deplacer(_ uid: String, vers jour: Date, avant cible: Etape?) -> Bool {
        guard let etape = voyage.etapes.first(where: { $0.uid == uid }) else { return false }
        return demander(etape, vers: jour, avant: cible)
    }

    /// Déplace tout de suite, ou demande confirmation si des transports entre étapes seraient effacés.
    private func demander(_ etape: Etape, vers jour: Date?, avant cible: Etape?) -> Bool {
        if cible === etape { return false }
        let perdus = voyage.transportsPerdus(deplacant: etape, vers: jour, avant: cible)
        if perdus.isEmpty {
            return appliquer(DeplacementEnAttente(etape: etape, jour: jour, cible: cible, perdus: []))
        }
        deplacementEnAttente = DeplacementEnAttente(etape: etape, jour: jour, cible: cible, perdus: perdus)
        return true
    }

    private func demanderNuit(_ etape: Etape, apres jour: Date) -> Bool {
        let perdus = voyage.transportsPerdus(deplacant: etape, vers: jour, avant: nil, nuit: true)
        let d = DeplacementEnAttente(etape: etape, jour: jour, cible: nil, perdus: perdus, nuit: true)
        if perdus.isEmpty { return appliquer(d) }
        deplacementEnAttente = d
        return true
    }

    @discardableResult
    private func appliquer(_ d: DeplacementEnAttente) -> Bool {
        withAnimation {
            for e in d.perdus { e.transport = nil }
            if d.nuit, let jour = d.jour { voyage.placerEntreJours(d.etape, apres: jour); return true }
            if let jour = d.jour { return voyage.deplacer(d.etape, vers: jour, avant: d.cible) }
            return voyage.retirerDuJour(d.etape)
        }
    }

    private func trierParHeure(_ jour: Date) {
        withAnimation { voyage.trierParHeure(jour) }
    }

    /// `rang` : numéro du repère sur la carte (étapes placées seulement) ; sinon l'icône de la catégorie.
    /// `incoherence` : heure de l'étape précédente qui contredit celle-ci (l'étape est placée après une étape plus tardive).
    private func ligne(_ etape: Etape, couleur: Color = .accentColor, rang: Int? = nil, incoherence: Date? = nil, chevauche: Etape? = nil) -> some View {
        HStack(spacing: 12) {
                Group {
                    if let rang {
                        Text("\(rang + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(couleur, in: Circle())
                    } else {
                        Image(systemName: etape.categorie.symbole)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(couleur)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).font(.headline).foregroundStyle(.primary)
                    if etape.noteGoogle != nil || etape.noteTripadvisor != nil {
                        NotesView(google: etape.noteGoogle.flatMap { n in etape.avisGoogle.map { (n, $0) } },
                                  tripadvisor: etape.noteTripadvisor.flatMap { n in etape.avisTripadvisor.map { (n, $0) } })
                    }
                    if !etape.lieu.isEmpty {
                        Text(etape.lieu).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if etape.heure == nil, let fin = etape.heureFin {
                    Text("→ \(fin.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let heure = etape.heure {
                    if incoherence != nil || chevauche != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(chevauche != nil && incoherence == nil ? "Cette étape chevauche la précédente" : "Horaire incohérent avec l'ordre des étapes")
                            .help(chevauche != nil && incoherence == nil ? "Cette étape commence avant la fin de la précédente" : "Cette étape est prévue avant l'étape précédente")
                            .onTapGesture { avertissementOuvert = etape.uid }
                            .popover(isPresented: Binding(get: { avertissementOuvert == etape.uid },
                                                          set: { if !$0 { avertissementOuvert = nil } })) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(incoherence == nil ? "Horaires qui se chevauchent" : "Horaire incohérent", systemImage: "exclamationmark.triangle.fill")
                                        .font(.headline).foregroundStyle(.orange)
                                    if incoherence == nil, let autre = chevauche, let fin = autre.heureFin {
                                        Text("Cette étape commence à \(heure.formatted(date: .omitted, time: .shortened)), mais « \(autre.titre) » dure jusqu'à \(fin.formatted(date: .omitted, time: .shortened)). Change une des heures.")
                                            .font(.subheadline)
                                    } else if let incoherence {
                                    Text("Cette étape est prévue à \(heure.formatted(date: .omitted, time: .shortened)), mais elle est placée après une étape prévue à \(incoherence.formatted(date: .omitted, time: .shortened)). Change l'heure, ou son rang dans la journée.")
                                        .font(.subheadline)
                                    }
                                    Text("Le menu « ··· » du jour propose « Trier par heure ».")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding()
                                .frame(width: 320)
                                .fixedSize(horizontal: false, vertical: true)
                                .presentationCompactAdaptation(.popover)
                            }
                    }
                    Text(etape.heureFin.map { "\(heure.formatted(date: .omitted, time: .shortened)) – \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? heure.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(incoherence == nil && chevauche == nil ? Color.secondary : Color.orange)
                }
            }
            .contentShape(Rectangle())
        // Pas de Button : sur Mac, un bouton capte le clic et empêche de démarrer un glissé à la souris.
        .onTapGesture { etapeEnEdition = etape }
        .accessibilityAddTraits(.isButton)
    }

    private func premiereLettreEnMajuscule(_ texte: String) -> String {
        texte.prefix(1).uppercased() + texte.dropFirst()
    }

    // MARK: Création et nettoyage

    private func creerInfos(_ jour: Date) -> JourVoyage {
        let infos = JourVoyage(date: jour)
        infos.voyage = voyage
        contexte.insert(infos)
        return infos
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }

    private func nettoyerJours() {
        for infos in voyage.infosJours where infos.estVide { contexte.delete(infos) }
    }

    private func ajouter(le jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.ordre = voyage.prochainOrdre(du: jour)
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }
}

/// Fond arrondi d'une carte de jour.
struct FondDeCarte: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FondDePage.carte))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

enum FondDePage {
    static var couleur: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var carte: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
