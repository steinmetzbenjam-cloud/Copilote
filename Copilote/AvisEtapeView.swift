import SwiftUI
import SwiftData

/// Petit résumé des avis du groupe sur une étape, à droite de sa ligne : un bouton qui ouvre la fenêtre d'avis.
struct PastilleAvis: View {
    let voyage: Voyage
    let etape: Etape
    let action: () -> Void

    var body: some View {
        let s = voyage.synthese(de: etape)
        Button(action: action) {
            HStack(spacing: 6) {
                if s.incontournables > 0 {
                    Label("\(s.incontournables)", systemImage: EnvieEtape.incontournable.symbole).foregroundStyle(EnvieEtape.incontournable.couleur)
                }
                if s.refus > 0 {
                    Label("\(s.refus)", systemImage: EnvieEtape.pasEnvie.symbole).foregroundStyle(EnvieEtape.pasEnvie.couleur)
                }
                if let moyenne = s.moyenne {
                    Label(moyenne.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill").foregroundStyle(.orange)
                } else if s.total == 0 {
                    Image(systemName: "star").foregroundStyle(.secondary)
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Avis du groupe sur \(etape.titre)")
    }
}

/// Les avis du groupe sur une étape : qui a noté, qui a écrit quoi.
struct ListeAvisEtape: View {
    let voyage: Voyage
    let etape: Etape
    /// Écarte l'avis de cette personne (le mien, quand il est affiché à part).
    var sans: String?

    private var avis: [AvisEtape] {
        voyage.avis(de: etape)
            .filter { $0.auteurUID != sans }
            .sorted { $0.modifieLe > $1.modifieLe }
    }

    var body: some View {
        ForEach(avis) { ligne($0) }
    }

    private func ligne(_ avis: AvisEtape) -> some View {
        let membre = voyage.membre(uid: avis.auteurUID)
        let moi = avis.auteurUID == MoiVoyage.lire(voyage)
        let nom = membre?.nomAffiche ?? "Quelqu'un"
        return HStack(alignment: .top, spacing: 12) {
            AvatarView(initiales: Profil.initiales(de: nom), donnees: moi ? Profil.partage.avatar : membre?.avatar, taille: 36,
                       couleur: moi ? .accentColor : AvatarView.couleur(pour: avis.auteurUID))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moi ? "\(nom) (moi)" : nom).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(avis.modifieLe.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
                }
                if avis.etoiles > 0 {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { Image(systemName: $0 <= avis.etoiles ? "star.fill" : "star").font(.caption).foregroundStyle(.orange) }
                        }
                        Text("a noté \(avis.etoiles)/5").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if avis.envie != .neutre {
                    Label(avis.envie.libelle, systemImage: avis.envie.symbole)
                        .font(.caption.weight(.medium)).foregroundStyle(avis.envie.couleur)
                }
                if !avis.commentaire.isEmpty {
                    Text(avis.commentaire)
                        .font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Dans la fiche d'une étape : mon avis (étoiles, envie, un commentaire) puis ceux des autres voyageurs.
struct AvisEtapeSection: View {
    @Bindable var voyage: Voyage
    let etape: Etape
    @Environment(\.modelContext) private var contexte
    @State private var moi: String
    @State private var commentaire = ""

    init(voyage: Voyage, etape: Etape) {
        self.voyage = voyage
        self.etape = etape
        let moi = MoiVoyage.lire(voyage)
        _moi = State(initialValue: moi)
        _commentaire = State(initialValue: voyage.monAvis(sur: etape, moi: moi)?.commentaire ?? "")
    }

    private var membres: [Membre] { voyage.membres.sorted { $0.creeLe < $1.creeLe } }
    private var jeSuisIdentifie: Bool { membres.contains { $0.uid == moi } }
    private var monAvis: AvisEtape? { voyage.monAvis(sur: etape, moi: moi) }
    private var aDesAutres: Bool { !voyage.avis(de: etape).filter { $0.auteurUID != moi }.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profil renseigné : on sait déjà qui note, rien à demander.
            if !(Profil.partage.estRenseigne && jeSuisIdentifie) { choixIdentite }
            if jeSuisIdentifie { monAvisEditable }
            if aDesAutres {
                Divider()
                Text("Les autres voyageurs").font(.subheadline.weight(.semibold))
                ListeAvisEtape(voyage: voyage, etape: etape, sans: moi)
            }
        }
        .onAppear(perform: identifier)
    }

    /// Avec un profil renseigné, on retrouve (ou crée) mon voyageur sans rien demander.
    private func identifier() {
        guard Profil.partage.estRenseigne else { return }
        moi = Profil.partage.identifier(dans: voyage, contexte: contexte)
        commentaire = monAvis?.commentaire ?? ""
    }

    /// Seulement quand le profil n'est pas renseigné : choisir qui on est parmi les voyageurs.
    @ViewBuilder private var choixIdentite: some View {
        Picker("Qui es-tu ?", selection: $moi) {
            Text("—").tag("")
            ForEach(membres) { Text($0.nom).tag($0.uid) }
        }
        .onChange(of: moi) {
            MoiVoyage.ecrire(moi, voyage)
            commentaire = monAvis?.commentaire ?? ""
        }
        if membres.isEmpty {
            Text("Ajoute d'abord les participants du voyage (onglet Groupe).").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var monAvisEditable: some View {
        // Ma note : un second toucher sur la même étoile l'efface.
        HStack(spacing: 8) {
            Text("Ma note").lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            ForEach(1...5, id: \.self) { rang in
                Image(systemName: rang <= (monAvis?.etoiles ?? 0) ? "star.fill" : "star")
                    .font(.system(size: 22)).foregroundStyle(.orange)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy(duration: 0.15)) { choisirEtoiles(rang) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ma note : \(monAvis?.etoiles ?? 0) sur 5")
        .accessibilityAdjustableAction { sens in
            let n = monAvis?.etoiles ?? 0
            choisirEtoiles(sens == .increment ? min(n + 1, 5) : max(n - 1, 0), basculer: false)
        }

        // Mon envie : de « incontournable » à « pas envie ».
        HStack(spacing: 6) {
            ForEach(EnvieEtape.allCases) { envie in
                let choisi = (monAvis?.envie ?? .neutre) == envie
                Button { choisirEnvie(envie) } label: {
                    Label(envie.libelle, systemImage: envie.symbole)
                        .font(.caption.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(choisi ? Color.white : envie.couleur)
                        .background(choisi ? envie.couleur : envie.couleur.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }

        TextField("Mon commentaire (facultatif)", text: $commentaire, axis: .vertical)
            .lineLimit(2...5)
            .textFieldStyle(.plain)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(FondDePage.carte))
            .onChange(of: commentaire) { enregistrer { $0.commentaire = commentaire } }
    }

    /// Retrouve mon avis ou le crée, applique le changement ; un avis redevenu vide est supprimé.
    private func enregistrer(_ modification: (AvisEtape) -> Void) {
        guard jeSuisIdentifie else { return }
        let avis = monAvis ?? {
            let nouveau = AvisEtape(etapeUID: etape.uid, auteurUID: moi)
            nouveau.voyage = voyage
            contexte.insert(nouveau)
            return nouveau
        }()
        modification(avis)
        avis.modifieLe = .now
        if avis.estVide { contexte.delete(avis) }
    }

    private func choisirEtoiles(_ rang: Int, basculer: Bool = true) {
        enregistrer { $0.etoiles = (basculer && $0.etoiles == rang) ? 0 : rang }
    }

    private func choisirEnvie(_ envie: EnvieEtape) {
        enregistrer { $0.envie = envie }
    }
}
