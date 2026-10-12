import SwiftUI

struct VoyageView: View {
    @Bindable var voyage: Voyage
    /// La vue affichée (Itinéraire, Timing, Budget…) ; l'espace qui la contient s'en déduit.
    @State private var onglet: Onglet
    /// La dernière vue ouverte dans chaque espace : on y revient en rouvrant l'espace.
    @State private var dernieres: [Espace: Onglet] = [:]
    @State private var modesOuverts = false
    /// iPhone : les infos du voyage s'ouvrent en touchant son nom.
    @State private var infosOuvertes = false
    @State private var largeur: CGFloat = 1400
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @Environment(\.modelContext) private var contexte

    init(voyage: Voyage) {
        self.voyage = voyage
        _onglet = State(initialValue: .itineraire)
    }

    /// Les vues de l'app, regroupées en espaces.
    enum Onglet: String, CaseIterable, Identifiable {
        case apercu = "Aperçu"
        case itineraire = "Itinéraire"
        case timing = "Timing"
        case carte = "Carte"
        case reservations = "Réservations"
        case budget = "Budget"
        case depenses = "Dépenses"
        case soldes = "Soldes"
        case groupe = "Groupe"
        case infos = "Infos"
        var id: String { rawValue }

        var espace: Espace {
            switch self {
            case .apercu: .apercu
            case .itineraire, .timing, .carte: .programme
            case .reservations: .reservations
            case .budget, .depenses, .soldes: .argent
            case .groupe: .groupe
            case .infos: .infos
            }
        }
    }

    /// Les grands espaces du voyage, chacun nommé dans la barre : le programme jour par jour, les réservations,
    /// l'argent (budget prévu, dépenses, soldes), le groupe (voyageurs, votes, documents) et les infos du voyage.
    enum Espace: String, CaseIterable, Identifiable {
        case apercu = "Aperçu"
        case programme = "Programme"
        case reservations = "Réservations"
        case argent = "Argent"
        case groupe = "Groupe"
        case infos = "Infos"
        var id: String { rawValue }

        var symbole: String {
            switch self {
            case .apercu: "gauge.with.dots.needle.67percent"
            case .programme: "calendar"
            case .reservations: "ticket"
            case .argent: "eurosign.circle"
            case .groupe: "person.3"
            case .infos: "info.circle"
            }
        }

        /// Les vues de l'espace, dans l'ordre de son sélecteur.
        var onglets: [Onglet] { Onglet.allCases.filter { $0.espace == self } }
    }

    /// Les espaces proposés : sur Mac, l'aperçu n'en est pas un (le compte à rebours est dans la barre de titre) ;
    /// ailleurs, il n'apparaît pas en préparation. Sur iPhone, les infos s'ouvrent depuis le nom du voyage.
    private var espaces: [Espace] {
        Espace.allCases.filter { e in
            #if os(macOS)
            if e == .apercu { return false }
            #else
            if e == .apercu && voyage.mode == .preparation { return false }
            #endif
            if e == .infos && iPhone { return false }
            return true
        }
    }

    private var espace: Espace { onglet.espace }

    private func ouvrir(_ e: Espace) {
        onglet = dernieres[e] ?? e.onglets[0]
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
                    // Un rond coloré (une couleur par mode) ; sur grand écran, le nom du mode à côté pour qu'on sache à quoi il sert.
                    Button { modesOuverts.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: voyage.mode.symbole)
                                .font(.system(size: iPhone ? 19 : 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: iPhone ? 40 : 30, height: iPhone ? 40 : 30)
                                .background(Circle().fill(voyage.mode.couleur))
                                .shadow(color: voyage.mode.couleur.opacity(0.45), radius: 3, y: 1)
                            if !iPhone {
                                Text(voyage.mode.nom)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(voyage.mode.couleur)
                                    .fixedSize()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mode : \(voyage.mode.nom)")
                    .help("Mode du voyage : \(voyage.mode.nom)")
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

    /// iPad et Mac : les espaces dans la barre, chacun avec son icône et son nom.
    private var barreEspaces: some View {
        HStack(spacing: 2) {
            ForEach(espaces) { e in
                let actif = e == espace
                Button { ouvrir(e) } label: {
                    VStack(spacing: 1) {
                        Image(systemName: e.symbole).font(.system(size: 15, weight: .semibold))
                        Text(e.rawValue).font(.system(size: 10, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(actif ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(minWidth: 62)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(actif ? 0.16 : 0)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.rawValue)
                .accessibilityAddTraits(actif ? .isSelected : [])
            }
        }
        .fixedSize()
    }

    /// iPhone : les espaces en bas de l'écran, comme une barre d'onglets.
    private var barreOngletsIPhone: some View {
        HStack(spacing: 0) {
            ForEach(espaces) { e in
                let actif = e == espace
                Button { ouvrir(e) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: e.symbole).font(.system(size: 20, weight: .semibold)).frame(height: 24)
                        Text(e.rawValue).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(actif ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7).padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.rawValue)
                .accessibilityAddTraits(actif ? .isSelected : [])
            }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Dans un espace à plusieurs vues (Programme, Argent) : un sélecteur en haut du contenu.
    @ViewBuilder private func selecteurVues(_ e: Espace) -> some View {
        if e.onglets.count > 1 {
            Picker("Vue", selection: Binding(get: { onglet }, set: { onglet = $0 })) {
                ForEach(e.onglets) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            // Un fond flouté : lisible même posé sur la carte.
            .padding(4)
            .background(.regularMaterial, in: Capsule())
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func vue(_ o: Onglet) -> some View {
        switch o {
        case .apercu: ApercuView(voyage: voyage)
        case .itineraire: ItineraireView(voyage: voyage)
        case .timing: TimingView(voyage: voyage)
        case .carte: CarteView(voyage: voyage)
        case .reservations: ReservationsView(voyage: voyage)
        case .budget: BudgetView(voyage: voyage)
        case .depenses: DepensesView(voyage: voyage, soldes: false)
        case .soldes: DepensesView(voyage: voyage, soldes: true)
        case .groupe: GroupeView(voyage: voyage)
        case .infos: VoyageDetailView(voyage: voyage)
        }
    }

    /// Le contenu d'un espace : sa vue en cours, avec le sélecteur de ses vues au-dessus.
    private func contenu(_ e: Espace) -> some View {
        let o = e == espace ? onglet : (dernieres[e] ?? e.onglets[0])
        return vue(o)
            .id(o)
            .safeAreaInset(edge: .top, spacing: 0) { selecteurVues(e) }
    }

    /// Le nom du voyage. Sur iPhone, il ouvre les infos du voyage (dates, pays, monnaies…).
    private var titre: some View {
        let texte = Text(voyage.titre)
            .font(PoliceVoyage.police(pour: voyage.pays, taille: iPhone ? 17 : 21))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        return Group {
            if iPhone {
                Button { infosOuvertes = true } label: {
                    HStack(spacing: 4) {
                        texte.foregroundStyle(.primary)
                        Image(systemName: "info.circle").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre les infos du voyage")
            } else {
                texte.frame(maxWidth: largeur < 1000 ? 150 : 260, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var principal: some View {
            if iPhone {
                // iPhone : une barre d'onglets en bas, chaque espace nommé. Dessinée ici plutôt que celle du système :
                // dans celle-ci, les boutons propres à chaque vue (étapes à placer, messages) ne remontaient plus dans la barre du haut.
                contenu(espace)
                    .safeAreaInset(edge: .bottom, spacing: 0) { barreOngletsIPhone }
            } else {
                contenu(espace)
            }
    }

    var body: some View {
        principal
        .overlay(alignment: .bottom) {
            if !Reseau.shared.enLigne {
                Label("Hors ligne : tes modifications sont gardées sur l'appareil", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange))
                    .shadow(radius: 3, y: 1).padding(.bottom, iPhone ? 60 : 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: Reseau.shared.enLigne)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { largeur = $0 }
        .onChange(of: onglet) { _, o in dernieres[o.espace] = o }
        // Le titre est affiché par la barre d'outils, à côté du mode : on vide celui du système pour ne pas le doubler.
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $infosOuvertes) {
            NavigationStack {
                VoyageDetailView(voyage: voyage)
                    .navigationTitle("Infos du voyage")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { infosOuvertes = false } } }
            }
        }
        // Le fuseau de chaque pays visité : il règle l'heure locale de tous les jours.
        .task(id: voyage.pays) {
            for code in voyage.pays { await FuseauxHoraires.shared.chargerPays(code) }
        }
        // L'aperçu disparaît en préparation (et les infos passent sous le nom sur iPhone) : on revient alors au programme.
        .onChange(of: voyage.mode) { _, _ in if !espaces.contains(espace) { onglet = .itineraire } }
        .onChange(of: iPhone) { _, _ in if !espaces.contains(espace) { onglet = .itineraire } }
        .onAppear {
            if !espaces.contains(espace) { onglet = .itineraire }
            Profil.partage.reconnaitre(dans: voyage)
            Profil.partage.publier(dans: contexte)
        }
        .toolbar { barre }
    }

    @ToolbarContentBuilder private var barre: some ToolbarContent {
            #if os(iOS)
            if iPhone {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { boutonMode }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { boutonMode }
                }
                ToolbarItem(placement: .principal) { titre }
            } else {
                barreGrandEcran
            }
            #else
            barreGrandEcran
            #endif
    }

    @ToolbarContentBuilder private var barreGrandEcran: some ToolbarContent {
                // De gauche à droite : le mode, le nom du voyage (et son compte à rebours sur Mac), puis les espaces.
                ToolbarItem(placement: placementGauche) {
                    HStack(spacing: 10) {
                        boutonMode
                        titre
                        #if os(macOS)
                        Text(voyage.compteARebours)
                            .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(voyage.mode.couleur))
                            .fixedSize()
                            .help("Compte à rebours du voyage")
                        #endif
                    }
                    #if os(iOS)
                    .fixedSize()
                    #endif
                }
                ToolbarItem(placement: placementVues) { barreEspaces }
    }

    /// Sur iPad, le mode, le nom du voyage et les espaces se suivent tous à gauche de la barre.
    private var placementGauche: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    private var placementVues: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .principal
        #endif
    }
}
