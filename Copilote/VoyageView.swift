import SwiftUI

struct VoyageView: View {
    @Bindable var voyage: Voyage
    @State private var onglet: Onglet
    @State private var modesOuverts = false
    @State private var vuesDepliees = false
    /// Largeur disponible : sur un petit écran (iPad mini), la barre passe en icônes pour que tout y tienne.
    @State private var largeur: CGFloat = 1400
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
        tailleHorizontale == .compact || largeur < 1180
        #else
        false
        #endif
    }

    private var iPhone: Bool {
        #if os(iOS)
        tailleHorizontale == .compact
        #else
        false
        #endif
    }

    @ViewBuilder private var boutonMode: some View {
                    // Un simple bouton : il ouvre ensuite la liste des trois modes.
                    // Un rond coloré (une couleur par mode) pour qu'il se voie bien.
                    Button { modesOuverts.toggle() } label: {
                        Image(systemName: voyage.mode.symbole)
                            .font(.system(size: iPhone ? 19 : 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: iPhone ? 40 : 30, height: iPhone ? 40 : 30)
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
    }

    private func rond(_ o: Onglet, actif: Bool) -> some View {
        Image(systemName: o.symbole)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(actif ? Color.white : Color.accentColor)
            .frame(width: 40, height: 40)
            .background(Circle().fill(actif ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial)))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    /// iPhone : dans la barre, un seul rond fixe (la vue en cours). Un appui déplie les autres vues juste sous la barre,
    /// car faire changer la taille de la barre elle-même la fait disparaître.
    private var selecteurIPhone: some View {
        Button { vuesDepliees.toggle() } label: { rond(onglet, actif: true) }
            .buttonStyle(.plain)
            .accessibilityLabel(onglet.rawValue)
    }

    private var rangeeVues: some View {
        HStack(spacing: 10) {
            ForEach(Onglet.allCases) { o in
                Button {
                    onglet = o
                    vuesDepliees = false
                } label: { rond(o, actif: o == onglet) }
                .buttonStyle(.plain)
                .accessibilityLabel(o.rawValue)
            }
        }
        .padding(.leading, 12).padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// iPhone : le mode puis la vue en cours, toujours à gauche (après le retour), sans cadre autour.
    @ToolbarContentBuilder private var barreIPhone: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { boutonMode }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarLeading) { selecteurIPhone }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { boutonMode }
            ToolbarItem(placement: .topBarLeading) { selecteurIPhone }
        }
        #else
        ToolbarItem(placement: .navigation) { boutonMode }
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
        .overlay(alignment: .topLeading) {
            if iPhone && vuesDepliees { rangeeVues }
        }
        .animation(.snappy, value: vuesDepliees)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
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
            if iPhone {
                barreIPhone
            } else {
            // De gauche à droite : le mode, puis le nom du voyage.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    boutonMode
                    // Le titre reste à gauche de la barre ; il rétrécit plutôt que de pousser les autres boutons.
                    Text(voyage.titre)
                        .font(PoliceVoyage.police(pour: voyage.pays, taille: iconesSeules ? 17 : 21))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: iconesSeules ? 140 : 260, alignment: .leading)
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
                .frame(maxWidth: iconesSeules ? 300 : 540)
            }
            }
        }
    }
}
