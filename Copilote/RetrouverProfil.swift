import SwiftUI
import SwiftData

/// Une personne des voyages de cet appareil : ses voyageurs (un par voyage), réunis par e-mail ou, à défaut, par nom.
struct PersonneConnue: Identifiable {
    let id: String
    var membres: [Membre]

    /// Le voyageur le plus complet sert de modèle : celui qui a un e-mail, sinon le plus ancien.
    var reference: Membre {
        membres.min { a, b in
            let ea = Self.courriel(de: a) != nil, eb = Self.courriel(de: b) != nil
            return ea != eb ? ea : a.creeLe < b.creeLe
        }!
    }
    var nomAffiche: String { reference.nomAffiche }
    var email: String? { membres.lazy.compactMap(Self.courriel(de:)).first }
    var avatar: Data? { membres.lazy.compactMap(\.avatar).first }
    var titresVoyages: [String] {
        var vus = Set<String>()
        return membres.compactMap { $0.voyage }.sorted { $0.debut < $1.debut }.map(\.titre).filter { vus.insert($0).inserted }
    }

    static func normaliser(_ texte: String?) -> String {
        (texte ?? "").trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// L'e-mail du profil, sinon celui de l'invitation.
    static func courriel(de membre: Membre) -> String? {
        [membre.email, membre.emailInvitation].lazy.map { ($0 ?? "").trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// Réunit les voyageurs de tous les voyages : même e-mail, ou même nom quand l'un d'eux n'en a pas.
    static func regrouper(_ membres: [Membre]) -> [PersonneConnue] {
        var personnes: [PersonneConnue] = []
        let avecNom = membres.filter { $0.voyage != nil && !normaliser($0.nom).isEmpty }
        let (avecCourriel, sansCourriel) = (avecNom.filter { courriel(de: $0) != nil }, avecNom.filter { courriel(de: $0) == nil })
        for membre in avecCourriel {
            let cle = "@" + normaliser(courriel(de: membre))
            if let i = personnes.firstIndex(where: { $0.id == cle }) { personnes[i].membres.append(membre) }
            else { personnes.append(PersonneConnue(id: cle, membres: [membre])) }
        }
        for membre in sansCourriel {
            let nom = normaliser(membre.nomAffiche)
            if let i = personnes.firstIndex(where: { p in p.membres.contains { normaliser($0.nomAffiche) == nom } }) {
                personnes[i].membres.append(membre)
            } else {
                personnes.append(PersonneConnue(id: "#" + nom, membres: [membre]))
            }
        }
        return personnes.sorted { $0.nomAffiche.localizedStandardCompare($1.nomAffiche) == .orderedAscending }
    }
}

extension Profil {
    /// « C'est moi » : je reprends le profil de cette personne, et je deviens son voyageur dans chacun de ses voyages.
    /// Le voyageur qui me représentait jusque-là sur cet appareil (un doublon) est retiré s'il n'a encore rien fait.
    /// Renvoie le nombre de doublons laissés en place parce qu'ils ont déjà des dépenses, des messages, des avis…
    @discardableResult
    func adopter(_ personne: PersonneConnue, contexte: ModelContext) -> Int {
        let ref = personne.reference
        prenom = ref.nom.trimmingCharacters(in: .whitespaces)
        nom = (ref.nomFamille ?? "").trimmingCharacters(in: .whitespaces)
        email = personne.email ?? ""
        avatar = personne.avatar
        var gardes = 0
        let parVoyage = Dictionary(grouping: personne.membres) { $0.voyage?.uid ?? "" }
        for (_, candidats) in parVoyage {
            guard let voyage = candidats.first?.voyage else { continue }
            let ancien = MoiVoyage.lire(voyage)
            // Dans un même voyage, on garde celui qui n'est pas mon doublon d'ici, puis le plus complet.
            let choisi = candidats.min { a, b in
                if (a.uid == ancien) != (b.uid == ancien) { return b.uid == ancien }
                let ea = PersonneConnue.courriel(de: a) != nil, eb = PersonneConnue.courriel(de: b) != nil
                return ea != eb ? ea : a.creeLe < b.creeLe
            }!
            // Seulement un vrai doublon (même prénom ou même e-mail) : jamais une autre personne reliée par erreur.
            if ancien != choisi.uid, let doublon = voyage.membre(uid: ancien),
               PersonneConnue.normaliser(doublon.nom) == PersonneConnue.normaliser(ref.nom)
                || (PersonneConnue.courriel(de: doublon).map(PersonneConnue.normaliser) == personne.email.map(PersonneConnue.normaliser)
                    && personne.email != nil) {
                if voyage.aDesTraces(de: ancien) { gardes += 1 } else { contexte.delete(doublon) }
            }
            MoiVoyage.ecrire(choisi.uid, voyage)
        }
        publier(dans: contexte)
        return gardes
    }
}

extension Voyage {
    /// Ce voyageur a-t-il déjà laissé quelque chose dans le voyage (dépense, message, avis, vote, document) ?
    func aDesTraces(de uid: String) -> Bool {
        depenses.contains { $0.payeurUID == uid || $0.parts.contains { $0.membreUID == uid } }
            || commentaires.contains { $0.auteurUID == uid }
            || avisEtapes.contains { $0.auteurUID == uid }
            || sondages.contains { $0.auteurUID == uid }
            || votes.contains { $0.auteurUID == uid }
            || documents.contains { $0.membreUID == uid }
    }
}

/// « Je suis déjà inscrit » : sur un nouvel appareil, je me retrouve parmi les voyageurs de mes voyages
/// (par mon nom ou mon e-mail) au lieu de créer une deuxième personne.
struct RetrouverProfilView: View {
    var onTermine: () -> Void
    @Environment(\.modelContext) private var contexte
    @Query private var membres: [Membre]
    @State private var email = ""
    @State private var choisie: PersonneConnue?
    @State private var doublonsGardes = 0
    private var cloud = PartageCloud.shared

    init(onTermine: @escaping () -> Void) {
        self.onTermine = onTermine
    }

    private var personnes: [PersonneConnue] { PersonneConnue.regrouper(membres) }

    private var cherche: String { PersonneConnue.normaliser(email) }

    private var trouvees: [PersonneConnue] {
        guard !cherche.isEmpty else { return personnes }
        return personnes.filter { p in
            p.membres.contains { m in [m.email, m.emailInvitation].contains { PersonneConnue.normaliser($0) == cherche } }
        }
    }

    var body: some View {
        Form {
            if PartageCloud.disponible && !cloud.actif {
                Section {
                    Button("Activer la synchronisation iCloud", systemImage: "icloud") { cloud.definirActif(true) }
                } footer: {
                    Text("Tes voyages arrivent sur cet appareil par iCloud : active la synchronisation pour t'y retrouver.")
                }
            } else if cloud.actif && cloud.synchroEnCours {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Récupération de tes voyages…").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField("Mon e-mail", text: $email)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
            } header: {
                Text("Me retrouver avec mon e-mail")
            } footer: {
                Text("Celui de ton profil sur ton autre appareil, ou celui avec lequel on t'a invité. Laisse vide pour voir tout le monde.")
            }
            Section {
                if trouvees.isEmpty {
                    Text(personnes.isEmpty
                         ? "Aucun voyage sur cet appareil pour l'instant. Avec le même compte iCloud, ils arrivent tout seuls une fois la synchronisation activée ; avec un autre compte, ouvre d'abord le lien d'invitation du voyage."
                         : "Personne avec cet e-mail dans tes voyages. Vérifie l'adresse, ou choisis ton nom en laissant le champ vide.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(trouvees) { personne in
                    Button { choisie = personne } label: { ligne(personne) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Choisir mon nom")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Déjà inscrit")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(choisie.map { "Es-tu « \($0.nomAffiche) » ?" } ?? "",
                            isPresented: Binding(get: { choisie != nil }, set: { if !$0 { choisie = nil } }),
                            titleVisibility: .visible, presenting: choisie) { personne in
            Button("Oui, c'est moi") {
                doublonsGardes = Profil.partage.adopter(personne, contexte: contexte)
                if doublonsGardes == 0 { onTermine() }
            }
        } message: { personne in
            Text("Cet appareil te reconnaîtra dans \(personne.titresVoyages.count > 1 ? "ces voyages" : "ce voyage") : \(personne.titresVoyages.joined(separator: ", ")).")
        }
        .alert("C'est noté", isPresented: Binding(get: { doublonsGardes > 0 }, set: { if !$0 { doublonsGardes = 0; onTermine() } })) {
            Button("OK") {}
        } message: {
            Text("Cet appareil t'avait déjà ajouté comme nouveau voyageur dans \(doublonsGardes > 1 ? "\(doublonsGardes) voyages" : "un voyage"), avec des dépenses, des messages ou des avis : ce doublon est resté dans l'onglet Groupe, où tu peux le supprimer.")
        }
    }

    private func ligne(_ personne: PersonneConnue) -> some View {
        HStack(spacing: 12) {
            AvatarView(initiales: Profil.initiales(de: personne.nomAffiche), donnees: personne.avatar, taille: 40,
                       couleur: AvatarView.couleur(pour: personne.reference.uid))
            VStack(alignment: .leading, spacing: 2) {
                Text(personne.nomAffiche).foregroundStyle(.primary)
                if let email = personne.email { Text(email).font(.footnote).foregroundStyle(.secondary) }
                Text(personne.titresVoyages.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
