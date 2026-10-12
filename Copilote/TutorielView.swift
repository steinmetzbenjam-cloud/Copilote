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
                      ("pencil.and.list.clipboard", "Un voyage passe par trois modes : Préparation, Voyage, puis Souvenir.")]),
        Page(symbole: "square.grid.2x2", couleur: .blue, titre: "Tout est rangé en cinq espaces",
             points: [("calendar", "Programme : les jours, les étapes, le Timing heure par heure et la carte."),
                      ("ticket", "Réservations : billets, hôtels et justificatifs."),
                      ("eurosign.circle", "Argent : le budget prévu et les dépenses partagées."),
                      ("person.3", "Groupe : les voyageurs, les votes et le partage. Infos : dates, pays et monnaies.")]),
        Page(symbole: "lightbulb.max.fill", couleur: .orange, titre: "Quelques astuces",
             points: [("hand.tap", "Touche un lieu sur la carte pour en faire une étape ; l'ampoule propose des idées."),
                      ("hand.draw", "Glisse les étapes pour changer leur ordre ou leur jour."),
                      ("icloud", "Active iCloud dans les Réglages pour partager un voyage avec le groupe.")]),
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
