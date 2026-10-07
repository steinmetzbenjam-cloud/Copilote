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
            HStack {
                Text("Qui es-tu ?").foregroundStyle(.secondary)
                Spacer()
                Picker("Qui es-tu ?", selection: $moi) {
                    Text("—").tag("")
                    ForEach(membres) { Text($0.nom).tag($0.uid) }
                }
                .labelsHidden()
                .onChange(of: moi) { MoiVoyage.ecrire(moi, voyage) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollViewReader { lecteur in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if messages.isEmpty {
                            Text("Aucun message. Donne ton avis sur le déroulé du voyage : les autres le verront.")
                                .font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(24)
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.uid) { rang, message in
                            let precedent = rang > 0 ? messages[rang - 1] : nil
                            bulle(message, premierDuGroupe: precedent?.auteurUID != message.auteurUID)
                                .id(message.uid)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .background(FondDePage.couleur)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.count) {
                    if let dernier = messages.last { withAnimation { lecteur.scrollTo(dernier.uid, anchor: .bottom) } }
                }
            }
            Divider()
            saisie
        }
    }

    /// Mes messages à droite (couleur d'accent), ceux des autres à gauche, comme dans une messagerie.
    private func bulle(_ message: Commentaire, premierDuGroupe: Bool) -> some View {
        let mien = message.auteurUID == moi
        return HStack(spacing: 0) {
            if mien { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 2) {
                if !mien && premierDuGroupe {
                    Text(voyage.nomMembre(message.auteurUID)).font(.caption.bold()).foregroundStyle(Self.couleurAuteur(message.auteurUID))
                }
                Text(message.texte).textSelection(.enabled)
                Text(message.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(mien ? Color.white.opacity(0.75) : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(mien ? Color.white : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(mien ? Color.accentColor : Color(white: 0.5).opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contextMenu {
                if mien { Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(message) } }
            }
            if !mien { Spacer(minLength: 48) }
        }
        .padding(.top, premierDuGroupe ? 6 : 0)
    }

    /// Une couleur stable par auteur, pour les distinguer dans la discussion.
    private static func couleurAuteur(_ uid: String) -> Color {
        let palette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown, .green]
        let somme = uid.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 }
        return palette[somme % palette.count]
    }

    private var saisie: some View {
        HStack(alignment: .bottom, spacing: 8) {
            #if os(macOS)
            // Entrée va à la ligne ; l'envoi se fait avec le bouton.
            TextEditor(text: $brouillon)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .frame(minHeight: 30, maxHeight: 100)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.separator))
                .overlay(alignment: .topLeading) {
                    if brouillon.isEmpty {
                        Text(jeSuisIdentifie ? "Ton avis sur la préparation…" : "Choisis d'abord qui tu es")
                            .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 5).allowsHitTesting(false)
                    }
                }
                .disabled(!jeSuisIdentifie)
            #else
            TextField(jeSuisIdentifie ? "Ton avis sur la préparation…" : "Choisis d'abord qui tu es", text: $brouillon, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(!jeSuisIdentifie)
            #endif
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
