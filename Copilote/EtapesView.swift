import SwiftUI
import SwiftData
import CoreLocation

/// Onglet « Étapes » : toutes les étapes du voyage. On peut en préparer sans savoir quel jour elles auront lieu.
struct EtapesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?
    @State private var transportEnEdition: PaireEtapes?
    @State private var transportExtremiteEnEdition: Extremite?

    /// Transport avant la première étape (aller) ou après la dernière (retour).
    enum Extremite: String, Identifiable {
        case aller, retour
        var id: String { rawValue }
    }
    @State private var avisOuvert: Etape?
    /// Glisser-déposer : étape au-dessus de laquelle on s'apprête à lâcher (trait), et zone survolée.
    @State private var etapeVisee: String?
    @State private var zoneVisee: String?
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

    struct PaireEtapes: Identifiable {
        let depart: Etape, arrivee: Etape
        var id: String { depart.uid }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                carteAPlacer
                if let premiere = voyage.elementsDuVoyage.first {
                    ligneExtremite(.aller, etape: premiere)
                }
                ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                    carteJour(numero: index + 1, jour: jour)
                    carteNuit(apres: jour)
                }
                if let derniere = voyage.elementsDuVoyage.last {
                    ligneExtremite(.retour, etape: derniere)
                }
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
        .confirmationDialog("Effacer le transport ?", isPresented: Binding(get: { deplacementEnAttente != nil }, set: { if !$0 { deplacementEnAttente = nil } }), titleVisibility: .visible, presenting: deplacementEnAttente) { d in
            Button("Déplacer et effacer le transport", role: .destructive) { appliquer(d) }
            Button("Annuler", role: .cancel) {}
        } message: { d in
            Text(d.perdus.count == 1 ? "Ce déplacement efface le transport prévu après « \(d.perdus[0].titre) »." : "Ce déplacement efface \(d.perdus.count) transports prévus entre des étapes.")
        }
        .sheet(item: $transportExtremiteEnEdition) { transportExtremite($0) }
        .sheet(item: $transportEnEdition) { TransportEditView(depart: $0.depart, arrivee: $0.arrivee) }
        .sheet(item: $avisOuvert) { AvisEtapeView(voyage: voyage, etape: $0) }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
    }

    /// Entre deux étapes : le transport prévu, ou un bouton pour en ajouter un.
    /// Les lignes de transport se distinguent des étapes par leur couleur.
    private static let couleurTransport = Color.indigo

    private func ligneTransport(_ depart: Etape, _ arrivee: Etape) -> some View {
        Button { transportEnEdition = PaireEtapes(depart: depart, arrivee: arrivee) } label: {
            HStack(spacing: 8) {
                if let t = depart.transport {
                    Image(systemName: t.mode.symbole).frame(width: 24)
                    Text(descriptif(t))
                    if t.mode.aUnItineraire, let a = depart.coordonnee, let b = arrivee.coordonnee {
                        Spacer()
                        ResumeItineraire(a: a, b: b, mode: t.mode)
                    }
                } else {
                    Image(systemName: "plus.circle").frame(width: 24)
                    Text("Ajouter un transport")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Self.couleurTransport)
            .padding(.leading, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Self.couleurTransport.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Étapes préparées sans jour.
    private var carteAPlacer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("À placer", systemImage: "tray.full").font(.headline)
            if voyage.etapesSansJour.isEmpty {
                Text("Aucune étape en attente. Prépare ici des idées, tu les glisseras ensuite sur un jour dans l'itinéraire.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(voyage.etapesSansJour) { ligneGlissable($0, jour: nil, couleur: .gray) }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter() }
                .buttonStyle(.borderless).font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
        .overlay { surbrillance("placer", couleur: .accentColor) }
        .dropDestination(for: String.self) { elements, _ in
            recevoir(elements, jour: nil, avant: nil)
        } isTargeted: { visee in
            zoneVisee = visee ? "placer" : (zoneVisee == "placer" ? nil : zoneVisee)
        }
    }

    /// Un jour, même sans étape : ses étapes, les transports entre elles et un bouton pour en ajouter.
    private func carteJour(numero: Int, jour: Date) -> some View {
        let etapes = voyage.etapes(du: jour)
        let couleur = CarteDuVoyage.couleur(du: numero - 1)
        return VStack(alignment: .leading, spacing: 8) {
            // Bandeau du jour : numéro et date en blanc sur la couleur du jour.
            VStack(alignment: .leading, spacing: 2) {
                Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(.white.opacity(0.85))
                Text(jour.formatted(.dateTime.weekday(.wide).day().month(.wide)).prefix(1).uppercased()
                     + jour.formatted(.dateTime.weekday(.wide).day().month(.wide)).dropFirst())
                    .font(.title3.bold()).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(couleur, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if etapes.isEmpty {
                Text("Aucune étape ce jour-là.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(etapes) { etape in
                ligneGlissable(etape, jour: jour, couleur: couleur)
                if let suivante = voyage.suivante(de: etape) { ligneTransport(etape, suivante) }
            }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(jour: jour) }
                .buttonStyle(.borderless).tint(couleur).font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
        .overlay { surbrillance(idZone("jour", jour), couleur: couleur) }
        .dropDestination(for: String.self) { elements, _ in
            recevoir(elements, jour: jour, avant: nil)
        } isTargeted: { visee in
            let id = idZone("jour", jour)
            zoneVisee = visee ? id : (zoneVisee == id ? nil : zoneVisee)
        }
    }

    /// Bande entre deux jours : les hébergements de la nuit, ou un bouton pour en ajouter un.
    private func carteNuit(apres jour: Date) -> some View {
        let nuits = voyage.hebergements(apres: jour)
        return VStack(alignment: .leading, spacing: 8) {
            if !nuits.isEmpty {
                Label(self.nuits(jour), systemImage: "moon.zzz.fill").font(.caption.bold()).foregroundStyle(Self.couleurNuit)
            }
            ForEach(nuits) { h in
                ligneGlissable(h, jour: nil, couleur: Self.couleurNuit, deposable: false)
                if let suivante = voyage.suivante(de: h) { ligneTransport(h, suivante) }
            }
            if nuits.isEmpty {
                Button("Ajouter un hébergement", systemImage: "plus.circle.fill") { ajouterHebergement(apres: jour) }
                    .buttonStyle(.borderless).tint(Self.couleurNuit).font(.footnote)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.couleurNuit.opacity(0.22))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Self.couleurNuit.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: nuits.isEmpty ? [5, 4] : [])))
        .overlay { surbrillance(idZone("nuit", jour), couleur: Self.couleurNuit) }
        // Seuls les hébergements se posent dans une nuit.
        .dropDestination(for: String.self) { elements, _ in
            recevoir(elements, jour: jour, avant: nil, nuit: true)
        } isTargeted: { visee in
            let id = idZone("nuit", jour)
            zoneVisee = visee ? id : (zoneVisee == id ? nil : zoneVisee)
        }
    }

    /// Une étape dans un cadre (fond teinté de la couleur du jour) que l'on peut glisser ailleurs.
    /// `deposable` : on peut aussi lâcher une autre étape juste au-dessus d'elle.
    private func ligneGlissable(_ etape: Etape, jour: Date?, couleur: Color, deposable: Bool = true) -> some View {
        let contenu = ligne(etape)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(couleur.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .draggable(Self.prefixe + etape.uid) {
                Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        return Group {
            if deposable {
                contenu
                    .overlay(alignment: .top) {
                        if etapeVisee == etape.uid { Capsule().fill(.tint).frame(height: 3).offset(y: -5) }
                    }
                    .dropDestination(for: String.self) { elements, _ in
                        recevoir(elements, jour: jour, avant: etape)
                    } isTargeted: { visee in
                        if visee { etapeVisee = etape.uid } else if etapeVisee == etape.uid { etapeVisee = nil }
                    }
            } else {
                contenu
            }
        }
    }

    // MARK: Glisser-déposer

    private static let prefixe = "copilote-etape:"

    private func idZone(_ type: String, _ jour: Date) -> String { "\(type)-\(jour.timeIntervalSince1970)" }

    @ViewBuilder private func surbrillance(_ id: String, couleur: Color) -> some View {
        if zoneVisee == id {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2)
        }
    }

    /// `jour` nil : la zone « À placer ». `nuit` : on ne reçoit qu'un hébergement, posé entre `jour` et le suivant.
    private func recevoir(_ elements: [String], jour: Date?, avant cible: Etape?, nuit: Bool = false) -> Bool {
        defer { etapeVisee = nil; zoneVisee = nil }
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count),
              let etape = voyage.etapes.first(where: { $0.uid == String(uid) }) else { return false }
        if nuit {
            guard etape.categorie == .hebergement, let jour else { return false }
            return demanderNuit(etape, apres: jour)
        }
        // Un hébergement lâché sur un jour va à la fin de ce jour, entre lui et le suivant.
        if let jour, etape.categorie == .hebergement { return demanderNuit(etape, apres: jour) }
        return demander(etape, vers: jour, avant: cible)
    }

    /// Déplace tout de suite, ou demande confirmation si des transports entre étapes seraient effacés.
    private func demander(_ etape: Etape, vers jour: Date?, avant cible: Etape?) -> Bool {
        if cible === etape { return false }
        let perdus = voyage.transportsPerdus(deplacant: etape, vers: jour, avant: cible)
        let d = DeplacementEnAttente(etape: etape, jour: jour, cible: cible, perdus: perdus)
        if perdus.isEmpty { return appliquer(d) }
        deplacementEnAttente = d
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
            return placerSansJour(d.etape, avant: d.cible)
        }
    }

    /// Range l'étape dans « À placer », juste avant `cible` ou à la fin.
    private func placerSansJour(_ etape: Etape, avant cible: Etape?) -> Bool {
        _ = voyage.retirerDuJour(etape)
        var liste = voyage.etapesSansJour.filter { $0 !== etape }
        let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
        liste.insert(etape, at: index)
        for (i, e) in liste.enumerated() { e.ordre = Double(i) }
        return true
    }

    /// Ligne de transport avant le premier jour ou après le dernier.
    @ViewBuilder private func ligneExtremite(_ extremite: Extremite, etape: Etape) -> some View {
        let t = extremite == .aller ? voyage.transportAller : voyage.transportRetour
        Button { transportExtremiteEnEdition = extremite } label: {
            HStack(spacing: 8) {
                if let t {
                    Image(systemName: t.mode.symbole).frame(width: 24)
                    Text((extremite == .aller ? "Aller · " : "Retour · ") + descriptif(t))
                } else {
                    Image(systemName: "plus.circle").frame(width: 24)
                    Text(extremite == .aller ? "Ajouter un transport avant le premier jour" : "Ajouter un transport après le dernier jour")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Self.couleurTransport)
            .padding(.leading, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Self.couleurTransport.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func transportExtremite(_ extremite: Extremite) -> some View {
        let elements = voyage.elementsDuVoyage
        let etape = extremite == .aller ? elements.first : elements.last
        let nom = etape.map { $0.titre.isEmpty ? "Étape" : $0.titre } ?? "Étape"
        let jours = voyage.jours
        return TransportEditView(
            trajet: extremite == .aller ? "Départ → \(nom)" : "\(nom) → Retour",
            jour: (extremite == .aller ? jours.first : jours.last) ?? .now,
            coordonnees: nil,
            existant: extremite == .aller ? voyage.transportAller : voyage.transportRetour,
            lieuxExtremites: true,
            enregistrer: { nouveau in
                if extremite == .aller { voyage.transportAller = nouveau } else { voyage.transportRetour = nouveau }
            })
    }

    private func descriptif(_ t: Transport) -> String {
        var morceaux = [t.mode.libelle]
        if t.mode == .commun, !t.sousType.isEmpty { morceaux = [t.sousType] }
        let ligne = [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " ")
        if !ligne.isEmpty { morceaux.append(ligne) }
        if let d = t.depart {
            morceaux.append(d.formatted(date: .omitted, time: .shortened) + (t.arrivee.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
        }
        return morceaux.joined(separator: " · ")
    }

    /// La photo déjà enregistrée dans l'étape, sinon l'icône de sa catégorie. Rien n'est téléchargé ici (pas d'appel à Google ni Tripadvisor).
    @ViewBuilder private func vignette(_ etape: Etape) -> some View {
        let formats: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "gif"]
        let photo = etape.photos.sorted { $0.nom < $1.nom }.first { formats.contains($0.extensionFichier.lowercased()) }
        if let photo {
            ImageDonnees(donnees: photo.donnees)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: etape.categorie.symbole).frame(width: 24).foregroundStyle(Color.accentColor)
        }
    }

    /// À droite de l'étape : le jugement de chacun, « Prénom · étoiles · intérêt · remarque ».
    /// Toucher ce bloc ouvre la fenêtre pour donner (ou modifier) son propre avis.
    @ViewBuilder private func avisDuGroupe(_ etape: Etape) -> some View {
        let avis = voyage.avis(de: etape).sorted { voyage.nomMembre($0.auteurUID) < voyage.nomMembre($1.auteurUID) }
        Button { avisOuvert = etape } label: {
            if avis.isEmpty {
                Label("Donner un avis", systemImage: "star")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(avis) { a in
                        HStack(spacing: 5) {
                            Text(voyage.membre(uid: a.auteurUID)?.nom ?? "Quelqu'un").fontWeight(.semibold)
                            if a.etoiles > 0 {
                                HStack(spacing: 1) {
                                    Text("\(a.etoiles)")
                                    Image(systemName: "star.fill")
                                }
                                .foregroundStyle(.orange)
                            }
                            Label(a.envie.libelle, systemImage: a.envie.symbole)
                                .labelStyle(.titleAndIcon).foregroundStyle(a.envie.couleur)
                            if !a.commentaire.isEmpty {
                                Text(a.commentaire).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .font(.caption2)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Avis du groupe sur \(etape.titre)")
    }

    private func ligne(_ etape: Etape) -> some View {
        HStack(spacing: 12) {
            vignette(etape)
            VStack(alignment: .leading, spacing: 2) {
                Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).foregroundStyle(.primary)
                if !etape.lieu.isEmpty {
                    Text(etape.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let budget = etape.resumeBudget {
                    Label(budget, systemImage: "eurosign.circle").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let heure = etape.heure {
                Text(heure.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Préparation seulement : le groupe donne son avis sur l'étape.
            if voyage.mode == .preparation, !etape.titre.isEmpty {
                avisDuGroupe(etape)
            }
        }
        .contentShape(Rectangle())
        // Pas de Button autour de la ligne : il avalerait le bouton d'avis.
        .onTapGesture { etapeEnEdition = etape }
        .accessibilityAddTraits(.isButton)
    }

    private static let couleurNuit = Color.mint

    private func nuits(_ jour: Date) -> String {
        let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
        return "Nuit du \(jour.formatted(.dateTime.day().month(.abbreviated))) au \(lendemain.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func ajouterHebergement(apres jour: Date) {
        let etape = Etape(titre: "", jour: jour, categorie: .hebergement)
        etape.apresJour = true
        etape.ordre = (voyage.hebergements(apres: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    private func ajouter(jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.ordre = (voyage.etapes(du: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    private func ajouter() {
        let etape = Etape(titre: "", jour: nil)
        etape.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }
}

private struct ResumeItineraire: View {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D
    let mode: ModeTransport
    @State private var itineraires = Itineraires.shared

    var body: some View {
        Text(itineraires.trajet(a, b, mode)?.resume ?? "…")
            .font(.caption).foregroundStyle(.secondary)
            .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
    }
}
