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
            ForEach(voyage.etapesSansJour) { ligneDansCadre($0, couleur: .gray) }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter() }
                .buttonStyle(.borderless).font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    /// Un jour, même sans étape : ses étapes, les transports entre elles et un bouton pour en ajouter.
    private func carteJour(numero: Int, jour: Date) -> some View {
        let etapes = voyage.etapes(du: jour)
        let couleur = CarteDuVoyage.couleur(du: numero - 1)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(couleur)
                Text(jour.formatted(.dateTime.weekday(.wide).day().month(.wide)).prefix(1).uppercased()
                     + jour.formatted(.dateTime.weekday(.wide).day().month(.wide)).dropFirst())
                    .font(.title3.bold())
            }
            Divider()
            if etapes.isEmpty {
                Text("Aucune étape ce jour-là.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(etapes) { etape in
                ligneDansCadre(etape, couleur: couleur)
                if let suivante = voyage.suivante(de: etape) { ligneTransport(etape, suivante) }
            }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(jour: jour) }
                .buttonStyle(.borderless).tint(couleur).font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    /// Bande entre deux jours : les hébergements de la nuit, ou un bouton pour en ajouter un.
    private func carteNuit(apres jour: Date) -> some View {
        let nuits = voyage.hebergements(apres: jour)
        return VStack(alignment: .leading, spacing: 8) {
            if !nuits.isEmpty {
                Label(self.nuits(jour), systemImage: "moon.zzz.fill").font(.caption.bold()).foregroundStyle(Self.couleurNuit)
            }
            ForEach(nuits) { h in
                ligneDansCadre(h, couleur: Self.couleurNuit)
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
    }

    /// Une étape dans un cadre : fond teinté de la couleur du jour.
    private func ligneDansCadre(_ etape: Etape, couleur: Color) -> some View {
        ligne(etape)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(couleur.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            libelleLieu: extremite == .aller ? "Lieu de départ" : "Lieu d'arrivée",
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

    private func ligne(_ etape: Etape) -> some View {
        HStack(spacing: 12) {
            Image(systemName: etape.categorie.symbole).frame(width: 24).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).foregroundStyle(.primary)
                if !etape.lieu.isEmpty {
                    Text(etape.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let heure = etape.heure {
                Text(heure.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Préparation seulement : le groupe donne son avis sur l'étape.
            if voyage.mode == .preparation, !etape.titre.isEmpty {
                PastilleAvis(voyage: voyage, etape: etape) { avisOuvert = etape }
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
