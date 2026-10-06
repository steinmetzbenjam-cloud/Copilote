import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Voyage.debut) private var voyages: [Voyage]
    @State private var selection: Voyage?
    /// Voyage affiché à droite. Distinct de la sélection de la liste : quand on referme le volet, SwiftUI
    /// vide la sélection de la liste, mais le voyage doit rester ouvert.
    @State private var voyageOuvert: Voyage?
    @State private var reglagesOuverts = false
    @State private var nouveauVoyageOuvert = false
    @State private var voyageASupprimer: Voyage?
    /// La liste des voyages se referme quand on en choisit un, pour laisser toute la place au voyage.
    @State private var colonnes: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $colonnes) {
            List(voyages, selection: $selection) { voyage in
                VStack(alignment: .leading) {
                    Text(voyage.titre).font(.headline)
                    if !voyage.destination.isEmpty {
                        Text(voyage.destination).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(voyage.debut.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .tag(voyage)
                .contextMenu {
                    Button(voyage.estRecu ? "Quitter ce voyage" : "Supprimer", role: .destructive) {
                        if voyage.partage || voyage.estRecu { voyageASupprimer = voyage } else { supprimer(voyage) }
                    }
                }
            }
            .navigationTitle("Voyages")
            .toolbar {
                Button("Réglages", systemImage: "key") { reglagesOuverts = true }
                Button("Nouveau voyage", systemImage: "plus") { nouveauVoyageOuvert = true }
            }
        } detail: {
            if let voyage = voyageOuvert {
                VoyageView(voyage: voyage).id(voyage.creeLe)
            } else {
                ContentUnavailableView("Aucun voyage sélectionné", systemImage: "car.fill",
                                       description: Text("Crée un voyage pour commencer à le préparer avec ton groupe."))
            }
        }
        .sheet(isPresented: $reglagesOuverts) { ReglagesView() }
        .onChange(of: selection) { _, voyage in
            guard let voyage else { return }
            voyageOuvert = voyage
            withAnimation { colonnes = .detailOnly }
        }
        .sheet(isPresented: $nouveauVoyageOuvert) {
            NouveauVoyageView { voyage in
                contexte.insert(voyage)
                selection = voyage
            }
        }
        .confirmationDialog(voyageASupprimer?.estRecu == true ? "Quitter ce voyage ?" : "Supprimer ce voyage partagé ?",
                            isPresented: Binding(get: { voyageASupprimer != nil }, set: { if !$0 { voyageASupprimer = nil } }),
                            titleVisibility: .visible) {
            Button(voyageASupprimer?.estRecu == true ? "Quitter" : "Supprimer pour tout le monde", role: .destructive) {
                if let v = voyageASupprimer { supprimer(v) }
                voyageASupprimer = nil
            }
        } message: {
            Text(voyageASupprimer?.estRecu == true
                 ? "Il disparaîtra de tes appareils, mais restera chez les autres voyageurs."
                 : "Les personnes invitées perdront aussi ce voyage.")
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 450)
        #endif
    }

    private func supprimer(_ voyage: Voyage) {
        if selection == voyage { selection = nil }
        if voyageOuvert == voyage {
            voyageOuvert = nil
            withAnimation { colonnes = .automatic }
        }
        contexte.delete(voyage)
    }

}

#Preview {
    ContentView().modelContainer(for: [Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self, Depense.self, Commentaire.self, AvisEtape.self], inMemory: true)
}
