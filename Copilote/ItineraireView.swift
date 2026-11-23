import SwiftUI
import SwiftData
import MapKit

/// Le planning : une carte par jour, avec sa date, ses lieux de référence et ses étapes.
struct ItineraireView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    /// Étape dont le détail est ouvert dans un cadre posé sur la colonne des jours ; la carte zoome dessus.
    @State private var etapeEnEdition: Etape?
    /// Sous-étape ouverte dans la fiche de son étape : la carte se cadre sur elle.
    @State private var sousEtapeEnEdition: Etape?
    /// Sous-étape touchée sur la carte : la fiche de son étape s'ouvre directement sur elle.
    @State private var sousEtapeDemandee: Etape?
    @State private var nuitEnAjout: NuitAjout?
    @State private var transportDeNuitEnEdition: NuitTransport?
    /// Transport d'aller ou de retour ouvert depuis son pavé, en tête du premier jour ou en bas du dernier.
    @State private var extremiteEnEdition: TimingView.ExtremiteTransport?
    /// Prévisions météo : le fond de chaque jour en prend l'aspect, quand elles le couvrent (16 jours).
    @State private var meteo = Meteo.shared
    /// Lieu de la météo pour les jours sans étape placée : le milieu du voyage, ou le premier pays.
    @State private var lieuMeteoVoyage: CLLocationCoordinate2D?
    @Environment(\.scenePhase) private var phase
    @State private var jourEnEdition: JourVoyage?
    @State private var parcoursJoue: ParcoursJourChoisi?
    /// Étape au-dessus de laquelle on s'apprête à déposer (trait d'insertion), ou jour survolé.
    @State private var etapeVisee: String?
    @State private var jourVise: Date?
    @State private var nuitVisee: Date?
    /// Jour sur lequel la carte est cadrée ; nil = tout le voyage.
    @State private var jourSelectionne: Date?
    /// Étape dont on affiche l'explication de l'avertissement d'horaire.
    @State private var avertissementOuvert: String?
    /// Fenêtre des votes, ouverte depuis le rond « Votes » de la carte.
    @State private var votesOuverts = false
    @State private var profilOuvert = false
    @State private var membreAffiche: Membre?
    /// Écran large (iPad, Mac) : plus de place pour les notes d'un jour.
    @State private var ecranLarge = false
    /// Hauteur du contenu de « Étapes à placer » (iPad), pour que son défilement ne couvre pas la carte.
    @State private var hauteurEtapesAPlacer: CGFloat = .infinity
    /// Fenêtre « Étapes à placer » ouverte : fermée au lancement de l'app (on l'ouvre avec son rond),
    /// puis gardée telle quelle d'un onglet à l'autre.
    @State private var etapesAPlacerOuvertes = ItineraireView.etapesAPlacerOuvertesSession
    private static var etapesAPlacerOuvertesSession = false
    /// Déplacement qui effacerait des transports : en attente de confirmation.
    @State private var deplacementEnAttente: DeplacementEnAttente?
    /// Jour dont les notes sont ouvertes dans un cadre à droite de sa carte (sous son en-tête sur iPhone).
    @State private var notesOuvertes: Date?
    /// Haut de la carte du jour aux notes ouvertes, pour y aligner le cadre.
    @State private var hautNotes: CGFloat = 0
    /// Clavier affiché (iPhone) : le détail de l'étape ouverte monte alors par-dessus la carte.
    @State private var clavierOuvert = false
    /// Partage entre la carte et la liste, réglé avec la poignée et retenu d'une ouverture à l'autre :
    /// iPhone, part de la hauteur donnée à la carte ; iPad et Mac, largeur du panneau des jours.
    @AppStorage("itineraireHauteurCarte") private var partCarte = ItineraireView.partCarteParDefaut
    @AppStorage("itineraireLargeurPanneau") private var largeurPanneauRetenue = Double(ItineraireView.largeurPanneauParDefaut)
    /// Poignée en cours de déplacement : taille de départ et décalage du doigt. La carte ne se recadre qu'au lâcher.
    @State private var poignee: (depart: CGFloat, decalage: CGFloat)?

    private static var estUnIPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private struct DeplacementEnAttente: Identifiable {
        let id = UUID()
        let etape: Etape
        let jour: Date?
        let cible: Etape?
        let perdus: [Etape]
        var nuit = false
    }

    private let cal = Calendar.current

    private var horsDates: [Etape] {
        voyage.etapes.filter { e in
            guard let jour = e.jour else { return false }
            return !voyage.jours.contains { cal.isDate($0, inSameDayAs: jour) }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let panneauLateral = geo.size.width >= 700
            if panneauLateral {
                // iPad, Mac : la carte en fond, les jours empilés dans un panneau à gauche.
                let largeurPanneau = largeurDuPanneau(dans: geo.size.width)
                ZStack(alignment: .leading) {
                    fondDeCarte(margeGauche: largeurPanneau)
                    DefilementMemorise(cle: cleDefilement(large: true)) { listeDesJours(avecEtapesAPlacer: false).padding(12) }
                        .id(cleDefilement(large: true))
                        .frame(width: largeurPanneau)
                        .scrollIndicators(.hidden)
                        .overlay { cadreEtape.padding(12) }
                        // La poignée, sur le bord droit du panneau : on la tire pour élargir la liste ou la carte.
                        .overlay(alignment: .trailing) { poigneeVerticale(largeurEcran: geo.size.width).offset(x: 9) }
                    // Les notes du jour : un post-it à droite de sa carte.
                    if let jour = notesOuvertes, let numero = voyage.jours.firstIndex(where: { cal.isDate($0, inSameDayAs: jour) }) {
                        cadreNotes(jour, numero: numero + 1)
                            .frame(width: 380)
                            .padding(.leading, largeurPanneau + 4)
                            .padding(.top, min(max(hautNotes, 12), max(geo.size.height - 470, 12)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    // À droite : les ronds (sur Mac) puis les étapes à placer. Seuls les cadres captent le toucher.
                    VStack(alignment: .trailing, spacing: 0) {
                        // Sur Mac, les ronds en haut à droite de la carte (sur iPhone et iPad, ils sont dans la barre du haut).
                        #if os(macOS)
                        boutonsRonds.padding(.top, 6).padding(.trailing, 10)
                        #endif
                        if etapesAPlacerOuvertes {
                            // Le défilement se limite à la hauteur du contenu : en dessous, le doigt agit sur la carte.
                            ScrollView {
                                etapesAPlacer.padding(12)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteurEtapesAPlacer = $0 }
                            }
                            .frame(width: 344)
                            .frame(maxHeight: hauteurEtapesAPlacer)
                            .scrollIndicators(.hidden)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            } else {
                // iPhone : la carte en haut, les jours dessous.
                // Le panneau des jours a les coins du haut arrondis, comme les cartes des étapes : la limite avec la carte n'est pas
                // une ligne droite. Il recouvre le bas de la carte de la hauteur de l'arrondi.
                let arrondi = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 16,
                                                     style: .continuous)
                let hauteurCarte = hauteurDeLaCarte(dans: geo.size.height)
                // Clavier ouvert sur une étape (iPhone) : son cadre monte par-dessus le plan et prend tout l'écran au-dessus du clavier.
                // Seul le cadre s'agrandit, sans changer de place dans la hiérarchie : le champ en cours garde le clavier.
                let etapePleinEcran = clavierOuvert && etapeEnEdition != nil && Self.estUnIPhone
                VStack(spacing: -16) {
                    fondDeCarte(margeGauche: 0).frame(height: hauteurCarte + 16)
                    DefilementMemorise(cle: cleDefilement(large: false)) { listeDesJours(avecEtapesAPlacer: true).padding(12) }
                        .id(cleDefilement(large: false))
                        // La poignée, en haut du panneau des jours : on la tire pour agrandir la carte ou la liste.
                        .safeAreaInset(edge: .top, spacing: 0) { poigneeHorizontale(hauteurEcran: geo.size.height) }
                        .background(FondDePage.couleur)
                        .clipShape(arrondi)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: -2)
                        .overlay { cadreEtape.padding(8).padding(.top, etapePleinEcran ? -hauteurCarte : 0) }
                        .zIndex(1)
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.snappy) { clavierOuvert = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.snappy) { clavierOuvert = false }
                }
                #endif
                // Les notes du jour s'ouvrent en haut, par-dessus la carte : le clavier, qui monte du bas, ne les cache pas.
                // (Les déplacer seulement à l'apparition du clavier recréerait la zone de texte et refermerait le clavier.)
                .overlay(alignment: .top) {
                    if let jour = notesOuvertes, let numero = voyage.jours.firstIndex(where: { cal.isDate($0, inSameDayAs: jour) }) {
                        cadreNotes(jour, numero: numero + 1)
                            .padding(.horizontal, 12).padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .ignoresSafeArea(.keyboard)
                    }
                }
            }
        }
        .coordinateSpace(.named(Self.espace))
        .onPreferenceChange(HautCarteNotes.self) { hautNotes = $0 }
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { ecranLarge = $0 }
        // Déposer une étape en dehors d'une carte de jour : elle n'a plus de jour.
        .dropDestination(for: String.self) { elements, _ in
            guard !voyage.lectureSeule else { return false }
            guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count),
                  let etape = voyage.etapes.first(where: { $0.uid == String(uid) }) else { return false }
            return demander(etape, vers: nil, avant: nil)
        }
        .confirmationDialog("Effacer le transport ?", isPresented: Binding(get: { deplacementEnAttente != nil }, set: { if !$0 { deplacementEnAttente = nil } }), titleVisibility: .visible, presenting: deplacementEnAttente) { d in
            Button("Déplacer et effacer le transport", role: .destructive) { appliquer(d) }
            Button("Annuler", role: .cancel) {}
        } message: { d in
            Text(d.perdus.count == 1 ? "Ce déplacement efface le transport prévu après « \(d.perdus[0].titre) »." : "Ce déplacement efface \(d.perdus.count) transports prévus entre des étapes.")
        }
        .toolbar {
            // Sur Mac : les voyageurs (toucher les ronds ouvre mon profil).
            #if os(iOS)
            // Sur iPhone et iPad : les ronds dans la barre du haut, au niveau du changement de vue.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { boutonsRonds }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { boutonsRonds }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                GroupeAvatars(voyage: voyage, onMoi: { profilOuvert = true }, onAutre: { membreAffiche = $0 })
            }
            #endif
        }
        // Les fonds suivent les prévisions : une mise à jour qui change le temps d'un jour change son fond.
        .task(id: voyage.cleMeteo) { await chargerMeteo() }
        .onChange(of: phase) { _, p in if p == .active { Task { await chargerMeteo() } } }
        .sheet(isPresented: $profilOuvert) { ProfilEditView() }
        .sheet(isPresented: $votesOuverts) {
            NavigationStack {
                VotesView(voyage: voyage)
                    .navigationTitle("Votes")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { votesOuverts = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 560)
            #endif
        }
        .sheet(item: $membreAffiche) { ProfilMembreView(membre: $0) }
        .sheet(item: $transportDeNuitEnEdition) { TransportEditView(depart: $0.depart, arrivee: $0.arrivee) }
        .sheet(item: $nuitEnAjout, onDismiss: { nettoyer(sauf: etapeEnEdition) }) { NuitAjoutView(voyage: voyage, nuit: $0) }
        .sheet(item: $extremiteEnEdition) { FicheExtremite(voyage: voyage, extremite: $0) }
        #if os(iOS)
        .fullScreenCover(item: $parcoursJoue) { ParcoursJourView(voyage: voyage, jour: $0.jour, numero: $0.numero) }
        #else
        .sheet(item: $parcoursJoue) { ParcoursJourView(voyage: voyage, jour: $0.jour, numero: $0.numero) }
        #endif
        .sheet(item: $jourEnEdition, onDismiss: nettoyerJours) { infos in
            JourEditView(jour: infos, voyage: voyage, numero: (voyage.jours.firstIndex { cal.isDate($0, inSameDayAs: infos.date) } ?? 0) + 1)
        }
    }

    // MARK: Poignée entre la carte et la liste

    private static let largeurPanneauParDefaut: CGFloat = 404
    private static let partCarteParDefaut = 0.36

    /// iPad, Mac : la largeur retenue, ou celle qu'on est en train de tirer, sans écraser la carte ni la liste.
    private func largeurDuPanneau(dans largeurEcran: CGFloat) -> CGFloat {
        let voulue = poignee.map { $0.depart + $0.decalage } ?? CGFloat(largeurPanneauRetenue)
        return Self.borner(voulue, 320, max(320, largeurEcran - 280))
    }

    /// iPhone : la hauteur de la carte, retenue en part de l'écran ou en cours de réglage, en gardant de la place pour la liste.
    private func hauteurDeLaCarte(dans hauteurEcran: CGFloat) -> CGFloat {
        let voulue = poignee.map { $0.depart + $0.decalage } ?? hauteurEcran * CGFloat(partCarte)
        return Self.borner(voulue, 120, max(120, hauteurEcran - 180))
    }

    private static func borner(_ valeur: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        min(max(valeur, minimum), maximum)
    }

    /// Le geste commun aux deux poignées. `taille` donne la taille actuelle au début du geste ; `fin` retient la taille lâchée.
    private func gestePoignee(axe: Axis, taille: @escaping () -> CGFloat, fin: @escaping (CGFloat) -> Void) -> some Gesture {
        // Repère global : la poignée bouge avec le doigt, un repère local fausserait le décalage.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { geste in
                let decalage = axe == .vertical ? geste.translation.height : geste.translation.width
                if poignee == nil { poignee = (taille(), 0) }
                poignee?.decalage = decalage
            }
            .onEnded { _ in
                fin(taille())
                poignee = nil
            }
    }

    /// iPhone : la barre en haut du panneau des jours. Tirer pour changer la hauteur de la carte ; toucher deux fois pour revenir au réglage d'origine.
    private func poigneeHorizontale(hauteurEcran: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(poignee == nil ? 0.45 : 0.8))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .padding(.top, 2)
            .background(FondDePage.couleur)
            .contentShape(Rectangle())
            .gesture(gestePoignee(axe: .vertical, taille: { hauteurDeLaCarte(dans: hauteurEcran) },
                                  fin: { partCarte = Double($0 / max(hauteurEcran, 1)) }))
            .onTapGesture(count: 2) { withAnimation(.snappy) { partCarte = Self.partCarteParDefaut } }
            .accessibilityElement()
            .accessibilityLabel("Taille de la carte")
            .accessibilityValue("\(Int((hauteurDeLaCarte(dans: hauteurEcran) / max(hauteurEcran, 1) * 100).rounded())) %")
            .accessibilityAdjustableAction { sens in
                let pas: CGFloat = sens == .increment ? 0.08 : -0.08
                let part = hauteurDeLaCarte(dans: hauteurEcran) / max(hauteurEcran, 1) + pas
                withAnimation(.snappy) { partCarte = Double(Self.borner(part, 0.15, 0.75)) }
            }
    }

    /// iPad, Mac : la poignée sur le bord droit du panneau des jours. Tirer pour changer sa largeur ; toucher deux fois pour revenir au réglage d'origine.
    private func poigneeVerticale(largeurEcran: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(poignee == nil ? 0.55 : 0.9))
            .frame(width: 5, height: 44)
            .padding(.vertical, 6).padding(.horizontal, 2)
            .background(Capsule().fill(.regularMaterial))
            .shadow(color: .black.opacity(0.15), radius: 3)
            // Zone de prise plus large que la capsule, sur toute la hauteur.
            .frame(width: 18)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { dessus in
                if dessus { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
            .gesture(gestePoignee(axe: .horizontal, taille: { largeurDuPanneau(dans: largeurEcran) },
                                  fin: { largeurPanneauRetenue = Double($0) }))
            .onTapGesture(count: 2) { withAnimation(.snappy) { largeurPanneauRetenue = Double(Self.largeurPanneauParDefaut) } }
            .help("Tirer pour changer la largeur de la liste ; double-clic pour revenir à la largeur d'origine")
            .accessibilityElement()
            .accessibilityLabel("Largeur de la liste")
            .accessibilityAdjustableAction { sens in
                let pas: CGFloat = sens == .increment ? 40 : -40
                withAnimation(.snappy) { largeurPanneauRetenue = Double(largeurDuPanneau(dans: largeurEcran) + pas) }
            }
    }

    // MARK: Messages

    /// Taille des ronds : sur iPhone et iPad ils sont dans la barre du haut, à côté du changement de vue, donc un peu plus petits.
    private var tailleRond: CGFloat {
        #if os(iOS)
        38
        #else
        46
        #endif
    }

    /// Les ronds, côte à côte : les votes en cours, puis les étapes à placer.
    private var boutonsRonds: some View {
        HStack(spacing: 8) {
            // Un vote en cours : raccourci vers la fenêtre des votes.
            if !voyage.votesOuverts.isEmpty { boutonVotes }
            boutonEtapesAPlacer
        }
    }

    /// Votes en cours : la pastille rouge compte ceux où ma famille n'a pas encore voté.
    private var boutonVotes: some View {
        let enAttente = voyage.votesEnAttenteDeMoi.count
        return Button { votesOuverts = true } label: {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: tailleRond * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: tailleRond, height: tailleRond)
                .background(Circle().fill(Color.purple))
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .overlay(alignment: .topTrailing) {
                    if enAttente > 0 {
                        Text("\(enAttente)")
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(.red))
                            .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                            .offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(enAttente > 0 ? "Votes en cours, \(enAttente) en attente de ma voix" : "Votes en cours")
        .help("Vote en cours : ouvrir les votes")
    }

    /// Ouvre ou ferme la fenêtre des étapes à placer ; une pastille rouge donne le nombre d'étapes qui attendent.
    private var boutonEtapesAPlacer: some View {
        let nombre = voyage.etapesSansJour.count
        return Button {
            withAnimation(.snappy) { etapesAPlacerOuvertes.toggle() }
            Self.etapesAPlacerOuvertesSession = etapesAPlacerOuvertes
        } label: {
            // Toujours le bac : ouvert, le rond s'inverse (fond blanc) au lieu de devenir une croix qu'on prendrait pour « fermer le voyage ».
            Image(systemName: "tray.full.fill")
                .font(.system(size: tailleRond * 0.4, weight: .semibold))
                .foregroundStyle(etapesAPlacerOuvertes ? Color.accentColor : .white)
                .frame(width: tailleRond, height: tailleRond)
                .background(Circle().fill(etapesAPlacerOuvertes ? Color.white : Color.accentColor))
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .overlay(alignment: .topTrailing) {
                    if nombre > 0 {
                        Text("\(nombre)")
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(.red))
                            .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                            .offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etapesAPlacerOuvertes ? "Fermer les étapes à placer" : "Étapes à placer : \(nombre)")
        .help(etapesAPlacerOuvertes ? "Fermer les étapes à placer" : "Étapes à placer")
    }

    private func fondDeCarte(margeGauche: CGFloat) -> some View {
        // Une sous-étape pas encore placée sur la carte : la carte reste sur son étape.
        CarteDuVoyage(voyage: voyage, jourFocus: jourSelectionne, masquerAutresJours: false, margeGauche: margeGauche,
                      cadrageFige: poignee != nil,
                      etapeFocus: sousEtapeEnEdition.flatMap { $0.coordonnee == nil ? nil : $0 } ?? etapeEnEdition,
                      onLieu: voyage.lectureSeule ? nil : { creerEtape(depuis: $0) },
                      ajoutSousEtape: etapeQuiPeutRecevoir.map { parente in
                          (parente.titre.isEmpty ? "l'étape" : parente.titre, { lieu in
                              let s = voyage.creerEtape(depuis: lieu, jour: nil, dans: contexte)
                              withAnimation(.snappy) { _ = parente.rattacher(s, avant: nil) }
                          })
                      }) { etape in
            ouvrir(etape)
        }
    }

    /// L'étape ouverte, quand un lieu touché sur la carte peut devenir une de ses sous-étapes.
    private var etapeQuiPeutRecevoir: Etape? {
        guard !voyage.lectureSeule, let e = etapeEnEdition, !e.estSousEtape, sousEtapeEnEdition == nil else { return nil }
        return e
    }

    // MARK: Détail d'une étape

    /// Le détail de l'étape, dans un cadre qui recouvre la colonne des jours : la carte reste libre à côté.
    @ViewBuilder private var cadreEtape: some View {
        if let etape = etapeEnEdition {
            EtapeEditView(etape: etape, jours: voyage.jours, onSupprimer: {
                if etapeEnEdition === etape { etapeEnEdition = nil }
                contexte.delete(etape)
            }, onFermer: { fermerEtape() }, onDupliquer: { ouvrir($0) },
               sousEtapeAOuvrir: sousEtapeDemandee, onSousEtape: { s in
                sousEtapeEnEdition = s
                if s == nil { sousEtapeDemandee = nil }
            })
            .id(etape.uid)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(FondDeCarte())
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private func ouvrir(_ etape: Etape) {
        // Une sous-étape s'ouvre dans la fiche de son étape.
        if let parente = etape.etapeParente {
            if etapeEnEdition !== parente { ouvrir(parente) }
            sousEtapeDemandee = etape
            return
        }
        // Passer d'une étape à l'autre : l'étape quittée, si elle est restée vide, est retirée.
        if etapeEnEdition.map({ $0 !== etape }) ?? false {
            nettoyer(sauf: etape)
            sousEtapeEnEdition = nil
        }
        sousEtapeDemandee = nil
        withAnimation(.snappy) { etapeEnEdition = etape }
    }

    private func fermerEtape() {
        withAnimation(.snappy) { etapeEnEdition = nil }
        sousEtapeEnEdition = nil
        sousEtapeDemandee = nil
        nettoyer()
    }

    /// Les jours, les uns au-dessus des autres.
    private func listeDesJours(avecEtapesAPlacer: Bool) -> some View {
        LazyVStack(spacing: 12) {
            // iPhone : les étapes sans jour, au-dessus du jour 1 (les ronds sont dans la barre du haut).
            if avecEtapesAPlacer && etapesAPlacerOuvertes { etapesAPlacer }
            ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                carte(numero: index + 1, jour: jour)
                nuit(apres: jour)
            }
            if !horsDates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hors des dates du voyage").font(.headline)
                    ForEach(horsDates) { ligne($0) }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(FondDeCarte())
            }
        }
    }

    /// Étapes préparées sans jour : on les glisse sur la carte d'un jour pour les placer.
    private var etapesAPlacer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Étapes à placer", systemImage: "tray.full").font(.headline)
            Text("Glisse une étape sur un jour.").font(.footnote).foregroundStyle(.secondary)
            Divider()
            ForEach(voyage.etapesSansJourParCategorie, id: \.categorie) { groupe in
                Label(groupe.categorie.libelle, systemImage: groupe.categorie.symbole)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(groupe.etapes) { etape in
                    ligne(etape)
                        .draggable(Self.prefixe + etape.uid) {
                            Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                                .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
            }
            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouterSansJour() }
                .disabled(voyage.lectureSeule)
                .buttonStyle(.borderless)
            // L'itinéraire préparé par Claude : une étape à placer qui contient toutes les siennes, avec leurs transports.
            BoutonImportClaude(voyage: voyage) { _ in
                withAnimation(.snappy) { etapesAPlacerOuvertes = true }
                Self.etapesAPlacerOuvertesSession = true
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    /// Un point d'intérêt touché sur la carte devient une étape à placer, et sa fiche s'ouvre.
    private func creerEtape(depuis lieu: LieuCarte) {
        let etape = voyage.creerEtape(depuis: lieu, jour: nil, dans: contexte)
        withAnimation(.snappy) { etapesAPlacerOuvertes = true }
        Self.etapesAPlacerOuvertesSession = true
        ouvrir(etape)
    }

    private func ajouterSansJour() {
        let etape = Etape(titre: "", jour: nil)
        etape.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        ouvrir(etape)
    }

    // MARK: Hébergements entre deux jours

    private func texteNuit(_ jour: Date) -> String {
        let lendemain = cal.date(byAdding: .day, value: 1, to: jour) ?? jour
        return "Nuit du \(jour.formatted(.dateTime.day().month(.abbreviated))) au \(lendemain.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// Bande entre deux jours : les hébergements de la nuit, ou un bouton pour en ajouter un.
    @ViewBuilder private func nuit(apres jour: Date) -> some View {
        if voyage.hebergements(apres: jour).isEmpty && voyage.transportDeNuit(apres: jour) == nil {
            nuitVide(apres: jour)
        } else {
            nuitRemplie(apres: jour)
        }
    }

    /// Une nuit sans hébergement ni transport : une simple ligne d'ajout, de la couleur du jour, qui accepte aussi une étape lâchée dessus.
    private func nuitVide(apres jour: Date) -> some View {
        let vise = nuitVisee.map { cal.isDate($0, inSameDayAs: jour) } ?? false
        let couleurJour = CarteDuVoyage.couleur(du: voyage.jours.firstIndex { cal.isDate($0, inSameDayAs: jour) } ?? 0)
        return Button { ajouterHebergement(apres: jour) } label: {
            Label("Nuit : ajouter un hébergement ou un transport", systemImage: "moon.zzz")
                .font(.footnote)
                .foregroundStyle(couleurJour.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 6)
                // Un fond discret mais plein : la carte, dessous, ne transparaît pas à travers le texte.
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(couleurJour.opacity(vise ? 0.25 : 0.06))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(voyage.lectureSeule)
        .dropDestination(for: String.self) { elements, _ in
            guard !voyage.lectureSeule else { return false }
            defer { nuitVisee = nil }
            guard let etape = etapeGlissee(elements) else { return false }
            return demanderNuit(etape, apres: jour)
        } isTargeted: { visee in
            if visee { nuitVisee = jour } else if let actuel = nuitVisee, cal.isDate(actuel, inSameDayAs: jour) { nuitVisee = nil }
        }
    }

    private func nuitRemplie(apres jour: Date) -> some View {
        let hebergements = voyage.hebergements(apres: jour)
        let vise = nuitVisee.map { cal.isDate($0, inSameDayAs: jour) } ?? false
        let couleurNuit = voyage.couleurNuit(apres: jour)
        return VStack(alignment: .leading, spacing: 8) {
            // Sans hébergement : seulement le bouton d'ajout. Avec : le titre de la nuit et les hébergements.
            if !hebergements.isEmpty {
                Label(texteNuit(jour), systemImage: "moon.zzz.fill")
                    .font(.caption.bold()).foregroundStyle(couleurNuit)
            }
            ForEach(hebergements) { h in
                VStack(alignment: .leading, spacing: 2) {
                    ligne(h)
                }
                .draggable(Self.prefixe + h.uid) {
                    Label(h.titre.isEmpty ? "Hébergement" : h.titre, systemImage: h.categorie.symbole)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if hebergements.isEmpty, let t = voyage.transportDeNuit(apres: jour), let transport = t.depart.transport {
                ligneTransportDeNuit(transport, depart: t.depart, arrivee: t.arrivee)
            }
            if hebergements.isEmpty {
                Button("Ajouter un hébergement ou un transport", systemImage: "plus.circle.fill") { ajouterHebergement(apres: jour) }
                .disabled(voyage.lectureSeule)
                    .buttonStyle(.borderless).tint(couleurNuit).font(.footnote)
            } else {
                // Une nuit peut avoir plusieurs hébergements (deux familles, deux logements).
                Button("Ajouter un autre hébergement", systemImage: "plus.circle") { ajouterHebergement(apres: jour) }
                .disabled(voyage.lectureSeule)
                    .buttonStyle(.borderless).tint(couleurNuit).font(.caption)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Un fond plein sous la teinte menthe : la carte ne transparaît pas à travers la bande.
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(couleurNuit.opacity(vise ? 0.38 : 0.22))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(couleurNuit.opacity(0.6), style: StrokeStyle(lineWidth: vise ? 2 : 1, dash: hebergements.isEmpty ? [5, 4] : [])))
        .dropDestination(for: String.self) { elements, _ in
            guard !voyage.lectureSeule else { return false }
            defer { nuitVisee = nil }
            // Toute étape lâchée sur la nuit devient un hébergement de cette nuit, à côté des autres.
            guard let etape = etapeGlissee(elements) else { return false }
            return demanderNuit(etape, apres: jour)
        } isTargeted: { visee in
            if visee { nuitVisee = jour } else if let actuel = nuitVisee, cal.isDate(actuel, inSameDayAs: jour) { nuitVisee = nil }
        }
    }


    private struct NuitTransport: Identifiable {
        let depart: Etape, arrivee: Etape
        var id: String { depart.uid }
    }

    /// Le transport entre deux étapes du jour, en une ligne fine : le mode, la distance et le temps. Un appui ouvre sa fiche.
    private func ligneTransport(_ t: Transport, depart: Etape, arrivee: Etape) -> some View {
        Button { transportDeNuitEnEdition = NuitTransport(depart: depart, arrivee: arrivee) } label: {
            HStack(spacing: 6) {
                Image(systemName: t.mode.symbole).font(.caption).frame(width: 24)
                Text(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt).font(.caption.weight(.medium))
                if t.mode.aUnItineraire, let a = depart.coordonnee, let b = arrivee.coordonnee {
                    Text("·").font(.caption)
                    ResumeItineraire(a: a, b: b, mode: t.mode, dureeModifiee: t.dureeModifiee, google: t.itineraireGoogle(a, b))
                } else if let resume = t.resume(depuis: depart, vers: arrivee) {
                    Text("· \(resume)").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(.separator.opacity(0.6)).frame(height: 0.5).padding(.leading, 30) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Le transport entre deux jours, présenté comme entre deux étapes ; un appui ouvre sa fiche.
    private func ligneTransportDeNuit(_ t: Transport, depart: Etape, arrivee: Etape) -> some View {
        Button { transportDeNuitEnEdition = NuitTransport(depart: depart, arrivee: arrivee) } label: {
            HStack(spacing: 8) {
                Image(systemName: t.mode.symbole).frame(width: 24)
                Text(voyage.descriptifLocal(t, depuis: depart, vers: arrivee))
                if t.mode.aUnItineraire, let a = depart.coordonnee, let b = arrivee.coordonnee {
                    Spacer()
                    ResumeItineraire(a: a, b: b, mode: t.mode, dureeModifiee: t.dureeModifiee, google: t.itineraireGoogle(a, b))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.indigo)
            .padding(.leading, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func etapeGlissee(_ elements: [String]) -> Etape? {
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count) else { return nil }
        return voyage.etapes.first { $0.uid == String(uid) }
    }

    private func ajouterHebergement(apres jour: Date) {
        let etape = Etape(titre: "", jour: jour, categorie: .hebergement)
        etape.apresJour = true
        etape.ordre = (voyage.hebergements(apres: jour).map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        nuitEnAjout = NuitAjout(etape: etape, jour: jour)
    }

    private func estSelectionne(_ jour: Date) -> Bool {
        jourSelectionne.map { cal.isDate($0, inSameDayAs: jour) } ?? false
    }

    /// Chaque hôtel de la nuit précédente et la première étape de ce jour, entre lesquels un transport peut être prévu.
    private func transportsDeLaVeille(avant jour: Date) -> [NuitTransport] {
        let veille = cal.date(byAdding: .day, value: -1, to: jour) ?? jour
        return voyage.hebergements(apres: veille).compactMap { h in voyage.suivante(de: h).map { NuitTransport(depart: h, arrivee: $0) } }
    }

    // MARK: Carte d'un jour

    private func chargerMeteo() async {
        guard !voyage.joursPrevisibles.isEmpty else { return }
        if lieuMeteoVoyage == nil { lieuMeteoVoyage = await voyage.lieuMeteo() }
        await meteo.chargerJours(de: voyage, lieuVoyage: lieuMeteoVoyage)
    }

    private func meteoDuJour(_ jour: Date) -> MeteoJour? { meteo.prevision(jour, de: voyage, lieuVoyage: lieuMeteoVoyage) }

    private func carte(numero: Int, jour: Date) -> some View {
        let infos = voyage.infos(du: jour)
        let temps = meteoDuJour(jour)
        let etapes = voyage.etapes(du: jour)
        // Même couleur et mêmes numéros que le tracé et les repères sur la carte ; éclaircie sur un ciel, pour rester lisible.
        let couleur = temps == nil ? CarteDuVoyage.couleur(du: numero - 1) : CarteDuVoyage.couleur(du: numero - 1).eclaircie(0.72)
        let placees = etapes.filter { $0.coordonnee != nil }
        let incoherences = voyage.etapesAuxHorairesIncoherents(du: jour)
        let chevauchements = voyage.etapesEnChevauchement(du: jour)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { jourSelectionne = estSelectionne(jour) ? nil : jour }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(couleur)
                        if let temps { EtiquetteMeteo(meteo: temps) }
                        Spacer()
                    }
                    Text(premiereLettreEnMajuscule(jour.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                        .font(.title3.bold()).foregroundStyle(.primary)
                    if let titre = infos?.titre, !titre.isEmpty {
                        Text(titre).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let lieux = infos?.lieux, !lieux.isEmpty {
                        FlowLayout(espacement: 6) {
                            ForEach(lieux) { lieu in
                                Label(lieu.etiquette, systemImage: lieu.estPays ? "flag.fill" : "mappin.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(couleur.opacity(0.14), in: Capsule())
                                    .foregroundStyle(couleur)
                            }
                        }
                    } else {
                        Label("Où se passe la journée ?", systemImage: "mappin.and.ellipse")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Premier jour : le transport d'aller (et, pour un vol, son terminal, sa porte…) ouvre la journée.
            if numero == 1 {
                PaveExtremite(voyage: voyage, extremite: .aller) { extremiteEnEdition = .aller }
            }

            // Transport prévu après l'hôtel de la veille : il ouvre la journée.
            ForEach(transportsDeLaVeille(avant: jour)) { t in
                if let transport = t.depart.transport {
                    ligneTransportDeNuit(transport, depart: t.depart, arrivee: t.arrivee)
                }
            }

            if etapes.isEmpty {
                Text("Aucune étape").font(.footnote).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(etapes.enumerated()), id: \.element.uid) { i, etape in
                        ligneGlissable(etape, jour: jour, couleur: couleur,
                                       rang: placees.firstIndex { $0 === etape }, incoherence: incoherences[etape.uid], chevauche: chevauchements[etape.uid])
                            // Sur le ciel de la météo : un cadre plus opaque, pour lire le détail de l'étape.
                            .cadreSurCiel(temps != nil)
                        // Le transport prévu vers l'étape suivante du jour : une ligne fine entre les deux.
                        if let transport = etape.transport, i + 1 < etapes.count {
                            ligneTransport(transport, depart: etape, arrivee: etapes[i + 1])
                        } else if let transport = etape.transport, let hebergement = voyage.hebergementVise(depuis: etape, apres: jour) {
                            // Après la dernière étape : le trajet jusqu'à l'hébergement de la nuit (celui choisi s'il y en a plusieurs).
                            ligneTransport(transport, depart: etape, arrivee: hebergement)
                        }
                    }
                }
            }

            // Dernier jour : le transport de retour la termine.
            if numero == voyage.jours.count {
                PaveExtremite(voyage: voyage, extremite: .retour) { extremiteEnEdition = .retour }
            }

            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(le: jour) }
                .disabled(voyage.lectureSeule)
                .buttonStyle(.borderless)
                .tint(couleur)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Le ciel prévu ce jour-là, en fond, et le contenu en clair par-dessus (comme l'app Météo).
        .cielMeteo(temps)
        .modifier(FondDeCarte())
        .overlay(alignment: .leading) {
            Capsule().fill(couleur).frame(width: 5).padding(.vertical, 16).padding(.leading, 5)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: -12) {
                boutonParcours(jour, numero: numero)
                boutonNotes(jour, infos: infos)
            }
        }
        .background {
            if notesSontOuvertes(jour) {
                GeometryReader { g in Color.clear.preference(key: HautCarteNotes.self, value: g.frame(in: .named(Self.espace)).minY) }
            }
        }
        .overlay {
            if estSelectionne(jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2.5)
            }
        }
        .overlay {
            if let jourVise, cal.isDate(jourVise, inSameDayAs: jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2)
            }
        }
        .dropDestination(for: String.self) { elements, _ in
            guard !voyage.lectureSeule else { return false }
            return recevoir(elements, jour: jour, avant: nil)
        } isTargeted: { visee in
            if visee { jourVise = jour } else if let actuel = jourVise, cal.isDate(actuel, inSameDayAs: jour) { jourVise = nil }
        }
    }

    // MARK: Glisser-déposer

    private static let prefixe = Etape.prefixeGlisser

    private func ligneGlissable(_ etape: Etape, jour: Date, couleur: Color, rang: Int?, incoherence: Date?, chevauche: Etape? = nil) -> some View {
        ligne(etape, couleur: couleur, rang: rang, incoherence: incoherence, chevauche: chevauche)
            .draggable(Self.prefixe + etape.uid) {
                Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .top) {
                if etapeVisee == etape.uid {
                    Capsule().fill(.tint).frame(height: 3).offset(y: -7)
                }
            }
            .dropDestination(for: String.self) { elements, _ in
            guard !voyage.lectureSeule else { return false }
                return recevoir(elements, jour: jour, avant: etape)
            } isTargeted: { visee in
                if visee { etapeVisee = etape.uid } else if etapeVisee == etape.uid { etapeVisee = nil }
            }
    }

    private static let espace = "itineraire"

    /// Position de défilement des jours, retenue par voyage (une pour l'écran large, une pour l'iPhone : leurs mises en page diffèrent).
    private func cleDefilement(large: Bool) -> String { "itineraire-\(voyage.uid)-\(large ? "large" : "etroit")" }

    private func notesSontOuvertes(_ jour: Date) -> Bool {
        notesOuvertes.map { cal.isDate($0, inSameDayAs: jour) } ?? false
    }

    /// Le post-it de la carte : ouvre ou ferme les notes du jour. Un appui long propose de modifier le jour ou de trier ses étapes.
    /// Lance l'animation du parcours de la journée.
    private func boutonParcours(_ jour: Date, numero: Int) -> some View {
        Button { parcoursJoue = ParcoursJourChoisi(jour: jour, numero: numero) } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(CarteDuVoyage.couleur(du: numero - 1), in: Circle())
                .padding(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jouer le parcours de la journée")
        .accessibilityLabel("Jouer le parcours de la journée")
    }

    private func boutonNotes(_ jour: Date, infos: JourVoyage?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { notesOuvertes = notesSontOuvertes(jour) ? nil : jour }
        } label: {
            IconePostIt(ecrit: !(infos?.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ouvert: notesSontOuvertes(jour))
                .frame(width: 26, height: 26)
                .padding(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Notes du jour")
        .accessibilityLabel(notesSontOuvertes(jour) ? "Fermer les notes du jour" : "Notes du jour")
        .contextMenu { actionsDuJour(jour, infos: infos) }
    }

    @ViewBuilder private func actionsDuJour(_ jour: Date, infos: JourVoyage?) -> some View {
        Button("Modifier le jour", systemImage: "pencil") { jourEnEdition = infos ?? creerInfos(jour) }
        Button("Trier par heure", systemImage: "clock") { trierParHeure(jour) }
            .disabled(voyage.etapes(du: jour).count < 2)
    }

    /// Les notes du jour, sur un post-it qu'on peut écrire directement.
    private func cadreNotes(_ jour: Date, numero: Int) -> some View {
        let infos = voyage.infos(du: jour)
        let texte = Binding<String>(
            get: { voyage.infos(du: jour)?.notes ?? "" },
            set: { nouveau in
                if let infos = voyage.infos(du: jour) { infos.notes = nouveau } else if !nouveau.isEmpty { creerInfos(jour).notes = nouveau }
            })
        let miseEnForme = Binding<Data?>(
            get: { voyage.infos(du: jour)?.notesMiseEnForme },
            set: { nouveau in
                if let infos = voyage.infos(du: jour) { infos.notesMiseEnForme = nouveau } else if nouveau != nil { creerInfos(jour).notesMiseEnForme = nouveau }
            })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notes · Jour \(numero) · \(jour.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))", systemImage: "note.text")
                    .font(.subheadline.bold())
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Menu { actionsDuJour(jour, infos: infos) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Button { withAnimation(.easeInOut(duration: 0.2)) { notesOuvertes = nil } } label: {
                    Image(systemName: "xmark").font(.subheadline.bold())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Color.black.opacity(0.7))
            EditeurNotes(texte: texte, donnees: miseEnForme, lectureSeule: voyage.lectureSeule, invite: "Écris ici tes notes pour ce jour…")
                .id(jour)
                // Sur iPhone, le post-it tient entre le haut de l'écran et le clavier : la zone d'écriture reste visible en tapant.
                .frame(minHeight: ecranLarge ? 220 : 150, maxHeight: ecranLarge ? 380 : 180)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                // Opaque : ouvert par-dessus la carte (iPhone), rien ne doit transparaître.
                .fill(LinearGradient(colors: [IconePostIt.jaune, Color(red: 0.98, green: 0.82, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
        )
        .environment(\.colorScheme, .light)
    }

    private func recevoir(_ elements: [String], jour: Date, avant cible: Etape?) -> Bool {
        defer { etapeVisee = nil; jourVise = nil }
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count) else { return false }
        // Un hébergement lâché parmi les étapes d'un jour y reste, en gardant sa catégorie.
        return deplacer(String(uid), vers: jour, avant: cible)
    }

    private func deplacer(_ uid: String, vers jour: Date, avant cible: Etape?) -> Bool {
        guard let etape = voyage.etapes.first(where: { $0.uid == uid }) else { return false }
        return demander(etape, vers: jour, avant: cible)
    }

    /// Déplace tout de suite, ou demande confirmation si des transports entre étapes seraient effacés.
    private func demander(_ etape: Etape, vers jour: Date?, avant cible: Etape?) -> Bool {
        if cible === etape { return false }
        let perdus = voyage.transportsPerdus(deplacant: etape, vers: jour, avant: cible)
        if perdus.isEmpty {
            return appliquer(DeplacementEnAttente(etape: etape, jour: jour, cible: cible, perdus: []))
        }
        deplacementEnAttente = DeplacementEnAttente(etape: etape, jour: jour, cible: cible, perdus: perdus)
        return true
    }

    private func demanderNuit(_ etape: Etape, apres jour: Date) -> Bool {
        let perdus = voyage.transportsPerdus(deplacant: etape, vers: jour, avant: nil, nuit: true)
        let d = DeplacementEnAttente(etape: etape, jour: jour, cible: nil, perdus: perdus, nuit: true)
        if perdus.isEmpty { return appliquer(d) }
        deplacementEnAttente = d
        return true
    }

    @discardableResult
    private func appliquer(_ d: DeplacementEnAttente) -> Bool {
        withAnimation {
            for e in d.perdus { e.transport = nil }
            if d.nuit, let jour = d.jour {
                d.etape.categorie = .hebergement
                voyage.placerEntreJours(d.etape, apres: jour)
                return true
            }
            if let jour = d.jour { return voyage.deplacer(d.etape, vers: jour, avant: d.cible) }
            return voyage.retirerDuJour(d.etape)
        }
    }

    private func trierParHeure(_ jour: Date) {
        withAnimation { voyage.trierParHeure(jour) }
    }

    /// `rang` : numéro du repère sur la carte (étapes placées seulement) ; sinon l'icône de la catégorie.
    /// `incoherence` : heure de l'étape précédente qui contredit celle-ci (l'étape est placée après une étape plus tardive).
    private func ligne(_ etape: Etape, couleur: Color = .accentColor, rang: Int? = nil, incoherence: Date? = nil, chevauche: Etape? = nil) -> some View {
        HStack(spacing: 12) {
                Group {
                    if let rang, etape.categorie == .repas {
                        // Un repas : l'assiette numérotée entre la fourchette et le couteau, comme sur la carte.
                        PionRepas(numero: rang + 1, couleur: couleur, taille: 22)
                    } else if let rang, etape.categorie == .hebergement {
                        // Un hébergement : un lit de la couleur du jour, son numéro dans une pastille.
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(couleur)
                            .frame(width: 34, height: 24)
                            .overlay(alignment: .topTrailing) {
                                Text("\(rang + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(couleur, in: Circle())
                                    .overlay(Circle().stroke(FondDePage.carte, lineWidth: 1.5))
                                    .offset(x: 4, y: -7)
                            }
                    } else if let rang {
                        Text("\(rang + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(couleur, in: Circle())
                    } else {
                        Image(systemName: etape.categorie.symbole)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(couleur)
                    }
                }
                // Même largeur pour tous les repères : les titres restent alignés d'une ligne à l'autre.
                .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).font(.headline).foregroundStyle(.primary)
                        // Étape favorite : un petit cœur après son nom.
                        if Favoris.partage.estFavorite(etape) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
                                .accessibilityLabel("Favorite")
                        }
                        // Une étape qui contient des sous-étapes (un circuit…) : leur nombre, avec le même symbole que sur la carte.
                        let nombreSous = etape.sousEtapes.count
                        if nombreSous > 0 {
                            Label("\(nombreSous)", systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.caption.weight(.semibold)).foregroundStyle(.mint)
                                .accessibilityLabel("\(nombreSous) sous-étape\(nombreSous > 1 ? "s" : "")")
                        }
                    }
                    if let note = etape.noteTripadvisor, let avis = etape.avisTripadvisor {
                        NotesView(tripadvisor: (note, avis))
                    }
                    if !etape.lieu.isEmpty {
                        Text(etape.lieu).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Sans horaire : la durée prévue, si on l'a notée.
                if etape.heure == nil, etape.heureFin == nil, let duree = etape.duree {
                    Label(CategorieEtape.texteDuree(duree), systemImage: "hourglass")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if etape.heure == nil, let fin = etape.heureFin {
                    Text("→ \(etape.heureAffichee(fin))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let heure = etape.heure {
                    if incoherence != nil || chevauche != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(chevauche != nil && incoherence == nil ? "Cette étape chevauche la précédente" : "Horaire incohérent avec l'ordre des étapes")
                            .help(chevauche != nil && incoherence == nil ? "Cette étape commence avant la fin de la précédente" : "Cette étape est prévue avant l'étape précédente")
                            .onTapGesture { avertissementOuvert = etape.uid }
                            .popover(isPresented: Binding(get: { avertissementOuvert == etape.uid },
                                                          set: { if !$0 { avertissementOuvert = nil } })) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(incoherence == nil ? "Horaires qui se chevauchent" : "Horaire incohérent", systemImage: "exclamationmark.triangle.fill")
                                        .font(.headline).foregroundStyle(.orange)
                                    if incoherence == nil, let autre = chevauche, let fin = autre.heureFin {
                                        Text("Cette étape commence à \(etape.heureAffichee(heure)), mais « \(autre.titre) » dure jusqu'à \(autre.heureAffichee(fin)). Change une des heures.")
                                            .font(.subheadline)
                                    } else if let incoherence {
                                    Text("Cette étape est prévue à \(etape.heureAffichee(heure)), mais elle est placée après une étape prévue à \(incoherence.formatted(date: .omitted, time: .shortened)). Change l'heure, ou son rang dans la journée.")
                                        .font(.subheadline)
                                    }
                                    Text("Le menu « ··· » du jour propose « Trier par heure ».")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding()
                                .frame(width: 320)
                                .fixedSize(horizontal: false, vertical: true)
                                .presentationCompactAdaptation(.popover)
                            }
                    }
                    Text(etape.heureFin.map { "\(etape.heureAffichee(heure)) – \(etape.heureAffichee($0))" }
                         ?? etape.heureAffichee(heure))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(incoherence == nil && chevauche == nil ? Color.secondary : Color.orange)
                }
                // La première photo enregistrée du lieu, en vignette.
                // La photo du lieu, sinon la première de l'album.
                if let photo = etape.photosDuLieu.min(by: { $0.nom < $1.nom }) ?? etape.album.first {
                    ImageDonnees(donnees: photo.donnees)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .contentShape(Rectangle())
        // Pas de Button : sur Mac, un bouton capte le clic et empêche de démarrer un glissé à la souris.
        .onTapGesture { ouvrir(etape) }
        .accessibilityAddTraits(.isButton)
    }

    private func premiereLettreEnMajuscule(_ texte: String) -> String {
        texte.prefix(1).uppercased() + texte.dropFirst()
    }

    // MARK: Création et nettoyage

    private func creerInfos(_ jour: Date) -> JourVoyage {
        let infos = JourVoyage(date: jour)
        infos.voyage = voyage
        contexte.insert(infos)
        return infos
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer(sauf gardee: Etape? = nil) {
        for etape in voyage.etapes where etape !== gardee && etape.sansContenu {
            contexte.delete(etape)
        }
    }

    private func nettoyerJours() {
        for infos in voyage.infosJours where infos.estVide { contexte.delete(infos) }
    }

    private func ajouter(le jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.ordre = voyage.prochainOrdre(du: jour)
        etape.voyage = voyage
        contexte.insert(etape)
        ouvrir(etape)
    }
}

/// Haut de la carte du jour aux notes ouvertes, dans le repère de l'Itinéraire.
private struct HautCarteNotes: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
