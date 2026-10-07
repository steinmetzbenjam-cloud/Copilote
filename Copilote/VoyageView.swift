import SwiftUI

struct VoyageView: View {
    @Bindable var voyage: Voyage
    @State private var onglet: Onglet
    @State private var modesOuverts = false
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @Environment(\.modelContext) private var contexte

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
        .onAppear {
            Profil.partage.reconnaitre(dans: voyage)
            Profil.partage.publier(dans: contexte)
        }
        .toolbar {
            // De gauche à droite : le mode, puis le nom du voyage.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    // Un simple bouton : il ouvre ensuite la liste des trois modes.
                    // Un rond coloré (une couleur par mode) pour qu'il se voie bien.
                    Button { modesOuverts.toggle() } label: {
                        Image(systemName: voyage.mode.symbole)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(voyage.mode.couleur))
                            .shadow(color: voyage.mode.couleur.opacity(0.45), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mode : \(voyage.mode.nom)")
                    .help("Mode : \(voyage.mode.nom)")
                    .popover(isPresented: $modesOuverts) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(ModeVoyage.allCases) { mode in
                                Button {
                                    voyage.mode = mode
                                    modesOuverts = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: mode.symbole).frame(width: 22)
                                        Text(mode.nom)
                                        Spacer(minLength: 16)
                                        if voyage.mode == mode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(minWidth: 200)
                        .presentationCompactAdaptation(.popover)
                    }
                    Text(voyage.titre).font(PoliceVoyage.police(pour: voyage.pays, taille: 21)).lineLimit(1)
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
