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

    #if ICLOUD && os(iOS)
    @State private var feuilleOuverte = false
    #endif
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
        #if ICLOUD && os(iOS)
        .sheet(isPresented: $feuilleOuverte) { ControleurPartage(voyage: voyage).ignoresSafeArea() }
        #endif
    }

    private func ouvrirPartage() {
        erreur = nil
        #if ICLOUD
        #if os(iOS)
        feuilleOuverte = true
        #else
        partagerSurMac(voyage)
        #endif
        #endif
    }
}

#if ICLOUD && os(iOS)
/// Fenêtre d'invitation d'iCloud (choix des personnes, droits, lien).
struct ControleurPartage: UIViewControllerRepresentable {
    var voyage: Voyage

    func makeCoordinator() -> Coordinateur { Coordinateur(titre: voyage.titre) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
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
                        terminer(nil, nil, error)
                    }
                }
            }
        }
        controleur.delegate = context.coordinator
        controleur.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controleur
    }

    func updateUIViewController(_ controleur: UICloudSharingController, context: Context) {}

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
