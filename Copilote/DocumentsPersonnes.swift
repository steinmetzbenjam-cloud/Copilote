import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum TypeDocument: String, CaseIterable, Identifiable {
    case passeport, identite, visa, assurance, billet, vaccin, permis, planMetro, autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .passeport: "Passeport"
        case .identite: "Carte d'identité"
        case .visa: "Visa"
        case .assurance: "Assurance"
        case .billet: "Billet"
        case .vaccin: "Carnet de vaccination"
        case .permis: "Permis de conduire"
        case .planMetro: "Plan de métro"
        case .autre: "Autre"
        }
    }

    var symbole: String {
        switch self {
        case .passeport: "person.text.rectangle.fill"
        case .identite: "person.crop.rectangle.fill"
        case .visa: "stamp.fill"
        case .assurance: "cross.case.fill"
        case .billet: "ticket.fill"
        case .vaccin: "syringe.fill"
        case .permis: "car.fill"
        case .planMetro: "map.fill"
        case .autre: "doc.fill"
        }
    }

    /// Les pièces qui expirent : on leur demande une date de validité.
    var aUneValidite: Bool { [.passeport, .identite, .visa, .assurance, .permis].contains(self) }

    /// Nombre de jours de validité exigés après le retour (6 mois pour un passeport, souvent demandé à l'entrée).
    var margeApresRetour: Int { self == .passeport ? 180 : 0 }
}

extension Document {
    var type: TypeDocument {
        get { typeBrut.flatMap(TypeDocument.init(rawValue:)) ?? .autre }
        set { typeBrut = newValue.rawValue }
    }

    enum Validite { case ok, courte, expire }

    /// La date de validité, comparée au retour du voyage.
    func validite(pour voyage: Voyage) -> Validite? {
        guard let expireLe else { return nil }
        if expireLe < Calendar.current.startOfDay(for: voyage.fin) { return .expire }
        let seuil = Calendar.current.date(byAdding: .day, value: type.margeApresRetour, to: voyage.fin) ?? voyage.fin
        return expireLe < seuil ? .courte : .ok
    }

    func urlTemporaire() throws -> URL {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(uid.isEmpty ? UUID().uuidString : uid, isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let fichier = dossier.appendingPathComponent(extensionFichier.isEmpty ? nom : "\(nom).\(extensionFichier)")
        try donnees.write(to: fichier)
        return fichier
    }
}

/// Les documents de chaque voyageur : passeport, assurance, billets… avec les dates de validité à surveiller.
struct DocumentsPersonnesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var importPour: Membre?
    @State private var importOuvert = false
    @State private var apercu: FichierAApercevoir?
    @State private var enEdition: Document?
    @State private var erreur: String?

    private func documents(de membre: Membre) -> [Document] {
        voyage.documents.filter { $0.membreUID == membre.uid }.sorted { $0.creeLe < $1.creeLe }
    }

    private var alertes: [(Document, Document.Validite)] {
        voyage.documents.compactMap { d in d.validite(pour: voyage).flatMap { $0 == .ok ? nil : (d, $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !alertes.isEmpty { cadreAlertes }
                ForEach(voyage.membresTries) { cadre($0) }
                if voyage.membres.isEmpty {
                    ContentUnavailableView("Aucun voyageur", systemImage: "person.text.rectangle",
                                           description: Text("Ajoute les voyageurs dans l'onglet Infos pour leur associer des documents."))
                }
                if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
                Text("Les documents sont partagés avec les personnes invitées au voyage. N'y mets que ce que le groupe peut voir.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
        .fileImporter(isPresented: $importOuvert, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: true) { importer($0) }
        .sheet(item: $apercu) { ApercuDocumentView(fichier: $0) }
        .sheet(item: $enEdition) { DocumentEditView(document: $0, voyage: voyage) }
    }

    // MARK: Alertes

    private var cadreAlertes: some View {
        CadreInfos(titre: "À vérifier", symbole: "exclamationmark.triangle.fill", couleur: .red) {
            ForEach(alertes, id: \.0.uid) { doc, etat in
                let proprietaire = doc.membreUID.flatMap { voyage.membre(uid: $0)?.nom } ?? "—"
                Label {
                    Text("\(doc.type.libelle) de \(proprietaire) : \(texte(etat, doc))")
                } icon: {
                    Image(systemName: etat == .expire ? "xmark.octagon.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(etat == .expire ? .red : .orange)
                }
                .font(.subheadline)
            }
        }
    }

    private func texte(_ etat: Document.Validite, _ doc: Document) -> String {
        let date = doc.expireLe?.formatted(date: .abbreviated, time: .omitted) ?? ""
        switch etat {
        case .expire: return "expire le \(date), avant le retour"
        case .courte: return "expire le \(date) : moins de 6 mois après le retour"
        case .ok: return "valide jusqu'au \(date)"
        }
    }

    // MARK: Une personne

    private func cadre(_ membre: Membre) -> some View {
        let docs = documents(de: membre)
        let peut = voyage.peutGererDocuments(de: membre)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RondMembre(membre: membre, voyage: voyage, taille: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text(membre.nom).font(.headline)
                    if !membre.famille.isEmpty { Text(membre.famille).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                Text("\(docs.count) document\(docs.count > 1 ? "s" : "")").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(docs) { ligne($0, peut: peut) }
            if peut {
                Button("Ajouter un document", systemImage: "paperclip") {
                    importPour = membre
                    importOuvert = true
                }
                .buttonStyle(.borderless)
            } else if docs.isEmpty {
                Text("Aucun document.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    private func ligne(_ doc: Document, peut: Bool) -> some View {
        let etat = doc.validite(pour: voyage)
        return HStack(spacing: 12) {
            Button { ouvrir(doc) } label: {
                HStack(spacing: 12) {
                    Image(systemName: doc.type.symbole).foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(Circle().fill(Color.indigo))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.nom).foregroundStyle(.primary).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(doc.type.libelle).font(.caption).foregroundStyle(.secondary)
                            if let etat, let date = doc.expireLe {
                                Text("· jusqu'au \(date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(etat == .expire ? .red : (etat == .courte ? .orange : .green))
                            }
                        }
                    }
                    Spacer()
                    if let etat, etat != .ok {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(etat == .expire ? .red : .orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if peut {
                Menu {
                    Button("Modifier", systemImage: "pencil") { enEdition = doc }
                    Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(doc) }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    // MARK: Actions

    private func ouvrir(_ doc: Document) {
        do { apercu = FichierAApercevoir(url: try doc.urlTemporaire(), titre: doc.nom) } catch { erreur = "Impossible d'ouvrir ce document." }
    }

    private func importer(_ resultat: Result<[URL], Error>) {
        erreur = nil
        guard let membre = importPour else { return }
        switch resultat {
        case .failure(let e): erreur = e.localizedDescription
        case .success(let urls):
            var dernier: Document?
            for url in urls {
                let acces = url.startAccessingSecurityScopedResource()
                defer { if acces { url.stopAccessingSecurityScopedResource() } }
                guard let donnees = try? Data(contentsOf: url) else { erreur = "Impossible de lire « \(url.lastPathComponent) »."; continue }
                guard donnees.count <= 50_000_000 else { erreur = "« \(url.lastPathComponent) » dépasse 50 Mo."; continue }
                let doc = Document(nom: url.deletingPathExtension().lastPathComponent, extensionFichier: url.pathExtension, donnees: donnees)
                doc.voyage = voyage
                doc.membreUID = membre.uid
                doc.type = .autre
                contexte.insert(doc)
                dernier = doc
            }
            // On demande tout de suite le type et la validité du dernier document ajouté.
            if urls.count == 1, let dernier { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { enEdition = dernier } }
        }
    }
}

/// Type, nom et date de validité d'un document.
struct DocumentEditView: View {
    @Bindable var document: Document
    var voyage: Voyage
    @Environment(\.dismiss) private var dismiss
    @State private var type: TypeDocument
    @State private var aUneDate: Bool
    @State private var date: Date

    init(document: Document, voyage: Voyage) {
        self.document = document
        self.voyage = voyage
        _type = State(initialValue: document.type)
        _aUneDate = State(initialValue: document.expireLe != nil)
        _date = State(initialValue: document.expireLe ?? Calendar.current.date(byAdding: .year, value: 1, to: voyage.fin) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $document.nom)
                    Picker("Type", selection: $type) {
                        ForEach(TypeDocument.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                    }
                }
                Section {
                    Toggle("Date de validité", isOn: $aUneDate)
                    if aUneDate { DatePicker("Valable jusqu'au", selection: $date, displayedComponents: .date) }
                } footer: {
                    Text(type == .passeport ? "Beaucoup de pays exigent un passeport valable 6 mois après le retour : l'app te prévient si ce n'est pas le cas."
                         : "L'app te prévient si la pièce expire avant le retour.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        document.type = type
                        document.expireLe = aUneDate ? date : nil
                        dismiss()
                    }
                }
            }
            .onChange(of: type) { _, nouveau in if nouveau.aUneValidite, document.expireLe == nil { aUneDate = true } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

/// L'onglet « Groupe » : les votes et les documents de chacun.
struct GroupeView: View {
    @Bindable var voyage: Voyage
    @State private var partie = Partie.votes

    enum Partie: String, CaseIterable, Identifiable {
        case votes = "Votes", documents = "Documents"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Partie", selection: $partie) {
                ForEach(Partie.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            switch partie {
            case .votes: VotesView(voyage: voyage)
            case .documents: DocumentsPersonnesView(voyage: voyage)
            }
        }
        .background(FondDePage.couleur)
    }
}
