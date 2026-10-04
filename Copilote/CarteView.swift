import SwiftUI
import MapKit

struct CarteView: View {
    @Bindable var voyage: Voyage
    /// nil = tous les jours.
    @State private var jourChoisi: Date?
    @State private var position: MapCameraPosition = .automatic
    @State private var etapeEnEdition: Etape?
    @Environment(\.modelContext) private var contexte

    /// Une couleur par jour, qui revient au bout de huit jours.
    private static let couleurs: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .pink, .brown]

    private func couleur(du index: Int) -> Color { Self.couleurs[index % Self.couleurs.count] }

    private var joursAffiches: [(index: Int, jour: Date)] {
        voyage.jours.enumerated()
            .map { (index: $0.offset, jour: $0.element) }
            .filter { jourChoisi == nil || Calendar.current.isDate($0.jour, inSameDayAs: jourChoisi!) }
    }

    private var sansLieu: Int {
        voyage.etapes.filter { $0.coordonnee == nil }.count
    }

    var body: some View {
        Map(position: $position) {
            ForEach(joursAffiches, id: \.jour) { index, jour in
                let etapes = voyage.etapes(du: jour).filter { $0.coordonnee != nil }
                if etapes.count > 1 {
                    MapPolyline(coordinates: etapes.compactMap(\.coordonnee))
                        .stroke(couleur(du: index).opacity(0.6), lineWidth: 3)
                }
                ForEach(Array(etapes.enumerated()), id: \.element.id) { rang, etape in
                    Annotation(etape.titre, coordinate: etape.coordonnee!) {
                        Button { etapeEnEdition = etape } label: {
                            Text("\(rang + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(couleur(du: index), in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) { barreDesJours }
        .onChange(of: jourChoisi) {
            withAnimation { position = .automatic }
        }
        .overlay {
            if voyage.etapes.allSatisfy({ $0.coordonnee == nil }) {
                ContentUnavailableView("Aucune étape sur la carte", systemImage: "map",
                                       description: Text("Dans l'itinéraire, ouvre une étape et touche « Placer sur la carte »."))
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
                        pastille("J\(index + 1)", couleur: couleur(du: index),
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
