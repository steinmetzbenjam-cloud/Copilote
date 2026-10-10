import SwiftUI
import SwiftData

/// Votes du groupe : plusieurs options, une voix par famille, puis l'option retenue.
struct VotesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var edition: EditionSondage?
    /// Étape (ou logement) d'une option, ouverte en entier pour la regarder de près.
    @State private var etapeOuverte: Etape?

    private struct EditionSondage: Identifiable {
        let id = UUID()
        var sondage: Sondage?
    }

    private var moi: String { MoiVoyage.lire(voyage) }
    private var sondages: [Sondage] {
        voyage.sondages.sorted { ($0.clos ? 1 : 0, $1.creeLe) < ($1.clos ? 1 : 0, $0.creeLe) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Button { edition = EditionSondage(sondage: nil) } label: {
                    Label("Lancer un vote", systemImage: "plus.circle.fill").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(voyage.lectureSeule || voyage.membres.isEmpty)

                if sondages.isEmpty {
                    ContentUnavailableView("Aucun vote", systemImage: "hand.thumbsup",
                                           description: Text("Propose deux restaurants ou deux excursions : chaque famille donne sa voix, l'app compte."))
                        .padding(.top, 20)
                }
                ForEach(sondages) { carte($0) }
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
        .sheet(item: $edition) { PropositionEditView(voyage: voyage, sondage: $0.sondage) }
        .sheet(item: $etapeOuverte) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
    }

    // MARK: Carte d'un vote

    private func carte(_ sondage: Sondage) -> some View {
        let unites = voyage.unitesDepense(moi: moi)
        let votes = voyage.votes(de: sondage)
        let maCle = moi.isEmpty ? "" : voyage.cleCompte(de: moi)
        let monVote = votes.first { $0.compteCle == maCle }
        let options = sondage.options
        let decompte = Dictionary(grouping: votes, by: \.optionID).mapValues(\.count)
        let maximum = decompte.values.max() ?? 0
        let teinte: Color = sondage.clos ? .gray : .purple
        let peutGerer = voyage.estOrganisateur || sondage.auteurUID == moi

        return CadreInfos(titre: sondage.titre.isEmpty ? "Vote" : sondage.titre, symbole: sondage.clos ? "checkmark.seal.fill" : "hand.thumbsup.fill",
                          couleur: teinte) {
            if !sondage.notes.isEmpty { Text(sondage.notes).font(.footnote).foregroundStyle(.secondary) }
            ForEach(options) { option in
                ligne(option, sondage: sondage, unites: unites, votes: votes, monVote: monVote?.optionID == option.id,
                      nombre: decompte[option.id] ?? 0, maximum: maximum)
            }
            HStack {
                Text("\(votes.count) sur \(unites.count) famille\(unites.count > 1 ? "s" : "") ont voté")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if sondage.clos { PastilleClos() }
            }
            // Ceux qui n'ont pas encore donné leur voix.
            let absents = unites.filter { u in !votes.contains { $0.compteCle == u.id } }
            if !absents.isEmpty, !sondage.clos {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "hourglass").foregroundStyle(.orange)
                    Text("Pas encore voté : " + absents.map(\.nom).joined(separator: ", "))
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            if peutGerer { actions(sondage, options: options, decompte: decompte) }
        }
    }

    private func ligne(_ option: OptionSondage, sondage: Sondage, unites: [UniteDepense], votes: [VoteSondage],
                       monVote: Bool, nombre: Int, maximum: Int) -> some View {
        let retenue = sondage.optionRetenue == option.id
        let electeurs = unites.filter { u in votes.contains { $0.optionID == option.id && $0.compteCle == cle(de: u) } }
        return VStack(alignment: .leading, spacing: 8) {
            // Le haut de la carte vote (ou retire ma voix).
            Button {
                guard !voyage.lectureSeule, !moi.isEmpty else { return }
                voyage.voter(option, dans: sondage, par: moi, contexte: contexte)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: monVote ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(monVote ? Color.purple : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                // Option liée à une étape ou un logement du voyage : son icône.
                                if let e = voyage.etape(de: option) {
                                    Image(systemName: e.categorie.symbole).font(.caption).foregroundStyle(.purple)
                                }
                                Text(option.titre).fontWeight(.semibold).foregroundStyle(.primary)
                            }
                            if !option.detail.isEmpty { Text(option.detail).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if retenue { Label("Retenue", systemImage: "star.fill").font(.caption.bold()).foregroundStyle(.orange) }
                        Text("\(nombre)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.primary)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(retenue ? Color.orange : Color.purple)
                                .frame(width: maximum > 0 ? g.size.width * Double(nombre) / Double(max(unites.count, 1)) : 0)
                        }
                    }
                    .frame(height: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(sondage.clos)

            // Étape ou logement du voyage : tout son détail en un clic, même une fois le vote clos.
            if let e = voyage.etape(de: option) {
                Button { etapeOuverte = e } label: {
                    Label(e.categorie == .hebergement ? "Voir tout le détail du logement" : "Voir tout le détail de l'étape", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            // Qui a voté pour cette option : la famille, la personne qui a voté pour elle, et quand.
            if !electeurs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(electeurs) { u in
                        let vote = votes.first { $0.optionID == option.id && $0.compteCle == cle(de: u) }
                        HStack(spacing: 8) {
                            VignetteFamille(photo: u.photo, nom: u.nom, taille: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(u.nom).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                if let vote {
                                    let auteur = voyage.membre(uid: vote.auteurUID)?.nom
                                    Text([u.membres.count > 1 ? auteur.map { "voté par \($0)" } : nil,
                                          vote.modifieLe.formatted(.relative(presentation: .named))]
                                            .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if u.membres.count > 1 {
                                Text("\(u.membres.count) pers.").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(monVote ? Color.purple.opacity(0.12) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(monVote ? Color.purple : .clear, lineWidth: 2))
    }

    /// La clé de compte d'une unité (famille ou voyageur seul), pour retrouver ses voix.
    private func cle(de unite: UniteDepense) -> String { unite.id }

    private func actions(_ sondage: Sondage, options: [OptionSondage], decompte: [String: Int]) -> some View {
        HStack(spacing: 14) {
            if sondage.clos {
                Button("Rouvrir", systemImage: "arrow.uturn.backward") { sondage.clos = false; sondage.optionRetenue = nil }
                // Une option libre retenue peut devenir une étape ; une option liée est déjà une étape du voyage.
                if let id = sondage.optionRetenue, let option = options.first(where: { $0.id == id }), voyage.etape(de: option) == nil {
                    Button("Créer l'étape", systemImage: "mappin.and.ellipse") { creerEtape(option, sondage) }
                }
            } else {
                Button("Clore le vote", systemImage: "checkmark.seal") {
                    let tete = options.max { (decompte[$0.id] ?? 0) < (decompte[$1.id] ?? 0) }
                    sondage.optionRetenue = (decompte.values.max() ?? 0) > 0 ? tete?.id : nil
                    sondage.clos = true
                }
                Button("Modifier", systemImage: "pencil") { edition = EditionSondage(sondage: sondage) }
            }
            Spacer()
            Button("Supprimer", systemImage: "trash", role: .destructive) { voyage.supprimer(sondage, contexte: contexte) }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }

    /// L'option retenue devient une étape à placer dans l'itinéraire.
    private func creerEtape(_ option: OptionSondage, _ sondage: Sondage) {
        let etape = Etape(titre: option.titre, jour: nil, categorie: .visite)
        etape.notes = [option.detail, "Retenu par vote : \(sondage.titre)"].filter { !$0.isEmpty }.joined(separator: "\n")
        etape.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
    }
}

private struct PastilleClos: View {
    var body: some View {
        Label("Clos", systemImage: "lock.fill").font(.caption2.weight(.semibold)).foregroundStyle(.gray)
            .padding(.horizontal, 7).padding(.vertical, 3).background(Color.gray.opacity(0.15), in: Capsule())
    }
}

/// Création ou modification d'un vote : une question et au moins deux options.
struct PropositionEditView: View {
    var voyage: Voyage
    var sondage: Sondage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var titre = ""
    @State private var notes = ""
    @State private var options: [OptionSondage] = [OptionSondage(), OptionSondage()]

    private var valides: [OptionSondage] { options.filter { !$0.titre.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var ok: Bool { !titre.trimmingCharacters(in: .whitespaces).isEmpty && valides.count >= 2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sur quoi voter ? (ex. Dîner du samedi)", text: $titre)
                    TextField("Précisions (facultatif)", text: $notes, axis: .vertical).lineLimit(1...4)
                }
                Section {
                    ForEach($options) { $option in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Option", text: $option.titre)
                                menuEtape($option)
                            }
                            TextField("Détail : adresse, prix… (facultatif)", text: $option.detail).font(.footnote).foregroundStyle(.secondary)
                            if let e = option.etapeUID.flatMap({ uid in voyage.etapes.first { $0.uid == uid } }) {
                                Label(e.categorie == .hebergement ? "Logement du voyage" : "Étape du voyage", systemImage: e.categorie.symbole)
                                    .font(.caption).foregroundStyle(.purple)
                            }
                        }
                    }
                    .onDelete { options.remove(atOffsets: $0) }
                    Button("Ajouter une option", systemImage: "plus.circle") { options.append(OptionSondage()) }
                } header: {
                    Text("Options")
                } footer: {
                    Text("Il en faut au moins deux. Chaque famille a une voix. Le bouton à droite d'une option y met une étape ou un logement du voyage, pour comparer deux étapes prévues au même moment ou deux logements.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(sondage == nil ? "Nouveau vote" : "Modifier le vote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(sondage == nil ? "Lancer" : "Enregistrer", action: enregistrer).disabled(!ok) }
            }
            .onAppear {
                guard let sondage else { return }
                titre = sondage.titre; notes = sondage.notes; options = sondage.options
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// Étapes et logements du voyage, dans l'ordre des jours (puis ceux à placer).
    private var etapesTriees: [Etape] {
        voyage.etapes.filter { !$0.titre.isEmpty }.sorted { ($0.jour ?? .distantFuture, $0.ordre) < ($1.jour ?? .distantFuture, $1.ordre) }
    }

    /// « Jour 3 · 10:00 · Adresse » : de quoi comparer les options d'un coup d'œil.
    private func resume(_ e: Etape) -> String {
        var morceaux: [String] = []
        if let jour = e.jour, let i = voyage.jours.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: jour) }) {
            morceaux.append(e.apresJour ? "Nuit du jour \(i + 1)" : "Jour \(i + 1)")
        }
        if let h = e.heure { morceaux.append(e.heureAffichee(h)) }
        if !e.lieu.isEmpty { morceaux.append(e.lieu) }
        if let budget = e.resumeBudget { morceaux.append(budget) }
        return morceaux.joined(separator: " · ")
    }

    /// Mettre une étape ou un logement du voyage dans l'option (ou l'en retirer).
    private func menuEtape(_ option: Binding<OptionSondage>) -> some View {
        Menu {
            Section("Logements") {
                ForEach(etapesTriees.filter { $0.categorie == .hebergement }) { e in
                    Button(e.titre, systemImage: e.categorie.symbole) { lier(option, e) }
                }
            }
            Section("Étapes") {
                ForEach(etapesTriees.filter { $0.categorie != .hebergement }) { e in
                    Button(e.titre, systemImage: e.categorie.symbole) { lier(option, e) }
                }
            }
            if option.wrappedValue.etapeUID != nil {
                Button("Retirer le lien", systemImage: "link.badge.minus", role: .destructive) { option.wrappedValue.etapeUID = nil }
            }
        } label: {
            Image(systemName: option.wrappedValue.etapeUID == nil ? "mappin.and.ellipse" : "link")
                .foregroundStyle(option.wrappedValue.etapeUID == nil ? Color.secondary : Color.purple)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choisir une étape ou un logement du voyage")
    }

    private func lier(_ option: Binding<OptionSondage>, _ e: Etape) {
        option.wrappedValue.etapeUID = e.uid
        option.wrappedValue.titre = e.titre
        option.wrappedValue.detail = resume(e)
    }

    private func enregistrer() {
        let cible = sondage ?? {
            let nouveau = Sondage(titre: "", auteurUID: MoiVoyage.lire(voyage))
            nouveau.voyage = voyage
            contexte.insert(nouveau)
            return nouveau
        }()
        cible.titre = titre.trimmingCharacters(in: .whitespaces)
        cible.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        cible.options = valides.map { OptionSondage(id: $0.id, titre: $0.titre.trimmingCharacters(in: .whitespaces), detail: $0.detail, etapeUID: $0.etapeUID) }
        dismiss()
    }
}
