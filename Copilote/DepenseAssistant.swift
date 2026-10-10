import SwiftUI
import SwiftData

/// Déclarer une dépense en trois fenêtres qui défilent : qui paie et pour qui, quoi et quand, puis combien et comment répartir.
struct DepenseAssistantView: View {
    var voyage: Voyage
    var moi: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte

    private enum Repartition: String, CaseIterable, Identifiable {
        case famille = "Par famille", personne = "Par personne", precis = "Précis"
        var id: String { rawValue }
    }

    @State private var page = 0
    @State private var avance = true
    @State private var payeur: String
    @State private var choixPayeur = false
    @State private var selection: Set<String> = []
    @State private var titre = ""
    @State private var date = Date.now
    @State private var categorie = CategorieDepense.autre
    @State private var etapeUID = ""
    @State private var montantTexte = ""
    @State private var devise: String
    @State private var repartition = Repartition.famille
    @State private var montantsUnite: [String: String] = [:]

    init(voyage: Voyage, moi: String) {
        self.voyage = voyage
        self.moi = moi
        _payeur = State(initialValue: moi.isEmpty ? (voyage.membresTries.first?.uid ?? "") : moi)
        _devise = State(initialValue: voyage.deviseLocale.flatMap { $0.isEmpty ? nil : $0 } ?? "EUR")
        let unites = voyage.unitesDepense(moi: moi, premier: moi.isEmpty ? voyage.membresTries.first?.uid : moi)
        _selection = State(initialValue: Set(unites.first.map { [$0.id] } ?? []))
    }

    // MARK: Données

    private var unites: [UniteDepense] { voyage.unitesDepense(moi: moi, premier: payeur) }
    private var choisies: [UniteDepense] { unites.filter { selection.contains($0.id) } }
    private var uniteDuPayeur: UniteDepense? { unites.first { $0.membres.contains { $0.uid == payeur } } }
    private var tousSelectionnes: Bool { !unites.isEmpty && unites.allSatisfy { selection.contains($0.id) } }

    private func nombre(_ texte: String) -> Double { Double(texte.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var montant: Double { nombre(montantTexte) }
    private var devises: [String] { voyage.codesMonnaies }
    private var sommePrecise: Double { choisies.reduce(0) { $0 + nombre(montantsUnite[$1.id] ?? "") } }
    private var ecart: Double { ((montant - sommePrecise) * 100).rounded() / 100 }

    /// Ce que chaque famille (ou voyageur seul) paie.
    private var partsParUnite: [(unite: UniteDepense, montant: Double)] {
        let u = choisies
        guard !u.isEmpty else { return [] }
        switch repartition {
        case .famille:
            return zip(u, Comptes.repartir(montant, entre: u.map(\.id))).map { ($0, $1.montant) }
        case .personne:
            let parts = Dictionary(uniqueKeysWithValues: Comptes.repartir(montant, entre: u.flatMap { $0.membres.map(\.uid) }).map { ($0.membreUID, $0.montant) })
            return u.map { unite in (unite, unite.membres.reduce(0) { $0 + (parts[$1.uid] ?? 0) }) }
        case .precis:
            return u.map { ($0, nombre(montantsUnite[$0.id] ?? "")) }
        }
    }

    /// Les parts de chaque voyageur : la part d'une famille est partagée à égalité entre ses membres.
    private var parts: [PartDepense] {
        if repartition == .personne { return Comptes.repartir(montant, entre: choisies.flatMap { $0.membres.map(\.uid) }) }
        return partsParUnite.flatMap { Comptes.repartir($0.montant, entre: $0.unite.membres.map(\.uid)) }
    }

    private var valide: Bool {
        montant > 0 && !choisies.isEmpty && !payeur.isEmpty && (repartition != .precis || abs(ecart) < 0.005)
    }

    private var peutAvancer: Bool { page == 0 ? (!payeur.isEmpty && !choisies.isEmpty) : true }

    private var etapes: [Etape] {
        voyage.etapes.sorted { ($0.jour ?? .distantFuture, $0.ordre, $0.creeLe) < ($1.jour ?? .distantFuture, $1.ordre, $1.creeLe) }
    }

    private let titres = ["Qui paie, et pour qui ?", "Quelle dépense ?", "Combien, et comment répartir ?"]

    // MARK: Corps

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { Capsule().fill($0 <= page ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4) }
                    }
                    Text(titres[page]).font(.title3.weight(.semibold))
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)

                ZStack {
                    Group {
                        switch page {
                        case 0: pagePersonnes
                        case 1: pageDetails
                        default: pagePrix
                        }
                    }
                    .id(page)
                    .transition(.asymmetric(insertion: .move(edge: avance ? .trailing : .leading),
                                            removal: .move(edge: avance ? .leading : .trailing)))
                }
                .clipped()

                barreBoutons
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .sheet(isPresented: $choixPayeur) {
                ChoixMembreView(voyage: voyage, titre: "Qui paie ?", choisi: payeur) { membre in
                    payeur = membre.uid
                    // La famille de celui qui paie est cochée d'office.
                    selection = Set(voyage.unitesDepense(moi: moi, premier: membre.uid).first.map { [$0.id] } ?? [])
                    choixPayeur = false
                } fermer: { choixPayeur = false }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private var barreBoutons: some View {
        HStack {
            if page > 0 {
                Button("Retour", systemImage: "chevron.left") { aller(page - 1) }
            }
            Spacer()
            if page < 2 {
                Button { aller(page + 1) } label: { Label("Suivant", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderedProminent).disabled(!peutAvancer)
            } else {
                Button("Enregistrer", systemImage: "checkmark", action: enregistrer)
                    .buttonStyle(.borderedProminent).disabled(!valide)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private func aller(_ nouvelle: Int) {
        avance = nouvelle > page
        withAnimation(.snappy) { page = nouvelle }
    }

    // MARK: Page 1 : qui paie, pour qui

    private var pagePersonnes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Button { choixPayeur = true } label: {
                        VStack(spacing: 6) {
                            if let membre = voyage.membre(uid: payeur) {
                                RondMembre(membre: membre, voyage: voyage, taille: 72)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.system(size: 22))
                                            .foregroundStyle(.white, Color.accentColor).offset(x: 4, y: 4)
                                    }
                                Text(membre.nom).font(.footnote.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                            }
                            Text("Celui qui paie").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 92)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Qui paie ? Toucher pour changer")

                    Image(systemName: "hand.point.right.fill").font(.system(size: 26)).foregroundStyle(.secondary).padding(.top, 22)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            if let mienne = uniteDuPayeur { vignette(mienne, titre: mienne.membres.count > 1 ? "Sa famille" : "Lui-même") }
                            Button { selection = tousSelectionnes ? Set(uniteDuPayeur.map { [$0.id] } ?? []) : Set(unites.map(\.id)) } label: {
                                tuile(selectionnee: tousSelectionnes) {
                                    Image(systemName: "person.3.fill").font(.system(size: 24)).foregroundStyle(.white)
                                        .frame(width: 56, height: 56).background(Circle().fill(Color.teal))
                                } nom: { "Tout le monde" }
                            }
                            .buttonStyle(.plain)
                            ForEach(unites.filter { $0.id != uniteDuPayeur?.id }) { vignette($0, titre: $0.nom) }
                        }
                        .padding(.vertical, 4).padding(.horizontal, 4)
                    }
                }
                Text("Touche le rond de gauche pour changer la personne qui paie. Touche une famille pour l'inclure ou l'exclure de la dépense.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func vignette(_ unite: UniteDepense, titre: String) -> some View {
        Button {
            if selection.contains(unite.id) { selection.remove(unite.id) } else { selection.insert(unite.id) }
        } label: {
            tuile(selectionnee: selection.contains(unite.id)) {
                VignetteFamille(photo: unite.photo, nom: unite.nom, taille: 56)
            } nom: { unite.membres.count > 1 && titre != unite.nom ? "\(titre)\n\(unite.nom)" : titre }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unite.nom)
        .accessibilityAddTraits(selection.contains(unite.id) ? .isSelected : [])
    }

    /// Un rond avec son nom dessous ; sélectionné, il est surligné et porte une coche.
    private func tuile<Rond: View>(selectionnee: Bool, @ViewBuilder rond: () -> Rond, nom: () -> String) -> some View {
        VStack(spacing: 6) {
            rond()
                .overlay(alignment: .topTrailing) {
                    if selectionnee {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                            .foregroundStyle(.white, Color.accentColor).offset(x: 4, y: -4)
                    }
                }
            Text(nom()).font(.footnote.weight(selectionnee ? .semibold : .regular)).lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selectionnee ? Color.accentColor.opacity(0.16) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(selectionnee ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selectionnee ? 2 : 1))
        .contentShape(Rectangle())
    }

    // MARK: Page 2 : quoi et quand

    private var pageDetails: some View {
        Form {
            Section {
                TextField("Qu'est-ce qui a été payé ?", text: $titre)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Type", selection: $categorie) {
                    ForEach(CategorieDepense.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                }
                Picker("Étape", selection: $etapeUID) {
                    Text("Aucune").tag("")
                    ForEach(etapes) { Text($0.titre.isEmpty ? $0.categorie.libelle : $0.titre).tag($0.uid) }
                }
            } footer: {
                Text("L'étape est facultative : elle sert à retrouver à quoi se rapporte la dépense.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Page 3 : combien

    private var pagePrix: some View {
        Form {
            Section {
                LabeledContent("Prix") {
                    HStack(spacing: 6) {
                        TextField("", text: $montantTexte)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(Self.sigle(devise)).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .leading)
                    }
                }
                if devises.count > 1 {
                    Picker("Monnaie", selection: $devise) {
                        ForEach(devises, id: \.self) { Text($0 == "EUR" ? "Euros (€)" : Monnaies.libelle($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if devise != "EUR", let euros = voyage.versEuros(montant, code: devise), montant > 0 {
                        Text("≈ \(Monnaies.formater(euros, "EUR"))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Picker("Répartition", selection: $repartition) {
                    ForEach(Repartition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(partsParUnite, id: \.unite.id) { ligne in
                    HStack {
                        VignetteFamille(photo: ligne.unite.photo, nom: ligne.unite.nom, taille: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ligne.unite.nom)
                            if ligne.unite.membres.count > 1 {
                                Text("\(ligne.unite.membres.count) personnes").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if repartition == .precis {
                            TextField("", text: Binding(get: { montantsUnite[ligne.unite.id] ?? "" }, set: { montantsUnite[ligne.unite.id] = $0 }))
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing).frame(width: 90)
                        } else {
                            Text(Monnaies.formater(ligne.montant, devise)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Comment répartir ?")
            } footer: {
                switch repartition {
                case .famille: Text("Le prix est divisé par le nombre de familles ; chaque famille partage sa part entre ses membres.")
                case .personne: Text("Le prix est divisé par le nombre de personnes des familles choisies.")
                case .precis:
                    Text(abs(ecart) < 0.005 ? "Le total est bon." : "Il reste \(Monnaies.formater(ecart, devise)) à répartir.")
                        .foregroundStyle(abs(ecart) < 0.005 ? Color.secondary : .orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Le signe de la monnaie : « € » pour l'euro, sinon son symbole ou son code.
    private static func sigle(_ code: String) -> String {
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.locale = Locale(identifier: "fr_FR")
        format.currencyCode = code
        return format.currencySymbol ?? code
    }

    // MARK: Enregistrement

    private func enregistrer() {
        let depense = Depense(devise: devise, payeurUID: payeur, date: date)
        depense.titre = titre.trimmingCharacters(in: .whitespaces)
        depense.montant = montant
        depense.categorie = categorie
        depense.etapeUID = etapeUID.isEmpty ? nil : etapeUID
        depense.repartitionPrecise = repartition == .precis
        depense.parts = parts
        depense.voyage = voyage
        contexte.insert(depense)
        dismiss()
    }
}
