import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var contexte
    @Environment(\.undoManager) private var annulation
    @Query(sort: \Voyage.debut) private var voyages: [Voyage]
    @State private var selection: Voyage?
    /// Voyage affiché à droite. Distinct de la sélection de la liste : quand on referme le volet, SwiftUI
    /// vide la sélection de la liste, mais le voyage doit rester ouvert.
    @State private var voyageOuvert: Voyage?
    @State private var reglagesOuverts = false
    /// Première ouverture de l'app : on demande qui est l'utilisateur.
    @State private var profilPremiereFois = false
    /// Première ouverture de l'app : un petit tutoriel, avant de demander qui est l'utilisateur.
    @State private var tutorielOuvert = false
    /// Au lancement, sans voyage ouvert : liste de tous les voyages à choisir.
    @State private var selecteurOuvert = false
    @State private var selecteurDejaPropose = false
    @State private var nouveauVoyageOuvert = false
    @State private var voyageASupprimer: Voyage?
    @Environment(\.scenePhase) private var phase
    @State private var sauvegarde: SauvegardeDocument?
    @State private var nomSauvegarde = "Copilote"
    @State private var exportOuvert = false
    @State private var choixSauvegardeOuvert = false
    @State private var voyagesChoisis: [Voyage]?
    @State private var importOuvert = false
    @State private var importEnAttente: Sauvegarde.Fichier?
    @State private var messageSauvegarde: String?
    /// La liste des voyages se referme quand on en choisit un, pour laisser toute la place au voyage.
    /// Au lancement, si un voyage va être rouvert, le volet est déjà refermé : on arrive directement sur le voyage.
    @State private var colonnes: NavigationSplitViewVisibility =
        (UserDefaults.standard.string(forKey: ContentView.cleDernierVoyage)?.isEmpty == false) ? .detailOnly : .automatic

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
                        voyageASupprimer = voyage
                    }
                }
            }
            .navigationTitle("Voyages")
            .overlay {
                if voyages.isEmpty {
                    Text("Aucun voyage pour l'instant.\nTouche « Nouveau » pour commencer.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding()
                }
            }
            // En haut, au-dessus des voyages : nouveau voyage.
            .safeAreaInset(edge: .top, spacing: 0) {
                Button { nouveauVoyageOuvert = true } label: {
                    Label("Nouveau", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            // En bas du panneau : les réglages, puis la sauvegarde en dessous.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 6) {
                    Divider()
                    Button { reglagesOuverts = true } label: {
                        Label("Réglages", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("Choisir les voyages à sauvegarder…", systemImage: "square.and.arrow.up") { choixSauvegardeOuvert = true }
                            .disabled(voyages.isEmpty)
                        Button("Importer une sauvegarde…", systemImage: "square.and.arrow.down") { importOuvert = true }
                    } label: {
                        Label("Sauvegarde", systemImage: "externaldrive")
                            // Même apparence que « Réglages » juste au-dessus (un menu se colorait de la teinte de l'app).
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
                .background(.bar)
            }
        } detail: {
            if let voyage = voyageOuvert {
                VoyageView(voyage: voyage).id(voyage.creeLe)
            } else {
                ContentUnavailableView {
                    Label(voyages.isEmpty ? "Aucun voyage" : "Aucun voyage ouvert", systemImage: "car.fill")
                } description: {
                    Text(voyages.isEmpty ? "Crée ton premier voyage pour commencer à le préparer, seul ou avec ton groupe."
                                         : "Choisis un voyage dans la liste, ou crées-en un nouveau.")
                } actions: {
                    Button("Nouveau voyage", systemImage: "plus.circle.fill") { nouveauVoyageOuvert = true }
                        .buttonStyle(.borderedProminent)
                    if !voyages.isEmpty {
                        Button("Voir mes voyages", systemImage: "sidebar.left") { withAnimation { colonnes = .all } }
                    }
                }
            }
        }
        .sheet(isPresented: $reglagesOuverts) { ReglagesView() }
        .sheet(isPresented: $profilPremiereFois, onDismiss: rouvrirOuProposer) { ProfilEditView(premiereFois: true) }
        .sheet(isPresented: $selecteurOuvert) {
            SelecteurVoyageView(voyages: voyages, onChoix: { selection = $0 }, onNouveau: { nouveauVoyageOuvert = true })
        }
        .sheet(isPresented: $tutorielOuvert, onDismiss: {
            if !Profil.partage.estRenseigne { profilPremiereFois = true } else { rouvrirOuProposer() }
        }) { TutorielView() }
        // Annuler (⌘Z, menu Édition, secousse de l'iPhone) reprend la dernière modification : une suppression comprise.
        .onChange(of: annulation, initial: true) { _, nouvelle in contexte.undoManager = nouvelle }
        .onAppear {
            if !Profil.partage.estRenseigne {
                // Nouvel utilisateur : le tutoriel d'abord (une seule fois), puis son profil.
                if UserDefaults.standard.bool(forKey: TutorielView.cleVu) { profilPremiereFois = true } else { tutorielOuvert = true }
            } else {
                rouvrirOuProposer()
            }
        }
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
        .task(id: signatureRappels) {
            try? await Task.sleep(for: .seconds(2))
            await Rappels.planifier(voyages)
        }
        .onChange(of: phase) { _, nouvelle in
            if nouvelle == .active { Task { await Rappels.planifier(voyages) } }
        }
        // Les notifications ne sont demandées qu'une fois un voyage en place (la veille du départ, les transports…) :
        // jamais au premier lancement, avant même le tutoriel.
        .task(id: voyages.isEmpty) {
            if !voyages.isEmpty { await Rappels.proposer() }
        }
        .onChange(of: selection) { _, voyage in
            guard let voyage else { return }
            UserDefaults.standard.set(voyage.uid, forKey: Self.cleDernierVoyage)
            // Les horaires du voyage sont lus dans son fuseau de référence, avant d'afficher quoi que ce soit.
            Horloge.ouvrir(voyage)
            let auLancement = voyageOuvert == nil
            voyageOuvert = voyage
            if auLancement { colonnes = .detailOnly } else { withAnimation { colonnes = .detailOnly } }
        }
        .sheet(isPresented: $nouveauVoyageOuvert) {
            NouveauVoyageView { voyage in
                voyage.fuseauReferenceId = Horloge.zoneAppareil().identifier
                contexte.insert(voyage)
                // Le créateur fait partie du voyage d'office : Budget, Dépenses et votes le connaissent tout de suite.
                if Profil.partage.estRenseigne { Profil.partage.identifier(dans: voyage, contexte: contexte) }
                selection = voyage
            }
        }
        .confirmationDialog(voyageASupprimer?.estRecu == true ? "Quitter ce voyage ?"
                            : voyageASupprimer?.partage == true ? "Supprimer ce voyage partagé ?" : "Supprimer ce voyage ?",
                            isPresented: Binding(get: { voyageASupprimer != nil }, set: { if !$0 { voyageASupprimer = nil } }),
                            titleVisibility: .visible) {
            Button(voyageASupprimer?.estRecu == true ? "Quitter" : voyageASupprimer?.partage == true ? "Supprimer pour tout le monde" : "Supprimer",
                   role: .destructive) {
                if let v = voyageASupprimer { supprimer(v) }
                voyageASupprimer = nil
            }
        } message: {
            Text(voyageASupprimer?.estRecu == true
                 ? "Il disparaîtra de tes appareils, mais restera chez les autres voyageurs."
                 : voyageASupprimer?.partage == true
                 ? "Les personnes invitées perdront aussi ce voyage."
                 : "Ses étapes, réservations, dépenses et documents seront effacés. Fais une sauvegarde avant si tu veux le garder.")
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 450)
        #endif
    }


    /// Change quand une date, une heure ou un transport change : les rappels sont alors reprogrammés.
    private var signatureRappels: String {
        voyages.map { v in
            "\(v.uid)\(v.debut.timeIntervalSince1970)\(v.etapes.map { "\($0.uid)\($0.jour?.timeIntervalSince1970 ?? 0)\($0.heure?.timeIntervalSince1970 ?? 0)\($0.apresJour)\($0.variante ?? "")\($0.transportJSON ?? "")" }.joined())\(v.transportAllerJSON ?? "")\(v.transportRetourJSON ?? "")"
        }.joined(separator: "|")
    }

    private static let cleDernierVoyage = "dernierVoyageOuvert"

    /// Au lancement : on rouvre le dernier voyage consulté (à l'itinéraire) ; s'il n'existe plus, on propose le choix.
    private func rouvrirOuProposer() {
        guard !selecteurDejaPropose, voyageOuvert == nil else { return }
        if let uid = UserDefaults.standard.string(forKey: Self.cleDernierVoyage), !uid.isEmpty,
           let dernier = voyages.first(where: { $0.uid == uid }) {
            selecteurDejaPropose = true
            selection = dernier
            return
        }
        proposerLesVoyages()
    }

    /// Une seule fois par lancement, et seulement s'il y a des voyages et qu'aucun n'est ouvert.
    private func proposerLesVoyages() {
        guard !selecteurDejaPropose, voyageOuvert == nil, !voyages.isEmpty else { return }
        selecteurDejaPropose = true
        selecteurOuvert = true
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
        importEnAttente = nil
        do {
            try Sauvegarde.importer(fichier, dans: contexte)
            let n = fichier.voyages.count
            messageSauvegarde = n == 1 ? "Le voyage « \(fichier.voyages[0].titre) » est importé." : "\(n) voyages importés."
        } catch {
            messageSauvegarde = "L'import n'a pas pu être enregistré : \(error.localizedDescription)"
        }
    }

    private func supprimer(_ voyage: Voyage) {
        if UserDefaults.standard.string(forKey: Self.cleDernierVoyage) == voyage.uid {
            UserDefaults.standard.removeObject(forKey: Self.cleDernierVoyage)
        }
        if selection == voyage { selection = nil }
        if voyageOuvert == voyage {
            voyageOuvert = nil
            withAnimation { colonnes = .automatic }
        }
        contexte.delete(voyage)
    }

}

#Preview {
    ContentView().modelContainer(for: [Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self, Depense.self, Commentaire.self, AvisEtape.self, Famille.self, Sondage.self, VoteSondage.self], inMemory: true)
}

