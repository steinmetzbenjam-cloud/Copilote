import SwiftUI
import SwiftData

/// Onglet « Dépenses », à la manière de Tricount : la liste des dépenses jour par jour, puis les soldes et les remboursements.
/// Les membres d'une même famille sont solidaires : soldes et remboursements se font de famille à famille.
struct DepensesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var enEdition: Depense?
    @State private var moi: String
    @State private var nouveauVoyageur = ""
    @State private var declaration = false
    @State private var onglet = Onglet.depenses
    @State private var remboursements = false
    @State private var triParNom = false
    @State private var aSupprimer: Depense?

    private enum Onglet: String, CaseIterable, Identifiable {
        case depenses = "Dépenses", soldes = "Soldes"
        var id: String { rawValue }
    }

    init(voyage: Voyage) {
        self.voyage = voyage
        _moi = State(initialValue: UserDefaults.standard.string(forKey: "moi-\(voyage.uid)") ?? "")
    }

    private var membres: [Membre] { voyage.membresTries }
    private var depensesTriees: [Depense] { voyage.depenses.sorted { ($0.date, $0.creeLe) > ($1.date, $1.creeLe) } }
    private var soldes: [String: [String: Double]] { voyage.soldesParCompte(moi: moi) }
    private var devises: [String] { soldes.keys.sorted() }
    /// Le compte (famille ou voyageur seul) qui porte mes comptes.
    private var monCompte: String? { moi.isEmpty ? nil : voyage.representant(de: moi, moi: moi) }

    private func monnaie(_ montant: Double, _ devise: String) -> String {
        montant.formatted(.currency(code: devise))
    }

    /// Prénom d'un voyageur, suivi de « (moi) » si c'est moi.
    private func nom(_ uid: String) -> String {
        let nom = voyage.membre(uid: uid)?.nom ?? "Ancien voyageur"
        return uid == moi ? "\(nom) (moi)" : nom
    }

    /// Nom d'un compte, suivi de « (moi) » si c'est le mien.
    private func nomCompte(_ uid: String) -> String {
        uid == monCompte ? "\(voyage.nomDuCompte(uid)) (moi)" : voyage.nomDuCompte(uid)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Vue", selection: $onglet) {
                ForEach(Onglet.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal).padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 10) {
                    if membres.count < 2 { voyageurs }
                    switch onglet {
                    case .depenses: listeDepenses
                    case .soldes: vueSoldes
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if onglet == .depenses && membres.count >= 2 && !voyage.lectureSeule { boutonAjouter }
        }
        .confirmerSuppression($aSupprimer, titre: { "Supprimer « \($0.titre.isEmpty ? "cette dépense" : $0.titre) » ?" }) { contexte.delete($0) }
        .sheet(isPresented: $declaration) { DepenseAssistantView(voyage: voyage, moi: moi) }
        .sheet(item: $enEdition, onDismiss: nettoyer) { d in
            DepenseEditView(depense: d, voyage: voyage, moi: moi) { contexte.delete(d) }
        }
        .sheet(isPresented: $remboursements) {
            RemboursementsView(voyage: voyage, moi: moi, enregistrer: rembourser)
        }
    }

    // MARK: Voyageurs

    /// Tant qu'il n'y a pas deux voyageurs, on commence par les ajouter.
    private var voyageurs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qui partage les frais ?").font(.headline)
            ForEach(membres) { Label($0.nom, systemImage: "person.fill") }
            HStack {
                TextField("Prénom d'un voyageur", text: $nouveauVoyageur)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(ajouterVoyageur)
                    .autocorrectionDisabled()
                Button("Ajouter", action: ajouterVoyageur)
                    .disabled(nouveauVoyageur.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Écris simplement les prénoms de ceux qui participent aux dépenses et ne sont pas encore listés : il n'est pas nécessaire de les inviter. Il en faut au moins deux pour répartir. Ils rejoignent aussi la liste des voyageurs de l'onglet Infos.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .background(fond, in: RoundedRectangle(cornerRadius: 20))
        .padding(.top, 6)
    }

    // MARK: Dépenses

    @ViewBuilder private var listeDepenses: some View {
        enTete
        if depensesTriees.isEmpty {
            VStack(spacing: 8) {
                IconeLiasse().frame(width: 70, height: 70)
                Text("Aucune dépense pour l'instant").font(.headline)
                Text(membres.count < 2 ? "Ajoute d'abord au moins deux voyageurs ci-dessus pour partager les frais."
                                       : "Ajoute la première avec le bouton ci-dessous.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        } else {
            ForEach(jours, id: \.jour) { groupe in
                Text(titreJour(groupe.jour))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                ForEach(groupe.depenses) { d in
                    Button { enEdition = d } label: { ligne(d) }
                        .buttonStyle(.plain)
                        .contextMenu { if !voyage.lectureSeule { Button("Supprimer", systemImage: "trash", role: .destructive) { aSupprimer = d } } }
                }
            }
        }
    }

    /// « Mes dépenses » (ma part, celle de ma famille) et « Dépenses totales ».
    private var enTete: some View {
        HStack {
            if let monCompte {
                chiffre("Mes dépenses", maPart(monCompte))
            }
            chiffre("Dépenses totales", Comptes.totaux(voyage.depenses).map { monnaie($0.montant, $0.devise) })
        }
        .padding(.vertical, 8)
    }

    private func chiffre(_ titre: String, _ montants: [String]) -> some View {
        VStack(spacing: 2) {
            Text(titre).font(.subheadline).foregroundStyle(.secondary)
            Text(montants.isEmpty ? monnaie(0, voyage.deviseLocale ?? "EUR") : montants.joined(separator: " + "))
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// Ce qui revient à ma famille dans les dépenses (remboursements exclus), devise par devise.
    private func maPart(_ compte: String) -> [String] {
        var parts: [String: Double] = [:]
        for d in voyage.depenses where !d.estRemboursement {
            for part in d.parts where voyage.representant(de: part.membreUID, moi: moi) == compte { parts[d.devise, default: 0] += part.montant }
        }
        return parts.sorted { $0.key < $1.key }.map { monnaie($0.value, $0.key) }
    }

    private var jours: [(jour: Date, depenses: [Depense])] {
        let calendrier = Calendar.current
        return Dictionary(grouping: depensesTriees) { calendrier.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { ($0.date, $0.creeLe) > ($1.date, $1.creeLe) }) }
            .sorted { $0.0 > $1.0 }
    }

    private func titreJour(_ jour: Date) -> String {
        if Calendar.current.isDateInToday(jour) { return "aujourd'hui" }
        if Calendar.current.isDateInYesterday(jour) { return "hier" }
        return jour.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func ligne(_ d: Depense) -> some View {
        let couleur = d.estRemboursement ? Color.green : d.categorie.couleurTicket
        return HStack(spacing: 14) {
            Image(systemName: d.estRemboursement ? "arrow.left.arrow.right" : d.categorie.symbole)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(couleur)
                .frame(width: 40, height: 40)
                .background(couleur.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(d.titre.isEmpty ? (d.estRemboursement ? "Remboursement" : "Sans titre") : d.titre)
                    .font(.body).foregroundStyle(.primary).lineLimit(1)
                sousTitre(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(monnaie(d.montant, d.devise)).font(.body.weight(.semibold)).monospacedDigit()
                if d.devise != "EUR", let euros = voyage.eurosDeDepense(d) {
                    Text("≈ \(Monnaies.formater(euros, "EUR"))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(fond, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    private func sousTitre(_ d: Depense) -> Text {
        if d.estRemboursement, let part = d.parts.first {
            return Text("\(Text(voyage.nomDuCompte(voyage.representant(de: d.payeurUID, moi: moi))).bold()) a remboursé \(Text(voyage.nomDuCompte(voyage.representant(de: part.membreUID, moi: moi))).bold())")
        }
        return Text("Payé par \(Text(nom(d.payeurUID)).bold())")
    }

    private var boutonAjouter: some View {
        Button { declaration = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Text("Ajouter\nune dépense")
                    .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    // MARK: Soldes

    @ViewBuilder private var vueSoldes: some View {
        if let monCompte {
            ForEach(devises, id: \.self) { devise in
                carteMonSolde(soldes[devise]?[monCompte] ?? 0, devise: devise, compte: monCompte)
            }
        }
        Button { remboursements = true } label: {
            Text("Voir tous les remboursements proposés")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(fond, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)

        ForEach(devises, id: \.self) { devise in
            HStack {
                Text(devises.count > 1 ? "Équilibres · \(devise)" : "Équilibres").font(.headline)
                Spacer()
                Button { withAnimation { triParNom.toggle() } } label: {
                    Image(systemName: triParNom ? "textformat" : "arrow.up.arrow.down")
                        .font(.headline)
                }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                .help(triParNom ? "Trié par nom" : "Trié par montant")
            }
            .padding(.top, 18)
            ForEach(comptesTries(soldes[devise] ?? [:]), id: \.key) { uid, solde in
                ligneSolde(uid: uid, solde: solde, devise: devise)
            }
        }
        Text("Les membres d'une même famille sont solidaires : leurs dépenses et leurs remboursements sont regroupés.")
            .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
    }

    private func carteMonSolde(_ solde: Double, devise: String, compte: String) -> some View {
        let virements = Comptes.virements(soldes[devise] ?? [:])
        let equilibre = abs(solde) < 0.005
        let autres = solde > 0 ? virements.filter { $0.vers == compte }.map { voyage.nomDuCompte($0.de) }
                               : virements.filter { $0.de == compte }.map { voyage.nomDuCompte($0.vers) }
        let liste = autres.count > 1 ? autres.dropLast().joined(separator: ", ") + " et " + autres.last! : autres.first ?? ""
        return Button { remboursements = true } label: {
            HStack(spacing: 14) {
                Text(equilibre ? "😌" : (solde > 0 ? "🤑" : "💸")).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(equilibre ? "Tu es à l'équilibre" : (solde > 0 ? "On te doit \(monnaie(solde, devise))" : "Tu dois \(monnaie(-solde, devise))"))
                        .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text(equilibre ? "Tu ne dois rien et on ne te doit rien"
                         : solde > 0 ? "Vois comment \(liste) \(autres.count > 1 ? "doivent" : "doit") te rembourser"
                         : "Vois comment rembourser \(liste)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(fond, in: RoundedRectangle(cornerRadius: 26))
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private func comptesTries(_ soldes: [String: Double]) -> [(key: String, value: Double)] {
        soldes.sorted { a, b in
            if a.key == monCompte { return true }
            if b.key == monCompte { return false }
            return triParNom ? voyage.nomDuCompte(a.key).localizedCompare(voyage.nomDuCompte(b.key)) == .orderedAscending : a.value > b.value
        }
    }

    private func ligneSolde(uid: String, solde: Double, devise: String) -> some View {
        let membre = voyage.membre(uid: uid)
        let famille = membre?.famille ?? ""
        let composants = famille.isEmpty ? [] : membres.filter { $0.famille.caseInsensitiveCompare(famille) == .orderedSame }.map(\.nom)
        let detail = [uid == monCompte ? "Moi" : nil, composants.isEmpty ? nil : composants.joined(separator: ", ")].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            if !famille.isEmpty {
                VignetteFamille(photo: voyage.photo(famille: famille), nom: famille, taille: 44)
            } else {
                AvatarView(initiales: Profil.initiales(de: membre?.nom ?? "?"), donnees: membre?.avatar, taille: 44,
                           couleur: AvatarView.couleur(pour: uid))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(voyage.nomDuCompte(uid)).font(.title3)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Text(abs(solde) < 0.005 ? monnaie(0, devise) : (solde > 0 ? "+" : "-") + monnaie(abs(solde), devise))
                .font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(abs(solde) < 0.005 ? Color.secondary : (solde > 0 ? .green : .red))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(fond, in: RoundedRectangle(cornerRadius: 26))
    }

    private var fond: Color { Color.secondary.opacity(0.12) }

    // MARK: Actions

    private func ajouterVoyageur() {
        let nom = nouveauVoyageur.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        let membre = Membre(nom: nom)
        membre.voyage = voyage
        contexte.insert(membre)
        nouveauVoyageur = ""
    }

    /// Enregistre un remboursement d'une famille à une autre : les soldes sont remis à jour.
    private func rembourser(_ v: Comptes.Virement, devise: String) {
        let d = Depense(devise: devise, payeurUID: v.de)
        d.estRemboursement = true
        d.titre = "Remboursement"
        d.montant = v.montant
        d.categorie = .autre
        d.parts = [PartDepense(membreUID: v.vers, montant: v.montant)]
        d.voyage = voyage
        contexte.insert(d)
    }

    /// Une dépense créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for d in voyage.depenses where d.estVide && !d.estRemboursement { contexte.delete(d) }
    }
}

/// Les remboursements proposés pour remettre tout le monde à zéro : d'abord ceux qui me concernent, puis les autres.
private struct RemboursementsView: View {
    var voyage: Voyage
    var moi: String
    var enregistrer: (Comptes.Virement, String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var monCompte: String? { moi.isEmpty ? nil : voyage.representant(de: moi, moi: moi) }
    private var soldes: [String: [String: Double]] { voyage.soldesParCompte(moi: moi) }

    private func monnaie(_ montant: Double, _ devise: String) -> String { montant.formatted(.currency(code: devise)) }

    private func nomCompte(_ uid: String) -> String {
        uid == monCompte ? "\(voyage.nomDuCompte(uid)) (moi)" : voyage.nomDuCompte(uid)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    let devises = soldes.keys.sorted()
                    let tous = devises.flatMap { devise in Comptes.virements(soldes[devise] ?? [:]).map { (devise: devise, virement: $0) } }
                    if tous.isEmpty {
                        VStack(spacing: 8) {
                            Text("🎉").font(.system(size: 54))
                            Text("Tout le monde est à l'équilibre").font(.title3.weight(.semibold))
                            Text("Aucun remboursement n'est nécessaire.").foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else {
                        if let monCompte {
                            ForEach(devises, id: \.self) { devise in
                                let solde = soldes[devise]?[monCompte] ?? 0
                                if abs(solde) >= 0.005 { enTete(solde, devise: devise) }
                            }
                        }
                        let miens = tous.filter { $0.virement.de == monCompte || $0.virement.vers == monCompte }
                        let autres = tous.filter { $0.virement.de != monCompte && $0.virement.vers != monCompte }
                        ForEach(miens, id: \.virement) { carte($0.virement, devise: $0.devise) }
                        if !autres.isEmpty {
                            if !miens.isEmpty {
                                Text("Autres").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                            }
                            ForEach(autres, id: \.virement) { carte($0.virement, devise: $0.devise) }
                        }
                        Text("Les familles sont solidaires : chaque remboursement se fait d'une famille à l'autre, peu importe qui paie.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 8)
                    }
                }
                .frame(maxWidth: 560)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Remboursements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func enTete(_ solde: Double, devise: String) -> some View {
        VStack(spacing: 6) {
            Text(solde > 0 ? "On te doit" : "Tu dois").font(.title3.weight(.semibold))
            Text(monnaie(abs(solde), devise))
                .font(.title.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(Capsule().fill(solde > 0 ? Color.green : Color.red))
        }
        .padding(.bottom, 10)
    }

    private func carte(_ v: Comptes.Virement, devise: String) -> some View {
        let jeRecois = v.vers == monCompte
        return VStack(spacing: 10) {
            Text("\(Text(nomCompte(v.de)).bold()) \(Text("doit à").font(.subheadline).foregroundStyle(.secondary)) \(Text(nomCompte(v.vers)).bold())")
                .font(.headline).multilineTextAlignment(.center)
            Text(monnaie(v.montant, devise)).font(.title.weight(.semibold)).monospacedDigit()
            HStack(spacing: 10) {
                if jeRecois {
                    ShareLink(item: demande(v, devise: devise)) {
                        Text("Demande").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Button { enregistrer(v, devise) } label: {
                    Text("C'est payé !").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(Color.accentColor).background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(voyage.lectureSeule)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    /// Le message envoyé pour demander un remboursement.
    private func demande(_ v: Comptes.Virement, devise: String) -> String {
        let voyageNom = voyage.titre.isEmpty ? "notre voyage" : "« \(voyage.titre) »"
        return "Bonjour \(voyage.nomDuCompte(v.de)) ! D'après les comptes de \(voyageNom) dans Copilote, tu dois \(monnaie(v.montant, devise)) à \(voyage.nomDuCompte(v.vers)). Merci 🙂"
    }
}
