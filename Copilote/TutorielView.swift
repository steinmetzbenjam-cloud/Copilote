import SwiftUI

/// Petit tutoriel montré à la première ouverture de l'app (et depuis les Réglages) : les grands points du fonctionnement.
struct TutorielView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    /// Retenu une fois le tutoriel vu ou passé.
    static let cleVu = "tutorielVu"

    private struct Page: Identifiable {
        let id = UUID()
        let symbole: String
        let couleur: Color
        let titre: String
        let points: [(symbole: String, texte: String)]
    }

    private let pages: [Page] = [
        Page(symbole: "car.fill", couleur: .indigo, titre: "Bienvenue dans Copilote",
             points: [("map", "Prépare tes voyages jour par jour, seul ou avec ta famille et tes amis."),
                      ("icloud", "Tout se synchronise avec iCloud : chacun voit les mêmes informations sur ses appareils."),
                      ("pencil.and.list.clipboard", "Un voyage passe par trois modes : Préparation, Voyage puis Souvenir (le rond coloré en haut à gauche).")]),
        Page(symbole: "list.bullet.rectangle", couleur: .blue, titre: "L'itinéraire",
             points: [("calendar", "Les jours sont à gauche, la carte à côté. Ajoute des étapes dans chaque jour et glisse-les pour changer l'ordre."),
                      ("tray.full.fill", "Les idées sans date vont dans « Étapes à placer » : glisse-les ensuite sur un jour."),
                      ("hand.tap", "Touche un lieu sur la carte (restaurant, musée, plage…) pour en faire une étape."),
                      ("bed.double.fill", "Entre deux jours, la bande de nuit accueille l'hôtel ou le transport de la nuit.")]),
        Page(symbole: "mappin.and.ellipse", couleur: .orange, titre: "Le détail d'une étape",
             points: [("square.grid.2x2", "Choisis la catégorie, le jour, l'horaire et la durée."),
                      ("star.bubble", "Note l'étape, donne ton envie et un commentaire : le groupe voit tous les avis."),
                      ("eurosign.circle", "Indique les prix (adulte, étudiant, enfant) en euros ou dans la monnaie du pays."),
                      ("lightbulb.max.fill", "L'ampoule propose des idées de lieux à visiter.")]),
        Page(symbole: "calendar.day.timeline.left", couleur: .teal, titre: "Timing et transports",
             points: [("clock", "Le Timing montre chaque journée heure par heure, à l'heure locale du pays visité."),
                      ("car.fill", "Entre deux étapes, ajoute un transport : l'itinéraire est calculé et tracé sur la carte."),
                      ("airplane", "L'aller et le retour se règlent avec leurs horaires et leurs fuseaux.")]),
        Page(symbole: "chart.pie", couleur: .green, titre: "Budget et dépenses",
             points: [("chart.pie", "Le Budget additionne les prix des étapes et des transports, par famille ou par personne."),
                      ("eurosign.circle", "Les Dépenses suivent ce que chacun a payé et qui doit combien."),
                      ("dollarsign.arrow.circlepath", "Dans Infos, choisis la monnaie locale (et une troisième au besoin) : les montants sont convertis.")]),
        Page(symbole: "person.3.sequence", couleur: .purple, titre: "À plusieurs",
             points: [("square.and.arrow.up", "Partage le voyage depuis Infos pour inviter les autres voyageurs."),
                      ("bubble.left.and.bubble.right.fill", "Discute avec le groupe grâce au rond des messages sur la carte."),
                      ("hand.thumbsup.fill", "Lance un vote pour départager deux étapes ou deux logements : chaque famille a une voix."),
                      ("crown.fill", "Les rôles (organisateur, voyageur, lecteur) règlent qui peut modifier quoi.")]),
    ]

    private var dernierePage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !dernierePage {
                    Button("Passer") { terminer() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)
            .frame(height: 44)

            contenu(pages[page])
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Les points de progression, puis les boutons.
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? pages[page].couleur : Color.secondary.opacity(0.3))
                        .frame(width: i == page ? 20 : 7, height: 7)
                }
            }
            .padding(.bottom, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) sur \(pages.count)")

            HStack(spacing: 12) {
                if page > 0 {
                    Button("Précédent") { aller(page - 1) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(dernierePage ? "Commencer" : "Suivant") {
                    if dernierePage { terminer() } else { aller(page + 1) }
                }
                .buttonStyle(.borderedProminent)
                .tint(pages[page].couleur)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(FondDePage.couleur)
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
        .interactiveDismissDisabled()
    }

    private func contenu(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: p.symbole)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(p.couleur.gradient))
                    .shadow(color: p.couleur.opacity(0.4), radius: 10, y: 4)
                Text(p.titre)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(p.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.symbole)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(p.couleur)
                                .frame(width: 28)
                            Text(point.texte)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FondDePage.carte))
            }
            .padding(.horizontal, 24).padding(.top, 8)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func aller(_ nouvelle: Int) {
        withAnimation(.snappy) { page = min(max(nouvelle, 0), pages.count - 1) }
    }

    private func terminer() {
        UserDefaults.standard.set(true, forKey: Self.cleVu)
        dismiss()
    }
}
