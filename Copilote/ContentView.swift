import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var contexte
    @Query(sort: \Voyage.debut) private var voyages: [Voyage]
    @State private var selection: Voyage?
    @State private var reglagesOuverts = false

    var body: some View {
        NavigationSplitView {
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
                    Button("Supprimer", role: .destructive) { supprimer(voyage) }
                }
            }
            .navigationTitle("Voyages")
            .toolbar {
                Button("Réglages", systemImage: "key") { reglagesOuverts = true }
                Button("Nouveau voyage", systemImage: "plus", action: ajouter)
            }
        } detail: {
            if let voyage = selection {
                VoyageView(voyage: voyage).id(voyage.persistentModelID)
            } else {
                ContentUnavailableView("Aucun voyage sélectionné", systemImage: "car.fill",
                                       description: Text("Crée un voyage pour commencer à le préparer avec ton groupe."))
            }
        }
        .sheet(isPresented: $reglagesOuverts) { ReglagesView() }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 450)
        #endif
    }

    private func supprimer(_ voyage: Voyage) {
        if selection == voyage { selection = nil }
        contexte.delete(voyage)
    }

    private func ajouter() {
        let voyage = Voyage(titre: "Nouveau voyage")
        contexte.insert(voyage)
        selection = voyage
    }
}

#Preview {
    ContentView().modelContainer(for: [Voyage.self, Membre.self, Etape.self], inMemory: true)
}
