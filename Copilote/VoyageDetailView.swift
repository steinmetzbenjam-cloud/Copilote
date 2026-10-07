import SwiftUI
import SwiftData

struct VoyageDetailView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var nouveauMembre = ""
    @State private var paysAAjouter = ""
    @State private var profilOuvert = false
    @State private var membreAffiche: Membre?
    private var profil = Profil.partage

    init(voyage: Voyage) { self.voyage = voyage }

    private var membresTries: [Membre] {
        voyage.membres.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                cadreProfil
                cadreVoyageEtDates
                CadreInfos(titre: "Monnaie locale", symbole: "coloncurrencysign.circle.fill", couleur: .orange) {
                    SectionMonnaie(voyage: voyage)
                }
                CadreInfos(titre: "Partage avec le groupe", symbole: "person.2.fill", couleur: .pink) {
                    SectionPartage(voyage: voyage)
                }
                cadreVoyageurs
                CadreInfos(titre: "Notes", symbole: "note.text", couleur: .brown) {
                    TextEditor(text: $voyage.notes)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
        .sheet(isPresented: $profilOuvert) { ProfilEditView() }
        .sheet(item: $membreAffiche) { ProfilMembreView(membre: $0) }
        .onChange(of: voyage.debut) { _, debut in
            if voyage.fin < debut { voyage.fin = debut }
        }
    }

    // MARK: Cadres

    private var cadreProfil: some View {
        CadreInfos(titre: "Mon profil", symbole: "person.crop.circle.fill", couleur: Color(rouge: 0x5B, vert: 0x6C, bleu: 0xFF)) {
            Button { profilOuvert = true } label: {
                HStack(spacing: 12) {
                    AvatarView(initiales: profil.initiales, donnees: profil.avatar, taille: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profil.nomComplet.isEmpty ? "Renseigner mon profil" : profil.nomComplet).foregroundStyle(.primary)
                        if !profil.email.isEmpty { Text(profil.email).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if profil.estRenseigne && MoiVoyage.lire(voyage).isEmpty {
                Button("M'ajouter aux voyageurs : \(profil.prenom)", systemImage: "person.badge.plus") {
                    let membre = Membre(nom: profil.prenom)
                    membre.voyage = voyage
                    contexte.insert(membre)
                    MoiVoyage.ecrire(membre.uid, voyage)
                    profil.publier(dans: contexte)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Le titre, les pays et les dates du voyage, dans un seul cadre.
    private var cadreVoyageEtDates: some View {
        CadreInfos(titre: "Voyage", symbole: "suitcase.fill", couleur: Color(rouge: 0xFF, vert: 0x7A, bleu: 0x59)) {
            TextField("Titre", text: $voyage.titre)
                .textFieldStyle(.roundedBorder)
            Divider()
            pays
            Divider()
            DatePicker("Départ", selection: $voyage.debut, displayedComponents: .date)
            DatePicker("Retour", selection: $voyage.fin, in: voyage.debut..., displayedComponents: .date)
            LabeledContent("Durée", value: "\(voyage.nombreDeJours) jour\(voyage.nombreDeJours > 1 ? "s" : "")")
        }
    }

    /// Les pays du voyage : liste, ajout, et une note sur leur effet sur la carte.
    @ViewBuilder private var pays: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pays", systemImage: "flag.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(voyage.pays, id: \.self) { code in
                if let pays = Pays.avec(code: code) {
                    HStack {
                        Text(pays.drapeau)
                        Text(pays.nom)
                        Spacer()
                        Button("Retirer", systemImage: "xmark.circle.fill") {
                            voyage.pays.removeAll { $0 == code }
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    }
                }
            }
            Picker(voyage.pays.isEmpty ? "Choisir un pays" : "Ajouter un pays", selection: $paysAAjouter) {
                Text("—").tag("")
                ForEach(Pays.tous.filter { !voyage.pays.contains($0.code) }) { pays in
                    Text("\(pays.drapeau)  \(pays.nom)").tag(pays.code)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: paysAAjouter) { _, code in
                guard !code.isEmpty else { return }
                voyage.pays.append(code)
                paysAAjouter = ""
            }
            Text("La carte et la recherche de lieux se centrent sur ces pays.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var cadreVoyageurs: some View {
        CadreInfos(titre: "Voyageurs (\(voyage.membres.count))", symbole: "person.3.fill", couleur: Color(rouge: 0x06, vert: 0xB6, bleu: 0xD4)) {
            ForEach(membresTries) { membre in
                let moi = membre.uid == MoiVoyage.lire(voyage)
                HStack(spacing: 10) {
                    AvatarView(initiales: Profil.initiales(de: membre.nomAffiche), donnees: moi ? profil.avatar : membre.avatar, taille: 28,
                               couleur: moi ? .accentColor : AvatarView.couleur(pour: membre.uid))
                    Text(membre.nomAffiche)
                    if moi { Text("(moi)").font(.footnote).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Retirer", systemImage: "xmark.circle.fill") { contexte.delete(membre) }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary).buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { if moi { profilOuvert = true } else { membreAffiche = membre } }
                .contextMenu {
                    Button("Retirer", role: .destructive) { contexte.delete(membre) }
                }
            }
            HStack {
                TextField("Ajouter un voyageur", text: $nouveauMembre)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(ajouterMembre)
                Button("Ajouter", action: ajouterMembre)
                    .disabled(nouveauMembre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func ajouterMembre() {
        let nom = nouveauMembre.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        let membre = Membre(nom: nom)
        membre.voyage = voyage
        contexte.insert(membre)
        nouveauMembre = ""
    }
}

/// Un cadre de l'onglet Infos : un titre coloré avec son icône, puis le contenu, sur une carte.
struct CadreInfos<Contenu: View>: View {
    let titre: String
    let symbole: String
    var couleur: Color = .accentColor
    var pied: String?
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(titre, systemImage: symbole).font(.headline).foregroundStyle(couleur)
            contenu
            if let pied { Text(pied).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
        .overlay(alignment: .leading) {
            Capsule().fill(couleur).frame(width: 4).padding(.vertical, 14).padding(.leading, 4)
        }
    }
}
