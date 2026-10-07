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
    /// Première ouverture de l'app : on demande qui est l'utilisateur.
    @State private var profilPremiereFois = false
    @State private var nouveauVoyageOuvert = false
    @State private var voyageASupprimer: Voyage?
    @State private var sauvegarde: SauvegardeDocument?
    @State private var nomSauvegarde = "Copilote"
    @State private var exportOuvert = false
    @State private var choixSauvegardeOuvert = false
    @State private var voyagesChoisis: [Voyage]?
    @State private var importOuvert = false
    @State private var importEnAttente: Sauvegarde.Fichier?
    @State private var messageSauvegarde: String?
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
                    Button("Sauvegarder ce voyage…", systemImage: "square.and.arrow.up") { sauvegarder([voyage]) }
                    Button(voyage.estRecu ? "Quitter ce voyage" : "Supprimer", role: .destructive) {
                        if voyage.partage || voyage.estRecu { voyageASupprimer = voyage } else { supprimer(voyage) }
                    }
                }
            }
            .navigationTitle("Voyages")
            .toolbar {
                Menu("Sauvegarde", systemImage: "externaldrive") {
                    Button("Choisir les voyages à sauvegarder…", systemImage: "square.and.arrow.up") { choixSauvegardeOuvert = true }
                        .disabled(voyages.isEmpty)
                    Button("Importer une sauvegarde…", systemImage: "square.and.arrow.down") { importOuvert = true }
                }
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
        .sheet(isPresented: $profilPremiereFois) { ProfilEditView(premiereFois: true) }
        .onAppear { if !Profil.partage.estRenseigne { profilPremiereFois = true } }
        .sheet(isPresented: $choixSauvegardeOuvert, onDismiss: {
            // L'enregistrement s'ouvre une fois la feuille de choix refermée.
            if let choisis = voyagesChoisis { voyagesChoisis = nil; sauvegarder(choisis) }
        }) {
            ChoixSauvegardeView(voyages: voyages) { voyagesChoisis = $0 }
        }
        .fileExporter(isPresented: $exportOuvert, document: sauvegarde, contentType: .json, defaultFilename: nomSauvegarde) { resultat in
            if case .failure(let erreur) = resultat { messageSauvegarde = "Sauvegarde impossible : \(erreur.localizedDescription)" }
            sauvegarde = nil
        }
        .fileImporter(isPresented: $importOuvert, allowedContentTypes: [.json]) { resultat in
            lireSauvegarde(resultat)
        }
        .confirmationDialog("Voyage déjà présent", isPresented: Binding(get: { importEnAttente != nil }, set: { if !$0 { importEnAttente = nil } }),
                            titleVisibility: .visible, presenting: importEnAttente) { fichier in
            Button("Importer et remettre à jour") { importer(fichier) }
        } message: { fichier in
            Text("« \(Sauvegarde.dejaPresents(fichier, contexte).joined(separator: ", ")) » existe déjà ici. Ses éléments reprendront les valeurs de la sauvegarde ; ceux ajoutés depuis ne seront pas supprimés.")
        }
        .alert("Sauvegarde", isPresented: Binding(get: { messageSauvegarde != nil }, set: { if !$0 { messageSauvegarde = nil } })) {
            Button("OK") {}
        } message: { Text(messageSauvegarde ?? "") }
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

    private func sauvegarder(_ aSauver: [Voyage]) {
        do {
            sauvegarde = SauvegardeDocument(donnees: try Sauvegarde.exporter(aSauver))
            let nom = aSauver.count == 1 ? aSauver[0].titre : "sauvegarde"
            nomSauvegarde = "Copilote – " + nom.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            exportOuvert = true
        } catch {
            messageSauvegarde = "Sauvegarde impossible : \(error.localizedDescription)"
        }
    }

    private func lireSauvegarde(_ resultat: Result<URL, Error>) {
        do {
            let url = try resultat.get()
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            let fichier = try Sauvegarde.lire(try Data(contentsOf: url))
            if Sauvegarde.dejaPresents(fichier, contexte).isEmpty { importer(fichier) } else { importEnAttente = fichier }
        } catch {
            messageSauvegarde = error.localizedDescription
        }
    }

    private func importer(_ fichier: Sauvegarde.Fichier) {
        Sauvegarde.importer(fichier, dans: contexte)
        importEnAttente = nil
        let n = fichier.voyages.count
        messageSauvegarde = n == 1 ? "Le voyage « \(fichier.voyages[0].titre) » est importé." : "\(n) voyages importés."
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
