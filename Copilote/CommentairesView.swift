import SwiftUI
import SwiftData

/// Fenêtre de discussion : chacun donne son avis sur la préparation du voyage.
struct CommentairesView: View {
    @Bindable var voyage: Voyage
    /// Affichée comme un cadre flottant (sans feuille ni barre de navigation), par-dessus la carte.
    var enCadre = false
    /// En cadre : l'état d'ouverture à remettre à faux pour fermer.
    var ouverte: Binding<Bool>?
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var fermer
    @State private var moi: String
    @State private var brouillon = ""
    @State private var nouveauVoyageur = ""

    init(voyage: Voyage, enCadre: Bool = false, ouverte: Binding<Bool>? = nil) {
        self.voyage = voyage
        self.enCadre = enCadre
        self.ouverte = ouverte
        _moi = State(initialValue: MoiVoyage.lire(voyage))
    }

    private var membres: [Membre] { voyage.membres.sorted { $0.creeLe < $1.creeLe } }
    private var messages: [Commentaire] { voyage.commentaires.sorted { $0.date < $1.date } }
    private var jeSuisIdentifie: Bool { membres.contains { $0.uid == moi } }

    var body: some View {
        if enCadre { cadre } else { feuille }
    }

    private var cadre: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Discussion", systemImage: "bubble.left.and.bubble.right").font(.headline)
                Spacer()
                Button { ouverte?.wrappedValue = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if membres.isEmpty { aucunVoyageur } else { discussion }
        }
        .modifier(FondDeCarte())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var feuille: some View {
        NavigationStack {
            Group {
                if membres.isEmpty { aucunVoyageur } else { discussion }
            }
            .navigationTitle("Discussion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private var aucunVoyageur: some View {
        Form {
            Section {
                HStack {
                    TextField("Ton prénom", text: $nouveauVoyageur)
                        .onSubmit(ajouterVoyageur)
                        .autocorrectionDisabled()
                    Button("Ajouter", action: ajouterVoyageur)
                        .disabled(nouveauVoyageur.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Ajoute les participants du voyage (onglet Infos ou Dépenses) pour pouvoir échanger.")
            }
        }
    }

    private var discussion: some View {
        VStack(spacing: 0) {
            ScrollViewReader { lecteur in
                List {
                    Section {
                        Picker("Qui es-tu ?", selection: $moi) {
                            Text("—").tag("")
                            ForEach(membres) { Text($0.nom).tag($0.uid) }
                        }
                        .onChange(of: moi) { MoiVoyage.ecrire(moi, voyage) }
                    }
                    Section {
                        if messages.isEmpty {
                            Text("Aucun message. Donne ton avis sur le déroulé du voyage : les autres le verront.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(messages) { message in
                            bulle(message).id(message.uid)
                                .swipeActions {
                                    if message.auteurUID == moi {
                                        Button("Supprimer", role: .destructive) { contexte.delete(message) }
                                    }
                                }
                        }
                    }
                }
                .onChange(of: messages.count) {
                    if let dernier = messages.last { withAnimation { lecteur.scrollTo(dernier.uid, anchor: .bottom) } }
                }
            }
            Divider()
            saisie
        }
    }

    private func bulle(_ message: Commentaire) -> some View {
        let mien = message.auteurUID == moi
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(voyage.nomMembre(message.auteurUID)).font(.caption.bold()).foregroundStyle(mien ? Color.accentColor : .secondary)
                Text(message.date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(message.texte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if mien { Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(message) } }
        }
    }

    private var saisie: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(jeSuisIdentifie ? "Ton avis sur la préparation…" : "Choisis d'abord qui tu es", text: $brouillon, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(!jeSuisIdentifie)
            Button(action: envoyer) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.borderless)
            .disabled(!jeSuisIdentifie || brouillon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private func envoyer() {
        let texte = brouillon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, jeSuisIdentifie else { return }
        let message = Commentaire(texte: texte, auteurUID: moi)
        message.voyage = voyage
        contexte.insert(message)
        brouillon = ""
    }

    private func ajouterVoyageur() {
        let nom = nouveauVoyageur.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        let membre = Membre(nom: nom)
        membre.voyage = voyage
        contexte.insert(membre)
        if moi.isEmpty { moi = membre.uid; MoiVoyage.ecrire(moi, voyage) }
        nouveauVoyageur = ""
    }
}
