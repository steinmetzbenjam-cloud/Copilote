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

/// Fenêtre d'avis sur une étape : le mien (étoiles, envie, un mot) et ceux des autres voyageurs.
struct AvisEtapeView: View {
    @Bindable var voyage: Voyage
    let etape: Etape
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
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
    private var autres: [AvisEtape] {
        voyage.avis(de: etape).filter { $0.auteurUID != moi }.sorted { voyage.nomMembre($0.auteurUID) < voyage.nomMembre($1.auteurUID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Qui es-tu ?", selection: $moi) {
                        Text("—").tag("")
                        ForEach(membres) { Text($0.nom).tag($0.uid) }
                    }
                    .onChange(of: moi) {
                        MoiVoyage.ecrire(moi, voyage)
                        commentaire = monAvis?.commentaire ?? ""
                    }
                } footer: {
                    if membres.isEmpty { Text("Ajoute d'abord les participants du voyage (onglet Infos ou Dépenses).") }
                }

                if jeSuisIdentifie {
                    Section("Mon avis") {
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { rang in
                                Image(systemName: rang <= (monAvis?.etoiles ?? 0) ? "star.fill" : "star")
                                    .font(.title2).foregroundStyle(.orange)
                                    .onTapGesture { choisirEtoiles(rang) }
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Étoiles : \(monAvis?.etoiles ?? 0) sur 5")
                        .accessibilityAdjustableAction { sens in
                            let n = monAvis?.etoiles ?? 0
                            choisirEtoiles(sens == .increment ? min(n + 1, 5) : max(n - 1, 0), basculer: false)
                        }

                        Picker("Envie", selection: Binding(get: { monAvis?.envie ?? .neutre }, set: { choisirEnvie($0) })) {
                            ForEach(EnvieEtape.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()

                        TextField("Un mot (facultatif)", text: $commentaire, axis: .vertical)
                            .lineLimit(1...4)
                            .onChange(of: commentaire) { enregistrer { $0.commentaire = commentaire } }
                    }
                }

                Section("Avis du groupe") {
                    if autres.isEmpty {
                        Text("Personne d'autre n'a encore donné son avis.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(autres) { avis in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(voyage.nomMembre(avis.auteurUID)).font(.headline)
                                Spacer()
                                if avis.envie != .neutre {
                                    Label(avis.envie.libelle, systemImage: avis.envie.symbole)
                                        .font(.caption.weight(.medium)).foregroundStyle(avis.envie.couleur)
                                }
                            }
                            if avis.etoiles > 0 {
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { Image(systemName: $0 <= avis.etoiles ? "star.fill" : "star").font(.caption).foregroundStyle(.orange) }
                                }
                            }
                            if !avis.commentaire.isEmpty { Text(avis.commentaire).font(.subheadline) }
                        }
                    }
                }
            }
            .navigationTitle(etape.titre.isEmpty ? "Étape" : etape.titre)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
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
