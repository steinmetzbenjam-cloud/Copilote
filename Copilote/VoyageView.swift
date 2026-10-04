import SwiftUI

struct VoyageView: View {
    @Bindable var voyage: Voyage
    @State private var onglet: Onglet = .itineraire

    enum Onglet: String, CaseIterable, Identifiable {
        case itineraire = "Itinéraire"
        case carte = "Carte"
        case infos = "Infos"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch onglet {
            case .itineraire: ItineraireView(voyage: voyage)
            case .carte: CarteView(voyage: voyage)
            case .infos: VoyageDetailView(voyage: voyage)
            }
        }
        .navigationTitle(voyage.titre)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $onglet) {
                    ForEach(Onglet.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }
        }
    }
}
