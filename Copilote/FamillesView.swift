import SwiftUI
import SwiftData
import PhotosUI

/// Cadre « Familles et voyageurs » de l'onglet Infos : les familles, leurs membres, leur âge,
/// et celles et ceux qui ont reçu une invitation dans l'app.
struct CadreFamilles: View {
    @Bindable var voyage: Voyage
    var onMoi: () -> Void
    @Environment(\.modelContext) private var contexte
    @State private var membreEnEdition: Membre?
    @State private var familleEnEdition: ChoixFamille?
    /// Famille survolée pendant un glisser-déposer (chaîne vide : la zone « Sans famille »).
    @State private var cible: String?
    private var profil = Profil.partage

    /// La famille que l'on modifie, ou une nouvelle (nom nil).
    private struct ChoixFamille: Identifiable {
        let id = UUID()
        var nom: String?
    }

    init(voyage: Voyage, onMoi: @escaping () -> Void) {
        self.voyage = voyage
        self.onMoi = onMoi
    }

    var body: some View {
        CadreInfos(titre: "Familles et voyageurs (\(voyage.membres.count))", symbole: "person.3.fill",
                   couleur: Color(rouge: 0x06, vert: 0xB6, bleu: 0xD4),
                   pied: "Le budget se calcule par famille et par personne, selon l'âge. Pour un voyageur invité dans l'app, indique l'e-mail de son invitation : ses règlements seront rattachés à sa famille.") {
            ForEach(voyage.familles) { famille in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VignetteFamille(photo: voyage.photo(famille: famille.nom), nom: famille.nom, taille: 30)
                        Text(famille.nom).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Modifier la famille", systemImage: "pencil") { familleEnEdition = ChoixFamille(nom: famille.nom) }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        Button("Ajouter un membre", systemImage: "plus.circle") { ajouterMembre(famille: famille.nom) }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.tint)
                    }
                    ForEach(famille.membres) { ligne($0) }
                }
                .padding(.vertical, 4)
                .modifier(ZoneDeDepot(actif: cible == famille.nom)) 
                .dropDestination(for: String.self) { uids, _ in deposer(uids, dans: famille.nom) } isTargeted: { cible = $0 ? famille.nom : (cible == famille.nom ? nil : cible) }
                Divider()
            }
            if !voyage.membresSansFamille.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !voyage.familles.isEmpty {
                        Label("Sans famille", systemImage: "person.fill").font(.subheadline.weight(.semibold))
                    }
                    ForEach(voyage.membresSansFamille) { ligne($0) }
                }
                .padding(.vertical, 4)
                .modifier(ZoneDeDepot(actif: cible == ""))
                .dropDestination(for: String.self) { uids, _ in deposer(uids, dans: nil) } isTargeted: { cible = $0 ? "" : (cible == "" ? nil : cible) }
                Divider()
            }
            HStack(spacing: 16) {
                Button("Ajouter une famille", systemImage: "house.fill") { familleEnEdition = ChoixFamille(nom: nil) }
                Button("Ajouter un voyageur", systemImage: "person.badge.plus") { ajouterMembre(famille: nil) }
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $membreEnEdition, onDismiss: nettoyer) { membre in
            MembreEditView(membre: membre, voyage: voyage, estMoi: membre.uid == MoiVoyage.lire(voyage), onMoi: onMoi)
        }
        .sheet(item: $familleEnEdition) { choix in
            FamilleEditView(voyage: voyage, existante: choix.nom) { nom in
                // On laisse la feuille se refermer avant d'ouvrir la fiche du premier membre.
                if choix.nom == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ajouterMembre(famille: nom) } }
            }
        }
    }

    private func ligne(_ membre: Membre) -> some View {
        let moi = membre.uid == MoiVoyage.lire(voyage)
        // Pas de Button : il avale le geste de glisser. Un simple toucher ouvre la fiche, un appui prolongé (iPhone, iPad) ou un glisser (Mac) déplace.
        return HStack(spacing: 10) {
                RondMembre(membre: membre, voyage: voyage, taille: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(membre.nom).foregroundStyle(.primary)
                        if moi { Text("(moi)").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Text([membre.age.map { "\($0) ans" }, membre.tarif.libelle].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if !(membre.emailInvitation ?? "").isEmpty || !(membre.email ?? "").isEmpty {
                    Image(systemName: "envelope.badge.fill").foregroundStyle(.tint).accessibilityLabel("Invité dans l'app")
                }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { membreEnEdition = membre }
        .draggable(Self.charge + membre.uid) {
            Text(membre.nom).padding(8).background(.regularMaterial, in: Capsule())
        }
        .accessibilityAddTraits(.isButton)
    }

    private static let charge = "membre:"

    /// Range les voyageurs glissés dans la famille (nil : sans famille). Ignore tout ce qui n'est pas un voyageur de ce voyage.
    private func deposer(_ textes: [String], dans famille: String?) -> Bool {
        var change = false
        for texte in textes where texte.hasPrefix(Self.charge) {
            let uid = String(texte.dropFirst(Self.charge.count))
            guard let membre = voyage.membre(uid: uid), membre.famille != (famille ?? "") else { continue }
            membre.familleNom = famille
            change = true
        }
        return change
    }

    private func ajouterMembre(famille: String?) {
        let membre = Membre(nom: "")
        membre.familleNom = famille
        membre.voyage = voyage
        contexte.insert(membre)
        membreEnEdition = membre
    }

    /// Un voyageur créé puis laissé sans prénom est retiré à la fermeture de sa fiche.
    private func nettoyer() {
        for membre in voyage.membres where membre.nom.trimmingCharacters(in: .whitespaces).isEmpty { contexte.delete(membre) }
    }
}

/// Fiche d'un voyageur : prénom, âge, famille, tarif et invitation dans l'app.
struct MembreEditView: View {
    @Bindable var membre: Membre
    var voyage: Voyage
    var estMoi: Bool
    var onMoi: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var choixPhoto: PhotosPickerItem?

    private var ageTexte: Binding<String> {
        Binding(get: { membre.age.map(String.init) ?? "" },
                set: { membre.age = Int($0.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 && $0 < 130 ? $0 : nil } })
    }

    private var familleTexte: Binding<String> {
        Binding(get: { membre.familleNom ?? "" }, set: { membre.familleNom = $0.isEmpty ? nil : $0 })
    }

    private var tarifChoisi: Binding<String> {
        Binding(get: { membre.tarifBrut ?? "" }, set: { membre.tarifBrut = $0.isEmpty ? nil : $0 })
    }

    private var emailInvitation: Binding<String> {
        Binding(get: { membre.emailInvitation ?? "" }, set: { membre.emailInvitation = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        RondMembre(membre: membre, voyage: voyage, taille: 88)
                        if !estMoi {
                            HStack(spacing: 16) {
                                PhotosPicker(selection: $choixPhoto, matching: .images) {
                                    Label(membre.avatar == nil ? "Ajouter une photo" : "Changer la photo", systemImage: "photo")
                                }
                                if membre.avatar != nil { Button("Retirer", role: .destructive) { membre.avatar = nil; choixPhoto = nil } }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section {
                    TextField("Prénom", text: $membre.nom)
                    LabeledContent("Âge") {
                        TextField("—", text: ageTexte)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    LabeledContent("Famille") {
                        HStack(spacing: 6) {
                            TextField("Aucune", text: familleTexte).multilineTextAlignment(.trailing)
                            if !voyage.familles.isEmpty {
                                Menu {
                                    Button("Aucune") { membre.familleNom = nil }
                                    ForEach(voyage.familles) { f in Button(f.nom) { membre.familleNom = f.nom } }
                                } label: { Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section {
                    Picker("Tarif", selection: tarifChoisi) {
                        Text("Selon l'âge (\(Tarif.pour(age: membre.age).libelle))").tag("")
                        ForEach(Tarif.allCases) { Text($0.libelle).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Détermine le prix retenu pour cette personne : adulte, étudiant ou enfant. Sans choix, l'enfant va jusqu'à \(Tarif.ageEnfantMax) ans.")
                }
                Section {
                    if estMoi {
                        Label("C'est toi : ce voyageur est relié à ton profil sur cet appareil.", systemImage: "person.crop.circle.badge.checkmark")
                        Button("Mon profil", systemImage: "person.crop.circle") {
                            dismiss()
                            onMoi()
                        }
                    } else {
                        TextField("E-mail de l'invitation", text: emailInvitation)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif
                        if let email = membre.email, !email.isEmpty {
                            LabeledContent("Profil relié", value: email)
                        }
                        Button("C'est moi", systemImage: "person.fill.checkmark") {
                            MoiVoyage.ecrire(membre.uid, voyage)
                            Profil.partage.publier(dans: contexte)
                            dismiss()
                        }
                    }
                } header: {
                    Text("Invitation dans l'app")
                } footer: {
                    Text("Quand cette personne ouvre le voyage avec le même e-mail dans son profil, l'app la reconnaît : ses règlements sont rattachés à sa famille. Laisse vide si elle n'utilise pas l'app.")
                }
                Section {
                    Button("Retirer du voyage", role: .destructive) {
                        contexte.delete(membre)
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(membre.nom.isEmpty ? "Nouveau voyageur" : membre.nom)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onChange(of: choixPhoto) { _, nouveau in
                guard let nouveau else { return }
                Task {
                    if let donnees = try? await nouveau.loadTransferable(type: Data.self), let reduite = Profil.reduire(donnees) { membre.avatar = reduite }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
    }
}

/// Cadre qui s'allume quand un voyageur est glissé au-dessus.
private struct ZoneDeDepot: ViewModifier {
    var actif: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(actif ? Color.accentColor.opacity(0.15) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(actif ? Color.accentColor : .clear, lineWidth: 1.5))
            .padding(.horizontal, -6)
    }
}
