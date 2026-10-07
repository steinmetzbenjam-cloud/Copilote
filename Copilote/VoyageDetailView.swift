import SwiftUI
import SwiftData

struct VoyageDetailView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var nouveauMembre = ""
    @State private var paysAAjouter = ""
    @State private var profilOuvert = false
    private var profil = Profil.partage

    init(voyage: Voyage) { self.voyage = voyage }

    private var membresTries: [Membre] {
        voyage.membres.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        Form {
            Section("Voyage") {
                TextField("Titre", text: $voyage.titre)
            }

            Section {
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
            } header: {
                Text("Pays")
            } footer: {
                Text("La carte et la recherche de lieux se centrent sur ces pays.")
            }

            SectionPartage(voyage: voyage)

            Section("Dates") {
                DatePicker("Départ", selection: $voyage.debut, displayedComponents: .date)
                DatePicker("Retour", selection: $voyage.fin, in: voyage.debut..., displayedComponents: .date)
                LabeledContent("Durée", value: "\(voyage.nombreDeJours) jour\(voyage.nombreDeJours > 1 ? "s" : "")")
            }

            Section("Mon profil") {
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
                }
                .buttonStyle(.plain)
                if profil.estRenseigne && MoiVoyage.lire(voyage).isEmpty {
                    Button("M'ajouter aux voyageurs : \(profil.prenom)", systemImage: "person.badge.plus") {
                        let membre = Membre(nom: profil.prenom)
                        membre.voyage = voyage
                        contexte.insert(membre)
                        MoiVoyage.ecrire(membre.uid, voyage)
                    }
                }
            }

            Section("Voyageurs (\(voyage.membres.count))") {
                ForEach(membresTries) { membre in
                    HStack(spacing: 10) {
                        let moi = membre.uid == MoiVoyage.lire(voyage)
                        AvatarView(initiales: Profil.initiales(de: membre.nom), donnees: moi ? profil.avatar : nil, taille: 28,
                                   couleur: moi ? .accentColor : AvatarView.couleur(pour: membre.uid))
                        Text(membre.nom)
                        if moi { Text("(moi)").font(.footnote).foregroundStyle(.secondary) }
                    }
                        .contextMenu {
                            Button("Retirer", role: .destructive) { contexte.delete(membre) }
                        }
                }
                .onDelete { indices in
                    for i in indices { contexte.delete(membresTries[i]) }
                }
                HStack {
                    TextField("Ajouter un voyageur", text: $nouveauMembre)
                        .onSubmit(ajouterMembre)
                    Button("Ajouter", action: ajouterMembre)
                        .disabled(nouveauMembre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Notes") {
                TextEditor(text: $voyage.notes)
                    .frame(minHeight: 100)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $profilOuvert) { ProfilEditView() }
        .onChange(of: voyage.debut) { _, debut in
            if voyage.fin < debut { voyage.fin = debut }
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
