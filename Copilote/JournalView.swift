import SwiftUI

/// Les dernières lignes du journal, dans la fiche du voyage (organisateurs).
struct ApercuJournal: View {
    let voyage: Voyage
    var toutVoir: () -> Void

    var body: some View {
        let dernieres = voyage.journal.sorted { $0.date > $1.date }.prefix(3)
        VStack(alignment: .leading, spacing: 10) {
            if dernieres.isEmpty {
                Text("Aucune modification pour l'instant. Chaque ajout, modification ou suppression y sera noté, avec son auteur, la date et l'heure.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(dernieres)) { LigneJournal(entree: $0, avecJour: true) }
                Button(action: toutVoir) {
                    Label("Voir tout le journal (\(voyage.journal.count))", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            }
        }
    }
}

/// Le journal complet : qui a modifié quoi, jour par jour.
struct JournalView: View {
    let voyage: Voyage
    @Environment(\.dismiss) private var fermer
    @State private var auteur: String?
    @State private var recherche = ""

    private var entrees: [EntreeJournal] {
        let texte = recherche.trimmingCharacters(in: .whitespaces)
        return voyage.journal
            .filter { auteur == nil || $0.auteurNom == auteur }
            .filter { texte.isEmpty || "\($0.auteurNom) \($0.phrase) \($0.champsEnClair)".localizedStandardContains(texte) }
            .sorted { $0.date > $1.date }
    }

    private var jours: [(jour: Date, entrees: [EntreeJournal])] {
        let calendrier = Calendar.current
        let groupes = Dictionary(grouping: entrees) { calendrier.startOfDay(for: $0.date) }
        return groupes.keys.sorted(by: >).map { ($0, groupes[$0] ?? []) }
    }

    private var auteurs: [String] {
        Array(Set(voyage.journal.map(\.auteurNom))).filter { !$0.isEmpty }.sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if entrees.isEmpty {
                    ContentUnavailableView(voyage.journal.isEmpty ? "Aucune modification" : "Aucun résultat",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text(voyage.journal.isEmpty
                                                             ? "Les ajouts, modifications et suppressions des voyageurs s'afficheront ici."
                                                             : "Rien ne correspond à ce filtre."))
                }
                ForEach(jours, id: \.jour) { groupe in
                    Section(groupe.jour.formatted(.dateTime.weekday(.wide).day().month(.wide).year())) {
                        ForEach(groupe.entrees) { LigneJournal(entree: $0, avecJour: false) }
                    }
                }
            }
            .searchable(text: $recherche, prompt: "Étape, voyageur, champ…")
            .navigationTitle("Journal des modifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { fermer() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Voyageur", selection: $auteur) {
                            Text("Tout le monde").tag(String?.none)
                            ForEach(auteurs, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    } label: {
                        Label("Voyageur", systemImage: auteur == nil ? "person.2" : "person.fill.checkmark")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}

/// Une ligne : l'action, son auteur, ce qui a changé, et l'heure.
struct LigneJournal: View {
    let entree: EntreeJournal
    var avecJour: Bool

    private var couleur: Color {
        switch entree.action {
        case .ajout: .green
        case .modification: .orange
        case .suppression: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entree.action.symbole)
                .font(.title3)
                .foregroundStyle(couleur)
            VStack(alignment: .leading, spacing: 2) {
                (Text(entree.auteurNom.isEmpty ? "Quelqu'un" : entree.auteurNom).bold() + Text(" ") + Text(entree.phrase))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if entree.action == .modification, !entree.champsEnClair.isEmpty {
                    Text(entree.champsEnClair).font(.caption).foregroundStyle(.secondary)
                }
                Text(avecJour
                     ? entree.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                     : entree.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
