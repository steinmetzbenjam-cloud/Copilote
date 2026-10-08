import SwiftUI
import SwiftData

/// Le rond d'un voyageur : sa photo, sinon ses initiales. Pour moi, c'est la photo de mon profil.
struct RondMembre: View {
    var membre: Membre
    var voyage: Voyage
    var taille: CGFloat = 40

    var body: some View {
        let moi = membre.uid == MoiVoyage.lire(voyage)
        AvatarView(initiales: Profil.initiales(de: membre.nom), donnees: moi ? (Profil.partage.avatar ?? membre.avatar) : membre.avatar,
                   taille: taille, couleur: moi ? .accentColor : AvatarView.couleur(pour: membre.uid))
    }
}

/// Tous les ronds des voyageurs : on en touche un pour le choisir.
struct ChoixMembreView: View {
    var voyage: Voyage
    var titre: String
    var choisi: String
    var onChoix: (Membre) -> Void
    var fermer: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 16)], spacing: 18) {
                    ForEach(voyage.membresTries) { membre in
                        Button { onChoix(membre) } label: {
                            VStack(spacing: 6) {
                                RondMembre(membre: membre, voyage: voyage, taille: 64)
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: membre.uid == choisi ? 3 : 0).padding(-3))
                                Text(membre.nom).font(.footnote).foregroundStyle(.primary).lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle(titre)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer", action: fermer) } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// Ce qui partage une dépense : une famille, ou un voyageur sans famille.
struct UniteDepense: Identifiable {
    let id: String
    let nom: String
    let photo: Data?
    let membres: [Membre]
}

extension Voyage {
    /// Les familles et les voyageurs seuls ; en premier celle de `premier` (par défaut `moi`, celui qui paie dans une dépense).
    @MainActor func unitesDepense(moi: String, premier: String? = nil) -> [UniteDepense] {
        var unites = familles.map { UniteDepense(id: "f:" + $0.nom.lowercased(), nom: $0.nom, photo: photo(famille: $0.nom), membres: $0.membres) }
        unites += membresSansFamille.map {
            UniteDepense(id: "m:" + $0.uid, nom: $0.nom, photo: $0.uid == moi ? (Profil.partage.avatar ?? $0.avatar) : $0.avatar, membres: [$0])
        }
        if let i = unites.firstIndex(where: { $0.membres.contains { $0.uid == (premier ?? moi) } }) { unites.insert(unites.remove(at: i), at: 0) }
        return unites
    }
}

/// Une liasse de billets : trois billets en éventail, retenus par une bande de papier. Sur un rond clair.
struct IconeLiasse: View {
    var body: some View {
        GeometryReader { g in
            let u = min(g.size.width, g.size.height) / 100
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(rouge: 0xF2, vert: 0xFB, bleu: 0xF5), Color(rouge: 0xC9, vert: 0xEE, bleu: 0xD8)],
                                             startPoint: .top, endPoint: .bottom))
                Circle().stroke(Color(rouge: 0x10, vert: 0xB9, bleu: 0x81).opacity(0.35), lineWidth: 1.2 * u)

                billet(u, haut: Color(rouge: 0x3C, vert: 0xA8, bleu: 0xB0), bas: Color(rouge: 0x1F, vert: 0x7A, bleu: 0x8C))
                    .rotationEffect(.degrees(-16)).offset(x: -3 * u, y: -4 * u)
                billet(u, haut: Color(rouge: 0x6B, vert: 0xC9, bleu: 0x6F), bas: Color(rouge: 0x2F, vert: 0x93, bleu: 0x4F))
                    .rotationEffect(.degrees(9)).offset(x: 3 * u, y: -1 * u)
                billet(u, haut: Color(rouge: 0x8A, vert: 0xDB, bleu: 0x7E), bas: Color(rouge: 0x3A, vert: 0xA3, bleu: 0x58))
                    .offset(y: 4 * u)
                bande(u).offset(x: 17 * u, y: 4 * u)
            }
            .frame(width: 100 * u, height: 100 * u)
            .frame(width: g.size.width, height: g.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Un billet : dégradé, liseré, médaillon central avec « € », coins numérotés et fines lignes de sécurité.
    private func billet(_ u: CGFloat, haut: Color, bas: Color) -> some View {
        let l = 62 * u, h = 34 * u
        return ZStack {
            RoundedRectangle(cornerRadius: 3 * u, style: .continuous)
                .fill(LinearGradient(colors: [haut, bas], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 2 * u, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.9 * u).padding(2 * u)
            // Lignes de sécurité de part et d'autre du médaillon
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(.white.opacity(0.22)).frame(width: 14 * u, height: 0.8 * u)
                    .offset(x: -19 * u, y: (CGFloat(i) - 1.5) * 3.4 * u)
                Capsule().fill(.white.opacity(0.22)).frame(width: 14 * u, height: 0.8 * u)
                    .offset(x: 19 * u, y: (CGFloat(i) - 1.5) * 3.4 * u)
            }
            // Médaillon
            Circle().fill(.white.opacity(0.2)).frame(width: 20 * u, height: 20 * u)
            Circle().stroke(.white.opacity(0.75), lineWidth: 1 * u).frame(width: 20 * u, height: 20 * u)
            Circle().stroke(.white.opacity(0.35), lineWidth: 0.6 * u).frame(width: 16.5 * u, height: 16.5 * u)
            Text("€").font(.system(size: 12.5 * u, weight: .heavy, design: .serif)).foregroundStyle(.white)
            // Valeur dans les coins
            Text("20").font(.system(size: 5.2 * u, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                .offset(x: -(l / 2) + 7.5 * u, y: -(h / 2) + 6 * u)
            Text("20").font(.system(size: 5.2 * u, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                .offset(x: (l / 2) - 7.5 * u, y: (h / 2) - 6 * u)
            // Reflet
            RoundedRectangle(cornerRadius: 3 * u, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
        }
        .frame(width: l, height: h)
        .shadow(color: .black.opacity(0.22), radius: 1.6 * u, x: 0, y: 1.2 * u)
    }

    /// La bande de papier qui tient la liasse.
    private func bande(_ u: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.2 * u, style: .continuous)
                .fill(LinearGradient(colors: [Color(rouge: 0xF7, vert: 0xEB, bleu: 0xCF), Color(rouge: 0xE6, vert: 0xD2, bleu: 0xA6)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 1.2 * u, style: .continuous)
                .stroke(Color(rouge: 0xB9, vert: 0x9A, bleu: 0x5C).opacity(0.7), lineWidth: 0.7 * u)
            Text("€").font(.system(size: 6.5 * u, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(rouge: 0xA8, vert: 0x4A, bleu: 0x32))
        }
        .frame(width: 13 * u, height: 40 * u)
        .shadow(color: .black.opacity(0.25), radius: 1.2 * u, x: 0, y: 1 * u)
    }
}
