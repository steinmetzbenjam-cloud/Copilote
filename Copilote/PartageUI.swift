import SwiftUI
import SwiftData
import CloudKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Section « Partage avec le groupe » de l'écran Infos d'un voyage.
struct SectionPartage: View {
    var voyage: Voyage
    private var cloud = PartageCloud.shared

    @State private var erreur: String?

    init(voyage: Voyage) { self.voyage = voyage }

    var body: some View {
        Section {
            if !PartageCloud.disponible {
                Label("Le partage iCloud n'est pas activé dans cette version de l'app (compte Apple Developer requis).",
                      systemImage: "icloud.slash")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !cloud.actif {
                Label("Active la synchronisation iCloud dans les réglages (icône clé) pour partager ce voyage.",
                      systemImage: "icloud")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if voyage.estRecu {
                    Label("Ce voyage t'a été partagé.", systemImage: "person.2.fill")
                }
                if voyage.partage {
                    LabeledContent("Partagé avec") {
                        Text(voyage.participantsCloud.isEmpty ? "—" : voyage.participantsCloud.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                } else if !voyage.estRecu {
                    Text("Ce voyage n'est pas encore partagé.").foregroundStyle(.secondary)
                }
                Button(voyage.partage ? "Gérer le partage" : "Inviter des voyageurs",
                       systemImage: "person.crop.circle.badge.plus", action: ouvrirPartage)
                if cloud.synchroEnCours {
                    Label("Synchronisation…", systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary)
                } else if !cloud.statut.isEmpty {
                    Text(cloud.statut).font(.footnote).foregroundStyle(.secondary)
                }
                if let erreur { Text(erreur).font(.footnote).foregroundStyle(.red) }
            }
        } header: {
            Text("Partage avec le groupe")
        } footer: {
            if PartageCloud.disponible && cloud.actif {
                Text("Les personnes invitées voient ce voyage dans leur app et peuvent le modifier. Supprimer ce voyage le supprime pour tout le monde.")
            }
        }
    }

    private func ouvrirPartage() {
        erreur = nil
        #if ICLOUD
        #if os(iOS)
        PresentateurPartage.presenter(voyage)
        #else
        partagerSurMac(voyage)
        #endif
        #endif
    }
}

#if ICLOUD && os(iOS)
/// Fenêtre d'invitation d'iCloud (choix des personnes, droits, lien).
/// Présentée directement par UIKit : dans une feuille SwiftUI, elle s'affiche en cadre blanc.
@MainActor
enum PresentateurPartage {
    /// Le contrôleur ne retient pas son délégué : on le garde ici le temps de la présentation.
    private static var coordinateur: Coordinateur?

    static func presenter(_ voyage: Voyage) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var haut = (scene.keyWindow ?? scene.windows.first)?.rootViewController else { return }
        while let suivant = haut.presentedViewController { haut = suivant }

        let controleur: UICloudSharingController
        let zone = Codec.zone(de: voyage)
        if let partage = PartageCloud.shared.partages[zone.zoneName], let conteneur = PartageCloud.shared.conteneur {
            controleur = UICloudSharingController(share: partage, container: conteneur)
        } else {
            controleur = UICloudSharingController { _, terminer in
                Task { @MainActor in
                    do {
                        let (partage, conteneur) = try await PartageCloud.shared.preparerPartage(voyage)
                        terminer(partage, conteneur, nil)
                    } catch {
                        PartageCloud.shared.statut = "Partage impossible : \(error.localizedDescription)"
                        terminer(nil, nil, error)
                    }
                }
            }
        }
        let coordinateur = Coordinateur(titre: voyage.titre)
        self.coordinateur = coordinateur
        controleur.delegate = coordinateur
        controleur.availablePermissions = [.allowReadWrite, .allowPrivate]
        // Sur iPad, la fenêtre s'ouvre en bulle : il lui faut une ancre.
        if let bulle = controleur.popoverPresentationController {
            bulle.sourceView = haut.view
            bulle.sourceRect = CGRect(x: haut.view.bounds.midX, y: haut.view.bounds.midY, width: 1, height: 1)
            bulle.permittedArrowDirections = []
        }
        haut.present(controleur, animated: true)
    }

    final class Coordinateur: NSObject, UICloudSharingControllerDelegate {
        let titre: String
        init(titre: String) { self.titre = titre }
        func itemTitle(for csc: UICloudSharingController) -> String? { titre }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            PartageCloud.shared.statut = "Partage impossible : \(error.localizedDescription)"
        }
    }
}
#endif

#if ICLOUD && os(macOS)
@MainActor func partagerSurMac(_ voyage: Voyage) {
    guard let conteneur = PartageCloud.shared.conteneur else { return }
    let fournisseur = NSItemProvider()
    fournisseur.registerCKShare(container: conteneur, allowedSharingOptions: .standard) {
        try await PartageCloud.shared.preparerPartage(voyage).0
    }
    NSSharingService(named: .cloudSharing)?.perform(withItems: [fournisseur])
}
#endif
