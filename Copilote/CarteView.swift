import SwiftUI
import MapKit
import SwiftData

/// Onglet Carte : la carte du voyage, avec un choix du jour affiché.
struct CarteView: View {
    @Bindable var voyage: Voyage
    /// nil = tous les jours.
    @State private var jourChoisi: Date?
    @State private var etapeEnEdition: Etape?
    @Environment(\.modelContext) private var contexte

    private var aucuneEtapePlacee: Bool {
        voyage.etapes.allSatisfy { $0.coordonnee == nil } && voyage.infosJours.allSatisfy { $0.lieux.isEmpty }
    }

    private var sansLieu: Int {
        voyage.etapes.filter { $0.coordonnee == nil }.count
    }

    var body: some View {
        // Un point d'intérêt touché devient une étape : du jour affiché, ou à placer quand tous les jours sont affichés.
        CarteDuVoyage(voyage: voyage, jourFocus: jourChoisi, masquerAutresJours: true,
                      onLieu: voyage.lectureSeule ? nil : { lieu in
                          etapeEnEdition = voyage.creerEtape(depuis: lieu, jour: jourChoisi, dans: contexte)
                      }) { etapeEnEdition = $0 }
            .safeAreaInset(edge: .bottom) { barreDesJours }
            .overlay {
                if aucuneEtapePlacee && voyage.pays.isEmpty {
                    ContentUnavailableView("Aucune étape sur la carte", systemImage: "map",
                                           description: Text("Choisis le pays du voyage dans Infos, puis place tes étapes depuis l'itinéraire."))
                        .background(.regularMaterial)
                }
            }
            .sheet(item: $etapeEnEdition) { etape in
                EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
            }
    }

    private var barreDesJours: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pastille("Tous", couleur: .gray, actif: jourChoisi == nil) { jourChoisi = nil }
                    ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                        pastille("J\(index + 1)", couleur: CarteDuVoyage.couleur(du: index),
                                 actif: jourChoisi.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? false) {
                            jourChoisi = jour
                        }
                    }
                }
                .padding(.horizontal)
            }
            if sansLieu > 0 {
                Text("\(sansLieu) étape\(sansLieu > 1 ? "s" : "") sans lieu sur la carte")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func pastille(_ texte: String, couleur: Color, actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(texte)
                .font(.subheadline.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(actif ? .white : couleur)
                .background(actif ? couleur : couleur.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
