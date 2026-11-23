import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Bouton « Itinéraire de Claude », dans « Étapes à placer » : colle le texte copié depuis Claude, ou ouvre le fichier qu'il a préparé.
/// L'itinéraire devient une étape à placer, avec ses sous-étapes et leurs transports (voir `ItineraireClaude`).
struct BoutonImportClaude: View {
    let voyage: Voyage
    /// Appelé avec l'étape créée (pour ouvrir la fenêtre des étapes à placer, par exemple).
    var onImporte: (Etape) -> Void = { _ in }
    @Environment(\.modelContext) private var contexte
    @State private var fichierOuvert = false
    @State private var message: (titre: String, texte: String)?

    var body: some View {
        Menu {
            Button("Coller l'itinéraire copié", systemImage: "doc.on.clipboard") { coller() }
            Button("Ouvrir le fichier de Claude…", systemImage: "folder") { fichierOuvert = true }
        } label: {
            Label("Itinéraire de Claude", systemImage: "sparkles")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .disabled(voyage.lectureSeule)
        .help("Ajouter l'itinéraire préparé par Claude : une étape qui contient toutes les siennes")
        .fileImporter(isPresented: $fichierOuvert, allowedContentTypes: [.json, .plainText, .text, .data]) { resultat in
            switch resultat {
            case .success(let url):
                let acces = url.startAccessingSecurityScopedResource()
                defer { if acces { url.stopAccessingSecurityScopedResource() } }
                do {
                    let donnees = try Data(contentsOf: url)
                    importer(try ItineraireClaude.lire(texte: String(decoding: donnees, as: UTF8.self)))
                } catch {
                    message = ("Itinéraire non importé", error.localizedDescription)
                }
            case .failure(let erreur):
                message = ("Itinéraire non importé", erreur.localizedDescription)
            }
        }
        .alert(message?.titre ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message?.texte ?? "") }
    }

    private func coller() {
        #if os(iOS)
        let texte = UIPasteboard.general.string ?? ""
        #else
        let texte = NSPasteboard.general.string(forType: .string) ?? ""
        #endif
        do {
            importer(try ItineraireClaude.lire(texte: texte))
        } catch ItineraireClaude.Erreur.vide {
            message = ("Rien à coller", "Copie d'abord l'itinéraire dans la conversation avec Claude (le bloc de code ou tout le message), puis reviens ici.")
        } catch {
            message = ("Itinéraire non importé", error.localizedDescription)
        }
    }

    private func importer(_ it: ItineraireClaude) {
        let etape = withAnimation(.snappy) { voyage.importer(it, dans: contexte) }
        let n = etape.sousEtapes.count
        let sansPosition = etape.sousEtapes.filter { $0.coordonnee == nil }.count
        onImporte(etape)
        message = ("Itinéraire ajouté",
                   "« \(etape.titre) » est dans les étapes à placer, avec \(n) sous-étape\(n > 1 ? "s" : "")."
                   + " Glisse-la sur le jour voulu."
                   + (sansPosition > 0 ? " Les lieux sans position sont cherchés dans Plans." : ""))
        if sansPosition > 0 { Task { await ItineraireClaude.completerPositions(de: etape) } }
    }
}
