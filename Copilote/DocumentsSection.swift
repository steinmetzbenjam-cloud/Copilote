import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

/// Documents d'une réservation, ou documents généraux du voyage (passeport, assurance…).
struct DocumentsSection: View {
    var voyage: Voyage
    var reservation: Reservation?
    var titre = "Documents"

    @Environment(\.modelContext) private var contexte
    @State private var importOuvert = false
    @State private var apercu: URL?
    @State private var erreur: String?

    private var documents: [Document] {
        let tous = reservation?.documents ?? voyage.documents.filter { $0.reservation == nil }
        return tous.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        Section(titre) {
            ForEach(documents) { doc in
                Button { ouvrir(doc) } label: {
                    HStack {
                        Image(systemName: doc.symbole).foregroundStyle(.tint).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(doc.nom).foregroundStyle(.primary).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(doc.donnees.count), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(doc) }
                }
            }
            .onDelete { indices in
                for i in indices { contexte.delete(documents[i]) }
            }
            Button("Ajouter un document", systemImage: "paperclip") { importOuvert = true }
            if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importOuvert, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: true) { resultat in
            importer(resultat)
        }
        .quickLookPreview($apercu)
    }

    private func importer(_ resultat: Result<[URL], Error>) {
        erreur = nil
        switch resultat {
        case .failure(let e):
            erreur = e.localizedDescription
        case .success(let urls):
            for url in urls {
                let acces = url.startAccessingSecurityScopedResource()
                defer { if acces { url.stopAccessingSecurityScopedResource() } }
                guard let donnees = try? Data(contentsOf: url) else {
                    erreur = "Impossible de lire « \(url.lastPathComponent) »."
                    continue
                }
                guard donnees.count <= 50_000_000 else {
                    erreur = "« \(url.lastPathComponent) » dépasse 50 Mo."
                    continue
                }
                let doc = Document(nom: url.deletingPathExtension().lastPathComponent,
                                   extensionFichier: url.pathExtension, donnees: donnees)
                doc.voyage = voyage
                doc.reservation = reservation
                contexte.insert(doc)
            }
        }
    }

    private func ouvrir(_ doc: Document) {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(doc.persistentModelID.hashValue.description, isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let nom = doc.extensionFichier.isEmpty ? doc.nom : "\(doc.nom).\(doc.extensionFichier)"
        let fichier = dossier.appendingPathComponent(nom)
        do {
            try doc.donnees.write(to: fichier)
            apercu = fichier
        } catch {
            erreur = "Impossible d'ouvrir ce document."
        }
    }
}
