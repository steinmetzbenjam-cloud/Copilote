import SwiftUI
import SwiftData

/// Le rond d'un voyageur : sa photo, sinon ses initiales. Pour moi, c'est la photo de mon profil.
struct RondMembre: View {
    var membre: Membre
    var voyage: Voyage
    var taille: CGFloat = 40

    var body: some View {
        let moi = membre.uid == MoiVoyage.lire(voyage)
        AvatarView(initiales: Profil.initiales(de: membre.nom), donnees: moi ? (Profil.partage.avatar ?? membre.avatar) : membre.avatar,
                   taille: taille, couleur: moi ? .accentColor : AvatarView.couleur(pour: membre.uid))
    }
}

/// « Qui es-tu ? » : mon rond, et un choix parmi les ronds de tous les voyageurs pour en changer.
struct SelecteurMoi: View {
    var voyage: Voyage
    @Binding var moi: String
    @State private var ouvert = false

    var body: some View {
        Button { ouvert = true } label: {
            HStack(spacing: 14) {
                if let membre = voyage.membre(uid: moi) {
                    RondMembre(membre: membre, voyage: voyage, taille: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(membre.nom).font(.headline).foregroundStyle(.primary)
                        Text(voyage.famille(de: membre.uid) ?? "Sans famille").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Circle().fill(.quaternary).frame(width: 56, height: 56)
                        .overlay(Image(systemName: "questionmark").foregroundStyle(.secondary))
                    Text("Qui es-tu ?").font(.headline).foregroundStyle(.primary)
                }
                Spacer()
                Label("Changer", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $ouvert) { choix }
    }

    private var choix: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 16)], spacing: 18) {
                    ForEach(voyage.membresTries) { membre in
                        Button {
                            moi = membre.uid
                            MoiVoyage.ecrire(membre.uid, voyage)
                            ouvert = false
                        } label: {
                            VStack(spacing: 6) {
                                RondMembre(membre: membre, voyage: voyage, taille: 64)
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: membre.uid == moi ? 3 : 0).padding(-3))
                                Text(membre.nom).font(.footnote).foregroundStyle(.primary).lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Qui es-tu ?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { ouvert = false } } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// Ce qui partage une dépense : une famille, ou un voyageur sans famille.
struct UniteDepense: Identifiable {
    let id: String
    let nom: String
    let photo: Data?
    let membres: [Membre]
}

extension Voyage {
    /// Les familles et les voyageurs seuls ; celle de `moi` en premier.
    @MainActor func unitesDepense(moi: String) -> [UniteDepense] {
        var unites = familles.map { UniteDepense(id: "f:" + $0.nom.lowercased(), nom: $0.nom, photo: photo(famille: $0.nom), membres: $0.membres) }
        unites += membresSansFamille.map {
            UniteDepense(id: "m:" + $0.uid, nom: $0.nom, photo: $0.uid == moi ? (Profil.partage.avatar ?? $0.avatar) : $0.avatar, membres: [$0])
        }
        if let i = unites.firstIndex(where: { $0.membres.contains { $0.uid == moi } }) { unites.insert(unites.remove(at: i), at: 0) }
        return unites
    }
}

/// Saisie d'une nouvelle dépense : pour qui, quoi, combien, et comment répartir entre les familles.
struct NouvelleDepenseSections: View {
    var voyage: Voyage
    var moi: String
    @Environment(\.modelContext) private var contexte

    private enum Repartition: String, CaseIterable, Identifiable {
        case famille = "Par famille", personne = "Par personne", precis = "Précis"
        var id: String { rawValue }
    }

    @State private var selection: Set<String> = []
    @State private var titre = ""
    @State private var date = Date.now
    @State private var categorie = CategorieDepense.autre
    @State private var etapeUID = ""
    @State private var montantTexte = ""
    @State private var devise = ""
    @State private var repartition = Repartition.famille
    @State private var montantsUnite: [String: String] = [:]
    @State private var initialisee = false

    private var unites: [UniteDepense] { voyage.unitesDepense(moi: moi) }
    private var choisies: [UniteDepense] { unites.filter { selection.contains($0.id) } }
    private var monUnite: UniteDepense? { unites.first { $0.membres.contains { $0.uid == moi } } }
    private var tousSelectionnes: Bool { !unites.isEmpty && unites.allSatisfy { selection.contains($0.id) } }

    private func nombre(_ texte: String) -> Double { Double(texte.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var montant: Double { nombre(montantTexte) }

    private var devises: [String] { ["EUR"] + [voyage.deviseLocale].compactMap { $0 }.filter { !$0.isEmpty && $0 != "EUR" } }

    private var sommePrecise: Double { choisies.reduce(0) { $0 + nombre(montantsUnite[$1.id] ?? "") } }
    private var ecart: Double { ((montant - sommePrecise) * 100).rounded() / 100 }

    /// Ce que chaque famille (ou voyageur seul) paie.
    private var partsParUnite: [(unite: UniteDepense, montant: Double)] {
        let u = choisies
        guard !u.isEmpty else { return [] }
        switch repartition {
        case .famille:
            let parts = Comptes.repartir(montant, entre: u.map(\.id))
            return zip(u, parts).map { ($0, $1.montant) }
        case .personne:
            let tous = u.flatMap { $0.membres.map(\.uid) }
            let parts = Dictionary(uniqueKeysWithValues: Comptes.repartir(montant, entre: tous).map { ($0.membreUID, $0.montant) })
            return u.map { unite in (unite, unite.membres.reduce(0) { $0 + (parts[$1.uid] ?? 0) }) }
        case .precis:
            return u.map { ($0, nombre(montantsUnite[$0.id] ?? "")) }
        }
    }

    /// Les parts de chaque voyageur : la part d'une famille est partagée à égalité entre ses membres.
    private var parts: [PartDepense] {
        if repartition == .personne {
            return Comptes.repartir(montant, entre: choisies.flatMap { $0.membres.map(\.uid) })
        }
        return partsParUnite.flatMap { Comptes.repartir($0.montant, entre: $0.unite.membres.map(\.uid)) }
    }

    private var valide: Bool {
        montant > 0 && !choisies.isEmpty && !moi.isEmpty && (repartition != .precis || abs(ecart) < 0.005)
    }

    private var etapes: [Etape] {
        voyage.etapes.sorted { ($0.jour ?? .distantFuture, $0.ordre, $0.creeLe) < ($1.jour ?? .distantFuture, $1.ordre, $1.creeLe) }
    }

    var body: some View {
        Group {
            pourQui
            details
            repartir
        }
        .onAppear(perform: initialiser)
        .onChange(of: moi) { reinitialiserSelection() }
    }

    // MARK: Pour qui ?

    private var pourQui: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    if let mienne = monUnite { vignette(mienne, titre: mienne.membres.count > 1 ? "Ma famille" : "Moi") }
                    Button { selection = tousSelectionnes ? Set(monUnite.map { [$0.id] } ?? []) : Set(unites.map(\.id)) } label: {
                        tuile(selectionnee: tousSelectionnes) {
                            Image(systemName: "person.3.fill").font(.system(size: 24)).foregroundStyle(.white)
                                .frame(width: 56, height: 56).background(Circle().fill(Color.teal))
                        } nom: { "Tout le monde" }
                    }
                    .buttonStyle(.plain)
                    ForEach(unites.filter { $0.id != monUnite?.id }) { vignette($0, titre: $0.nom) }
                }
                .padding(.vertical, 6).padding(.horizontal, 4)
            }
        } header: {
            Text("Pour qui ?")
        } footer: {
            Text("Touche une famille pour l'inclure ou l'exclure de la dépense.")
        }
    }

    private func vignette(_ unite: UniteDepense, titre: String) -> some View {
        Button {
            if selection.contains(unite.id) { selection.remove(unite.id) } else { selection.insert(unite.id) }
        } label: {
            tuile(selectionnee: selection.contains(unite.id)) {
                VignetteFamille(photo: unite.photo, nom: unite.nom, taille: 56)
            } nom: { titre }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titre)
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
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selectionnee ? Color.accentColor : Color.secondary.opacity(0.25),
                                                                               lineWidth: selectionnee ? 2 : 1))
        .contentShape(Rectangle())
    }

    // MARK: Détails

    private var details: some View {
        Section("Nouvelle dépense") {
            TextField("Qu'est-ce qui a été payé ?", text: $titre)
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Picker("Type", selection: $categorie) {
                ForEach(CategorieDepense.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
            }
            Picker("Étape", selection: $etapeUID) {
                Text("Aucune").tag("")
                ForEach(etapes) { Text($0.titre.isEmpty ? $0.categorie.libelle : $0.titre).tag($0.uid) }
            }
            LabeledContent("Prix") {
                TextField("0", text: $montantTexte)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
            if devises.count > 1 {
                Picker("Monnaie", selection: $devise) {
                    ForEach(devises, id: \.self) { Text($0 == "EUR" ? "Euros (€)" : Monnaies.libelle($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                if devise != "EUR", let euros = voyage.versEuros(montant), montant > 0 {
                    Text("≈ \(Monnaies.formater(euros, "EUR"))").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Répartition

    private var repartir: some View {
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
                        TextField("0", text: Binding(get: { montantsUnite[ligne.unite.id] ?? "" }, set: { montantsUnite[ligne.unite.id] = $0 }))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing).frame(width: 90)
                    } else {
                        Text(Monnaies.formater(ligne.montant, devise)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Button("Ajouter la dépense", systemImage: "plus.circle.fill", action: ajouter).disabled(!valide)
        } header: {
            Text("Comment répartir ?")
        } footer: {
            switch repartition {
            case .famille: Text("Le prix est divisé par le nombre de familles ; chaque famille partage sa part entre ses membres.")
            case .personne: Text("Le prix est divisé par le nombre de personnes des familles choisies.")
            case .precis:
                Text(abs(ecart) < 0.005 ? "Le total est bon."
                     : "Il reste \(Monnaies.formater(ecart, devise)) à répartir.")
                    .foregroundStyle(abs(ecart) < 0.005 ? Color.secondary : .orange)
            }
        }
    }

    // MARK: Actions

    private func initialiser() {
        guard !initialisee else { return }
        initialisee = true
        devise = voyage.deviseLocale.flatMap { $0.isEmpty ? nil : $0 } ?? "EUR"
        reinitialiserSelection()
    }

    /// Au départ, seule ma famille est cochée.
    private func reinitialiserSelection() {
        selection = Set(monUnite.map { [$0.id] } ?? [])
    }

    private func ajouter() {
        let depense = Depense(devise: devise, payeurUID: moi, date: date)
        depense.titre = titre.trimmingCharacters(in: .whitespaces)
        depense.montant = montant
        depense.categorie = categorie
        depense.etapeUID = etapeUID.isEmpty ? nil : etapeUID
        depense.repartitionPrecise = repartition == .precis
        depense.parts = parts
        depense.voyage = voyage
        contexte.insert(depense)
        titre = ""
        montantTexte = ""
        montantsUnite = [:]
        etapeUID = ""
    }
}
