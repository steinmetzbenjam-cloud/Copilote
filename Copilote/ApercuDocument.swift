import SwiftUI
import QuickLook
#if os(macOS)
import QuickLookUI
#endif

/// Un fichier à prévisualiser.
struct FichierAApercevoir: Identifiable {
    let id = UUID()
    let url: URL
    let titre: String
}

/// Fenêtre d'aperçu d'un document (PDF, image…), présentée une seule fois depuis la liste des documents.
struct ApercuDocumentView: View {
    let fichier: FichierAApercevoir
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ApercuQuickLook(url: fichier.url)
                .navigationTitle(fichier.titre)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
                    ToolbarItem { ShareLink(item: fichier.url) }
                }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }
}

#if os(iOS)
struct ApercuQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinateur { Coordinateur(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controleur = QLPreviewController()
        controleur.dataSource = context.coordinator
        return controleur
    }

    func updateUIViewController(_ controleur: QLPreviewController, context: Context) {}

    final class Coordinateur: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
#else
struct ApercuQuickLook: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let vue = QLPreviewView(frame: .zero, style: .normal)!
        vue.previewItem = url as NSURL
        return vue
    }

    func updateNSView(_ vue: QLPreviewView, context: Context) {
        vue.previewItem = url as NSURL
    }
}
#endif
