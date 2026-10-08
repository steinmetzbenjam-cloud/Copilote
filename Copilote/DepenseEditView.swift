import SwiftUI
import SwiftData

struct DepenseEditView: View {
    @Bindable var depense: Depense
    var voyage: Voyage
    var moi: String
    var onSupprimer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var participants: Set<String> = []
    @State private var montantsPrecis: [String: String] = [:]
    @State private var precise = false
    @State private var montantTexte = ""
    @FocusState private var titreActif: Bool

    private var membres: [Membre] { voyage.membres.sorted { $0.creeLe < $1.creeLe } }

    private var devisesProposees: [String] {
        var liste = voyage.pays.compactMap { Locale(identifier: "und_\($0)").currency?.identifier }
        liste += ["EUR", "USD", "GBP", "CHF"]
        var vues = Set<String>()
        return liste.filter { vues.insert($0).inserted }
    }

    private var sommePrecise: Double {
        membres.filter { participants.contains($0.uid) }
            .reduce(0) { $0 + (Double((montantsPrecis[$1.uid] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0) }
    }

    private var ecart: Double { ((depense.montant - sommePrecise) * 100).rounded() / 100 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Qu'est-ce qui a été payé ?", text: $depense.titre).focused($titreActif)
                    HStack {
                        TextField("Montant", text: $montantTexte)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .onChange(of: montantTexte) { depense.montant = Double(montantTexte.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                        TextField("Devise", text: $depense.devise)
                            .textCase(.uppercase).autocorrectionDisabled()
                            .frame(width: 64).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                        Menu {
                            ForEach(devisesProposees, id: \.self) { code in Button(code) { depense.devise = code } }
                        } label: { Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary) }
                    }
                    Picker("Catégorie", selection: $depense.categorie) {
                        ForEach(CategorieDepense.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                    }
                    DatePicker("Date", selection: $depense.date, displayedComponents: .date)
                    Picker("Étape", selection: Binding(get: { depense.etapeUID ?? "" }, set: { depense.etapeUID = $0.isEmpty ? nil : $0 })) {
                        Text("Aucune").tag("")
                        ForEach(voyage.etapes.sorted { ($0.jour ?? .distantFuture, $0.ordre) < ($1.jour ?? .distantFuture, $1.ordre) }) {
                            Text($0.titre.isEmpty ? $0.categorie.libelle : $0.titre).tag($0.uid)
                        }
                    }
                }

                Section("Payé par") {
                    Picker("Payeur", selection: $depense.payeurUID) {
                        ForEach(membres) { Text($0.nom).tag($0.uid) }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Picker("Répartition", selection: $precise) {
                        Text("Parts égales").tag(false)
                        Text("Montants précis").tag(true)
                    }
                    .pickerStyle(.segmented)

                    ForEach(membres) { m in
                        HStack {
                            Toggle(m.nom, isOn: Binding(
                                get: { participants.contains(m.uid) },
                                set: { if $0 { participants.insert(m.uid) } else { participants.remove(m.uid) } }))
                            if precise && participants.contains(m.uid) {
                                TextField("0", text: Binding(get: { montantsPrecis[m.uid] ?? "" }, set: { montantsPrecis[m.uid] = $0 }))
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .multilineTextAlignment(.trailing).frame(width: 80)
                            }
                        }
                    }
                } header: {
                    Text("Pour qui ?")
                } footer: {
                    if precise {
                        Text(abs(ecart) < 0.005 ? "Le total est bon."
                             : "Il reste \(ecart.formatted(.currency(code: depense.devise))) à répartir.")
                            .foregroundStyle(abs(ecart) < 0.005 ? Color.secondary : .orange)
                    } else if !participants.isEmpty, depense.montant > 0 {
                        Text("Environ \((depense.montant / Double(participants.count)).formatted(.currency(code: depense.devise))) par personne.")
                    }
                }

                Section("Notes") { TextEditor(text: $depense.notes).frame(minHeight: 60) }

                Section {
                    Button("Supprimer la dépense", role: .destructive) { onSupprimer(); dismiss() }
                }
            }
            .formStyle(.grouped)
            .disabled(voyage.lectureSeule)
            .navigationTitle("Dépense")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onAppear(perform: charger)
            .onDisappear(perform: enregistrer)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    private func charger() {
        precise = depense.repartitionPrecise
        participants = depense.parts.isEmpty ? Set(membres.map(\.uid)) : Set(depense.parts.map(\.membreUID))
        for part in depense.parts { montantsPrecis[part.membreUID] = part.montant.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        if depense.montant > 0 { montantTexte = depense.montant.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        if depense.titre.isEmpty { titreActif = true }
    }

    /// Calcule les parts de chacun à la fermeture, et retient la devise pour la prochaine dépense.
    private func enregistrer() {
        let choisis = membres.map(\.uid).filter { participants.contains($0) }
        depense.devise = depense.devise.trimmingCharacters(in: .whitespaces).uppercased()
        if depense.devise.isEmpty { depense.devise = "EUR" }
        UserDefaults.standard.set(depense.devise, forKey: "derniereDevise")
        depense.repartitionPrecise = precise
        if precise {
            depense.parts = choisis.map { uid in
                PartDepense(membreUID: uid, montant: Double((montantsPrecis[uid] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0)
            }
        } else {
            depense.parts = Comptes.repartir(depense.montant, entre: choisis)
        }
    }
}
