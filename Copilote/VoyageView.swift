import SwiftUI

struct VoyageView: View {
    @Bindable var voyage: Voyage
    @State private var onglet: Onglet
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @State private var profilOuvert = false

    init(voyage: Voyage) {
        self.voyage = voyage
        _onglet = State(initialValue: .itineraire)
    }

    enum Onglet: String, CaseIterable, Identifiable {
        case itineraire = "Itinéraire"
        case etapes = "Étapes"
        case carte = "Carte"
        case reservations = "Réserv."
        case depenses = "Dépenses"
        case infos = "Infos"
        var id: String { rawValue }

        var symbole: String {
            switch self {
            case .itineraire: "list.bullet.rectangle"
            case .etapes: "mappin.and.ellipse"
            case .carte: "map"
            case .reservations: "ticket"
            case .depenses: "eurosign.circle"
            case .infos: "info.circle"
            }
        }
    }

    /// Sur iPhone, des icônes : cinq noms ne tiendraient pas dans la barre.
    private var iconesSeules: Bool {
        #if os(iOS)
        tailleHorizontale == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            switch onglet {
            case .itineraire: ItineraireView(voyage: voyage)
            case .etapes: EtapesView(voyage: voyage)
            case .carte: CarteView(voyage: voyage)
            case .reservations: ReservationsView(voyage: voyage)
            case .depenses: DepensesView(voyage: voyage)
            case .infos: VoyageDetailView(voyage: voyage)
            }
        }
        // Le titre est affiché par la barre d'outils, à côté des ronds : on vide celui du système pour ne pas le doubler.
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $profilOuvert) { ProfilEditView() }
        .onAppear { Profil.partage.reconnaitre(dans: voyage) }
        .toolbar {
            // De gauche à droite : le mode, le nom du voyage, puis les voyageurs (toucher les ronds ouvre mon profil).
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    Menu {
                        Picker("Mode", selection: $voyage.mode) {
                            ForEach(ModeVoyage.allCases) { mode in
                                Label(mode.nom, systemImage: mode.symbole).tag(mode)
                            }
                        }
                    } label: {
                        if iconesSeules {
                            Image(systemName: voyage.mode.symbole).accessibilityLabel(voyage.mode.nom)
                        } else {
                            Label(voyage.mode.nom, systemImage: voyage.mode.symbole)
                        }
                    }
                    Text(voyage.titre).font(.headline).lineLimit(1)
                    GroupeAvatars(voyage: voyage) { profilOuvert = true }
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $onglet) {
                    ForEach(Onglet.allCases) { onglet in
                        if iconesSeules {
                            Image(systemName: onglet.symbole).accessibilityLabel(onglet.rawValue).tag(onglet)
                        } else {
                            Text(onglet.rawValue).tag(onglet)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: iconesSeules ? 340 : 540)
            }
        }
    }
}
