import SwiftUI
import SwiftData

/// Onglet « Dépenses » : qui a payé quoi, les soldes de chacun et les remboursements pour s'équilibrer.
struct DepensesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var enEdition: Depense?
    @State private var moi: String
    @State private var nouveauVoyageur = ""

    init(voyage: Voyage) {
        self.voyage = voyage
        _moi = State(initialValue: UserDefaults.standard.string(forKey: "moi-\(voyage.uid)") ?? "")
    }

    private var membres: [Membre] { voyage.membres.sorted { $0.creeLe < $1.creeLe } }

    private func nom(_ uid: String) -> String {
        membres.first { $0.uid == uid }?.nom ?? "Ancien voyageur"
    }

    private var depensesTriees: [Depense] { voyage.depenses.sorted { ($0.date, $0.creeLe) > ($1.date, $1.creeLe) } }
    private var soldes: [String: [String: Double]] { voyage.soldesParCompte(moi: moi) }

    private func monnaie(_ montant: Double, _ devise: String) -> String {
        montant.formatted(.currency(code: devise))
    }

    var body: some View {
        List {
            if membres.count < 2 {
                Section {
                    ForEach(membres) { Label($0.nom, systemImage: "person.fill") }
                    HStack {
                        TextField("Prénom d'un voyageur", text: $nouveauVoyageur)
                            .onSubmit(ajouterVoyageur)
                            .autocorrectionDisabled()
                        Button("Ajouter", action: ajouterVoyageur)
                            .disabled(nouveauVoyageur.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Qui partage les frais ?")
                } footer: {
                    Text("Écris simplement les prénoms de ceux qui participent aux dépenses, toi compris : il n'est pas nécessaire de les inviter. Il en faut au moins deux pour répartir.")
                }
            } else {
                Section { SelecteurMoi(voyage: voyage, moi: $moi) }
                NouvelleDepenseSections(voyage: voyage, moi: moi)
                resume
                ForEach(soldes.keys.sorted(), id: \.self) { devise in
                    soldesEtVirements(devise: devise, soldes: soldes[devise] ?? [:])
                }
            }

            Section("Dépenses") {
                ForEach(depensesTriees) { d in
                    Button { enEdition = d } label: { ligne(d) }.buttonStyle(.plain)
                        .swipeActions { Button("Supprimer", role: .destructive) { contexte.delete(d) } }
                }
            }
        }
        .sheet(item: $enEdition, onDismiss: nettoyer) { d in
            DepenseEditView(depense: d, voyage: voyage, moi: moi) { contexte.delete(d) }
        }
    }

    // MARK: Résumé et soldes

    private var resume: some View {
        Section {
            ForEach(Comptes.totaux(voyage.depenses), id: \.devise) { total in
                LabeledContent("Total dépensé", value: monnaie(total.montant, total.devise))
            }
            if !moi.isEmpty {
                ForEach(soldes.keys.sorted(), id: \.self) { devise in
                    let solde = soldes[devise]?[voyage.representant(de: moi, moi: moi)] ?? 0
                    if abs(solde) >= 0.005 {
                        Label(solde > 0 ? "On te doit \(monnaie(solde, devise))" : "Tu dois \(monnaie(-solde, devise))",
                              systemImage: solde > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(solde > 0 ? .green : .red)
                            .font(.headline)
                    }
                }
            }
        } header: {
            Text("Résumé")
        }
    }

    @ViewBuilder
    private func soldesEtVirements(devise: String, soldes: [String: Double]) -> some View {
        Section {
            ForEach(soldes.sorted { $0.value > $1.value }, id: \.key) { uid, solde in
                HStack {
                    let estMoi = uid == voyage.representant(de: moi, moi: moi)
                    Text(estMoi ? "\(voyage.nomDuCompte(uid)) (toi)" : voyage.nomDuCompte(uid)).fontWeight(estMoi ? .semibold : .regular)
                    Spacer()
                    Text(abs(solde) < 0.005 ? "à l'équilibre" : (solde > 0 ? "doit recevoir " : "doit ") + monnaie(abs(solde), devise))
                        .foregroundStyle(abs(solde) < 0.005 ? Color.secondary : (solde > 0 ? .green : .red))
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Soldes · \(devise)")
        }

        let virements = Comptes.virements(soldes)
        if !virements.isEmpty {
            Section {
                ForEach(virements, id: \.self) { v in
                    HStack {
                        Text("\(voyage.nomDuCompte(v.de)) → \(voyage.nomDuCompte(v.vers))")
                        Spacer()
                        Text(monnaie(v.montant, devise)).monospacedDigit()
                        Button("Remboursé") { rembourser(v, devise: devise) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            } header: {
                Text("Pour s'équilibrer · \(devise)")
            } footer: {
                Text("Les membres d'une même famille sont solidaires : leurs comptes sont regroupés. « Remboursé » enregistre le paiement : les soldes sont remis à jour.")
            }
        }
    }

    private func ligne(_ d: Depense) -> some View {
        HStack(spacing: 12) {
            Image(systemName: d.estRemboursement ? "arrow.left.arrow.right.circle.fill" : d.categorie.symbole)
                .frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.titre.isEmpty ? (d.estRemboursement ? "Remboursement" : "Sans titre") : d.titre).font(.headline).foregroundStyle(.primary)
                Text(detail(d)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(monnaie(d.montant, d.devise)).monospacedDigit().foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }

    private func detail(_ d: Depense) -> String {
        let date = d.date.formatted(date: .abbreviated, time: .omitted)
        if d.estRemboursement, let part = d.parts.first {
            return "\(nom(d.payeurUID)) a remboursé \(nom(part.membreUID)) · \(date)"
        }
        let pour = d.parts.count == membres.count ? "tous" : "\(d.parts.count) pers."
        let famille = voyage.famille(de: d.payeurUID).map { " (\($0))" } ?? ""
        let etape = d.etapeUID.flatMap { uid in voyage.etapes.first { $0.uid == uid } }.map { " · \($0.titre)" } ?? ""
        return "Payé par \(nom(d.payeurUID))\(famille) · pour \(pour) · \(date)\(etape)"
    }

    // MARK: Actions

    private func ajouterVoyageur() {
        let nom = nouveauVoyageur.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        let membre = Membre(nom: nom)
        membre.voyage = voyage
        contexte.insert(membre)
        nouveauVoyageur = ""
    }

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
