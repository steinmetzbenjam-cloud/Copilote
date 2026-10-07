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
        VStack(alignment: .leading, spacing: 12) {
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
            if PartageCloud.disponible && cloud.actif {
                Text("Les personnes invitées voient ce voyage dans leur app et peuvent le modifier. Supprimer ce voyage le supprime pour tout le monde.")
                    .font(.footnote).foregroundStyle(.secondary)
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
/// Fenêtre d'invitation d'iCloud sur Mac. Le service doit rester en vie pendant l'affichage (sinon rien ne s'ouvre),
/// et les erreurs de préparation du partage, silencieuses côté système, sont reportées dans le statut.
@MainActor
final class PresentateurPartageMac: NSObject, NSSharingServiceDelegate {
    static let partage = PresentateurPartageMac()
    private var service: NSSharingService?
    private var menu: NSSharingServicePicker?

    func presenter(_ voyage: Voyage) {
        let cloud = PartageCloud.shared
        guard let conteneur = cloud.conteneur else { cloud.statut = "iCloud n'est pas disponible."; return }
        let fournisseur = NSItemProvider()
        if let existant = cloud.partages[Codec.zone(de: voyage).zoneName] {
            fournisseur.registerCKShare(existant, container: conteneur, allowedSharingOptions: .standard)
        } else {
            fournisseur.registerCKShare(container: conteneur, allowedSharingOptions: .standard) {
                do {
                    return try await PartageCloud.shared.preparerPartage(voyage).0
                } catch {
                    await MainActor.run { PartageCloud.shared.statut = "Partage impossible : \(error.localizedDescription)" }
                    throw error
                }
            }
        }
        if let service = NSSharingService(named: .cloudSharing), service.canPerform(withItems: [fournisseur]) {
            service.delegate = self
            self.service = service
            service.perform(withItems: [fournisseur])
            return
        }
        // Repli : le menu de partage standard de macOS, qui propose « Ajouter des personnes » pour un partage iCloud.
        guard let vue = NSApp.keyWindow?.contentView else {
            cloud.statut = "Impossible d'ouvrir le partage : aucune fenêtre active."
            return
        }
        let menu = NSSharingServicePicker(items: [fournisseur])
        self.menu = menu
        menu.show(relativeTo: CGRect(x: vue.bounds.midX, y: vue.bounds.maxY - 60, width: 1, height: 1), of: vue, preferredEdge: .minY)
    }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        PartageCloud.shared.statut = "Partage impossible : \(error.localizedDescription)"
        service = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { service = nil }
}

@MainActor func partagerSurMac(_ voyage: Voyage) { PresentateurPartageMac.partage.presenter(voyage) }
#endif
