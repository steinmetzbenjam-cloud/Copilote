import SwiftUI
import SwiftData

/// Votes du groupe : plusieurs options, une voix par famille, puis l'option retenue.
struct VotesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var edition: EditionSondage?

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
            if peutGerer { actions(sondage, options: options, decompte: decompte) }
        }
    }

    private func ligne(_ option: OptionSondage, sondage: Sondage, unites: [UniteDepense], votes: [VoteSondage],
                       monVote: Bool, nombre: Int, maximum: Int) -> some View {
        let retenue = sondage.optionRetenue == option.id
        let electeurs = unites.filter { u in votes.contains { $0.optionID == option.id && $0.compteCle == cle(de: u) } }
        return Button {
            guard !voyage.lectureSeule, !moi.isEmpty else { return }
            voyage.voter(option, dans: sondage, par: moi, contexte: contexte)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: monVote ? "checkmark.circle.fill" : "circle").font(.title3)
                        .foregroundStyle(monVote ? Color.purple : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.titre).fontWeight(.semibold).foregroundStyle(.primary)
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
                if !electeurs.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(electeurs) { u in
                            VignetteFamille(photo: u.photo, nom: u.nom, taille: 24).overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        }
                        Text(electeurs.map(\.nom).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).padding(.leading, 12).lineLimit(1)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(monVote ? Color.purple.opacity(0.12) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(monVote ? Color.purple : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sondage.clos)
    }

    /// La clé de compte d'une unité (famille ou voyageur seul), pour retrouver ses voix.
    private func cle(de unite: UniteDepense) -> String { unite.id }

    private func actions(_ sondage: Sondage, options: [OptionSondage], decompte: [String: Int]) -> some View {
        HStack(spacing: 14) {
            if sondage.clos {
                Button("Rouvrir", systemImage: "arrow.uturn.backward") { sondage.clos = false; sondage.optionRetenue = nil }
                if let id = sondage.optionRetenue, let option = options.first(where: { $0.id == id }) {
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
                            TextField("Option", text: $option.titre)
                            TextField("Détail : adresse, prix… (facultatif)", text: $option.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { options.remove(atOffsets: $0) }
                    Button("Ajouter une option", systemImage: "plus.circle") { options.append(OptionSondage()) }
                } header: {
                    Text("Options")
                } footer: {
                    Text("Il en faut au moins deux. Chaque famille a une voix.")
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

    private func enregistrer() {
        let cible = sondage ?? {
            let nouveau = Sondage(titre: "", auteurUID: MoiVoyage.lire(voyage))
            nouveau.voyage = voyage
            contexte.insert(nouveau)
            return nouveau
        }()
        cible.titre = titre.trimmingCharacters(in: .whitespaces)
        cible.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        cible.options = valides.map { OptionSondage(id: $0.id, titre: $0.titre.trimmingCharacters(in: .whitespaces), detail: $0.detail) }
        dismiss()
    }
}
