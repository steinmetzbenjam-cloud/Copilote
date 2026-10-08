import SwiftUI
import SwiftData
import MapKit

/// Première fenêtre : « Quel voyage ouvrir ? ». Les voyages sont posés sur la carte du monde, chacun dans sa couleur.
/// On touche une épingle (ou un cadre en bas) pour choisir un voyage, puis « Ouvrir ».
struct SelecteurVoyageView: View {
    let voyages: [Voyage]
    let onChoix: (Voyage) -> Void
    let onNouveau: () -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Emplacement {
        var centre: CLLocationCoordinate2D
        /// Taille de la zone à montrer quand on s'approche : celle du pays.
        var etendue: Double
    }

    @State private var position: MapCameraPosition = .region(Self.monde)
    @State private var emplacements: [PersistentIdentifier: Emplacement] = [:]
    @State private var choisi: PersistentIdentifier?

    private static let monde = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25, longitude: 10),
                                                  span: MKCoordinateSpan(latitudeDelta: 130, longitudeDelta: 330))

    private static let palette: [Color] = [
        Color(rouge: 0xFF, vert: 0x6B, bleu: 0x4A), Color(rouge: 0x2F, vert: 0x7B, bleu: 0xF2), Color(rouge: 0x1F, vert: 0xB5, bleu: 0x6B),
        Color(rouge: 0xE8, vert: 0x3E, bleu: 0x8C), Color(rouge: 0x8B, vert: 0x5C, bleu: 0xF6), Color(rouge: 0xF5, vert: 0xA6, bleu: 0x23),
        Color(rouge: 0x0E, vert: 0xA5, bleu: 0xC9), Color(rouge: 0xD9, vert: 0x48, bleu: 0x48),
    ]

    private func couleur(_ voyage: Voyage) -> Color {
        let i = voyages.firstIndex { $0.persistentModelID == voyage.persistentModelID } ?? 0
        return Self.palette[i % Self.palette.count]
    }

    private func drapeaux(_ v: Voyage) -> String { v.pays.compactMap { Pays.avec(code: $0)?.drapeau }.joined(separator: " ") }

    // MARK: Corps

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(voyages.filter { emplacements[$0.persistentModelID] != nil }) { voyage in
                    if let lieu = emplacements[voyage.persistentModelID] {
                        Annotation("", coordinate: lieu.centre, anchor: .bottom) { epingle(voyage) }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .safeAreaInset(edge: .bottom, spacing: 0) { cadres }
            .navigationTitle("Quel voyage ouvrir ?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouveau voyage", systemImage: "plus") {
                        dismiss()
                        onNouveau()
                    }
                }
            }
            .task(id: voyages.map { "\($0.uid)|\($0.pays.joined())" }) { await placer() }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 600)
        #endif
    }

    // MARK: Épingles

    private func epingle(_ voyage: Voyage) -> some View {
        let actif = choisi == voyage.persistentModelID
        let teinte = couleur(voyage)
        return VStack(spacing: 3) {
            Text(voyage.titre.isEmpty ? "Voyage" : voyage.titre)
                .font(.caption.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(teinte))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            ZStack {
                Circle().fill(LinearGradient(colors: [teinte.opacity(0.85), teinte], startPoint: .top, endPoint: .bottom))
                Circle().stroke(.white, lineWidth: 3)
                Text(Pays.avec(code: voyage.pays.first ?? "")?.drapeau ?? "📍").font(.system(size: actif ? 26 : 20))
            }
            .frame(width: actif ? 52 : 40, height: actif ? 52 : 40)
            .shadow(color: teinte.opacity(0.6), radius: actif ? 8 : 4, y: 2)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(teinte).offset(y: -5)
        }
        .scaleEffect(actif ? 1.12 : 1)
        .animation(.snappy, value: actif)
        .contentShape(Rectangle())
        .onTapGesture { choisir(voyage) }
    }

    // MARK: Cadres en bas

    private var cadres: some View {
        ScrollViewReader { lecteur in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(voyages) { voyage in carte(voyage).id(voyage.persistentModelID) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .background(.regularMaterial)
            .onChange(of: choisi) { _, nouveau in
                if let nouveau { withAnimation { lecteur.scrollTo(nouveau, anchor: .center) } }
            }
        }
    }

    private func carte(_ voyage: Voyage) -> some View {
        let actif = choisi == voyage.persistentModelID
        let teinte = couleur(voyage)
        let place = emplacements[voyage.persistentModelID] != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drapeaux(voyage).isEmpty ? "📍" : drapeaux(voyage)).font(.title3)
                Spacer()
                Text(voyage.compteARebours).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.25), in: Capsule())
                if !place { Image(systemName: "mappin.slash").font(.footnote) }
            }
            Text(voyage.titre.isEmpty ? "Voyage" : voyage.titre).font(.headline).lineLimit(2)
            Text("\(voyage.debut.formatted(.dateTime.day().month(.abbreviated).year())) – \(voyage.fin.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.caption).opacity(0.9)
            Spacer(minLength: 0)
            if actif {
                Button { ouvrir(voyage) } label: {
                    Label("Ouvrir", systemImage: "arrow.right.circle.fill").font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(Capsule().fill(.white)).foregroundStyle(teinte)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 200, height: 142, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [teinte, teinte.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(actif ? 0.9 : 0), lineWidth: 3))
        .shadow(color: teinte.opacity(actif ? 0.55 : 0.25), radius: actif ? 9 : 4, y: 2)
        .scaleEffect(actif ? 1.03 : 1)
        .animation(.snappy, value: actif)
        .contentShape(Rectangle())
        .onTapGesture { if actif { ouvrir(voyage) } else { choisir(voyage) } }
    }

    // MARK: Actions

    private func ouvrir(_ voyage: Voyage) {
        onChoix(voyage)
        dismiss()
    }

    private func choisir(_ voyage: Voyage) {
        choisi = voyage.persistentModelID
        guard let lieu = emplacements[voyage.persistentModelID] else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            position = .region(MKCoordinateRegion(center: lieu.centre, span: MKCoordinateSpan(latitudeDelta: lieu.etendue, longitudeDelta: lieu.etendue * 1.4)))
        }
    }

    /// Cherche où poser chaque voyage : le centre de son premier pays, sinon la moyenne de ses étapes localisées.
    private func placer() async {
        var trouves: [PersistentIdentifier: Emplacement] = [:]
        for voyage in voyages {
            if let code = voyage.pays.first, let region = await Pays.region(de: code) {
                let etendue = min(max(max(region.span.latitudeDelta, region.span.longitudeDelta / 1.4) * 1.5, 6), 45)
                trouves[voyage.persistentModelID] = Emplacement(centre: region.center, etendue: etendue)
            } else {
                let points = voyage.etapes.compactMap(\.coordonnee)
                if !points.isEmpty {
                    let centre = CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                                        longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
                    trouves[voyage.persistentModelID] = Emplacement(centre: centre, etendue: 8)
                }
            }
        }
        emplacements = trouves
        cadrer(Array(trouves.values))
    }

    /// Au départ, la carte montre tous les voyages : le monde entier s'il y en a de très éloignés.
    private func cadrer(_ lieux: [Emplacement]) {
        guard choisi == nil else { return }
        guard !lieux.isEmpty else { position = .region(Self.monde); return }
        if lieux.count == 1, let seul = lieux.first {
            position = .region(MKCoordinateRegion(center: seul.centre, span: MKCoordinateSpan(latitudeDelta: seul.etendue * 1.6, longitudeDelta: seul.etendue * 2.2)))
            return
        }
        let lat = lieux.map(\.centre.latitude), lon = lieux.map(\.centre.longitude)
        let centre = CLLocationCoordinate2D(latitude: (lat.min()! + lat.max()!) / 2, longitude: (lon.min()! + lon.max()!) / 2)
        let dLat = min(max((lat.max()! - lat.min()!) * 1.6, 20), 130)
        let dLon = min(max((lon.max()! - lon.min()!) * 1.6, 30), 330)
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .region(MKCoordinateRegion(center: centre, span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon)))
        }
    }
}
