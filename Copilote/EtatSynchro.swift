import SwiftUI

/// Où en est la synchronisation iCloud : à jour, en cours, en attente du réseau, en échec…
/// Le même état sert au cadre « Synchronisation » de l'Aperçu et à la pastille sous le nom du voyage.
@MainActor struct EtatSynchro {
    /// Titre complet (Aperçu) et version courte (barre de titre).
    let titre: String
    let court: String
    let detail: String?
    let symbole: String
    let couleur: Color

    static var actuel: EtatSynchro {
        let cloud = PartageCloud.shared
        let reseau = Reseau.shared
        let attente = cloud.enAttente
        let modifications = "\(attente) modification\(attente > 1 ? "s" : "")"

        if !PartageCloud.disponible || !cloud.actif {
            return EtatSynchro(titre: "Sur cet appareil seulement", court: "iCloud désactivé",
                               detail: "La synchronisation iCloud n'est pas activée : ce voyage n'est pas envoyé aux autres appareils ni au groupe.",
                               symbole: "internaldrive", couleur: .gray)
        }
        if !reseau.enLigne {
            let enAttente = attente > 0 ? " \(modifications) attend\(attente > 1 ? "ent" : "") le retour du réseau." : ""
            return EtatSynchro(titre: "Hors ligne", court: attente > 0 ? "Hors ligne · \(attente) en attente" : "Hors ligne",
                               detail: "Tu peux continuer à travailler : tout est gardé sur l'appareil.\(enAttente)",
                               symbole: "icloud.slash", couleur: .orange)
        }
        if let erreur = cloud.erreur {
            return EtatSynchro(titre: "Modifications non envoyées", court: "Erreur iCloud", detail: erreur,
                               symbole: "exclamationmark.icloud.fill", couleur: .red)
        }
        if cloud.synchroEnCours || attente > 0 {
            return EtatSynchro(titre: "Synchronisation en cours…", court: attente > 0 ? "Envoi de \(modifications)…" : "Synchronisation…",
                               detail: attente > 0 ? "\(modifications) à envoyer." : nil,
                               symbole: "arrow.triangle.2.circlepath.icloud", couleur: .blue)
        }
        if let echec = cloud.echecSynchro {
            return EtatSynchro(titre: "iCloud injoignable", court: "iCloud injoignable",
                               detail: "La dernière vérification a échoué (\(echec)). Touche la pastille pour réessayer.",
                               symbole: "exclamationmark.icloud", couleur: .orange)
        }
        guard let quand = cloud.derniereSynchro else {
            return EtatSynchro(titre: "Vérification…", court: "Vérification…",
                               detail: "Copilote demande à iCloud s'il y a du nouveau.", symbole: "icloud", couleur: .secondary)
        }
        let ilYa = Date.now.timeIntervalSince(quand) < 60 ? "à l'instant"
            : quand.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return EtatSynchro(titre: "Synchronisé", court: "À jour · \(ilYa)",
                           detail: "Tout est envoyé, et iCloud a été consulté \(ilYa).",
                           symbole: "checkmark.icloud.fill", couleur: .green)
    }
}

/// La pastille de synchronisation, sous le nom du voyage (à côté sur iPad et Mac).
/// La toucher lance tout de suite un échange avec iCloud : envoi des modifications et réception des nouveautés.
struct PastilleSynchro: View {
    private var cloud = PartageCloud.shared

    var body: some View {
        // Relue toutes les 30 secondes, pour que « il y a 2 min » reste juste.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let etat = EtatSynchro.actuel
            Button {
                Task { await cloud.synchroniser() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: etat.symbole)
                        .symbolEffect(.pulse, isActive: cloud.synchroEnCours)
                    Text(etat.court).lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(etat.couleur)
                // Un fond léger : la barre passe souvent par-dessus la carte.
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(etat.detail.map { "\(etat.titre) : \($0)" } ?? etat.titre)
            .accessibilityLabel("Synchronisation iCloud : \(etat.court)")
            .accessibilityHint("Touche pour synchroniser maintenant")
            .animation(.snappy, value: etat.court)
        }
    }
}
