import SwiftUI
import SwiftData
import MapKit

struct EtapeEditView: View {
    @Bindable var etape: Etape
    var jours: [Date]
    var onSupprimer: () -> Void
    /// Fiche ouverte dans un cadre posé sur la colonne des jours (Itinéraire) : fermée par ce rappel au lieu d'une feuille.
    var onFermer: (() -> Void)? = nil
    /// Reçoit l'étape qui vient d'être créée par « Dupliquer » ou « Revenir à… » (l'Itinéraire l'ouvre) ; sans rappel, la fiche reste sur l'original.
    var onDupliquer: ((Etape) -> Void)? = nil
    /// Ouverte depuis un vote : les infos du lieu remontent juste sous la catégorie, pour comparer les propositions.
    var depuisVote = false
    /// Sous-étape à ouvrir dès l'affichage (touchée sur la carte) : la fiche de l'étape s'ouvre directement sur elle.
    var sousEtapeAOuvrir: Etape? = nil
    /// Prévenu quand une sous-étape s'ouvre ou se referme (nil) : l'Itinéraire cadre alors la carte sur elle.
    var onSousEtape: ((Etape?) -> Void)? = nil
    /// Fiche d'une sous-étape affichée dans celle de son étape, elle-même dans une feuille (et non dans un cadre de l'Itinéraire).
    var imbriqueeDansFeuille = false
    /// Petit message « Copie créée » après une duplication.
    @State private var copieFaite = false
    /// Le pays de l'étape est en cours de recherche pour la garder en favori.
    @State private var rechercheFavori = false
    @State private var sansPaysFavori = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titreActif: Bool
    /// Case de la durée en cours de saisie (« h » ou « min ») : son contenu est sélectionné dès qu'on y entre.
    @FocusState private var caseDureeActive: String?
    @State private var rechercheOuverte = false
    @State private var transportOuvert = false
    @State private var suggestionsOuvertes = false
    @State private var photosEnCours = false
    @Environment(\.horizontalSizeClass) private var tailleHorizontale
    @Environment(\.modelContext) private var contexte
    /// Sous-étape dont la fiche remplace celle de l'étape ; « OK » ramène à l'étape.
    @State private var sousEtapeOuverte: Etape?
    /// Transport entre deux sous-étapes, en cours de modification.
    @State private var transportSousEtapes: PaireSousEtapes?
    /// Étape glissée au-dessus de la liste des sous-étapes (uid de la sous-étape visée, ou "" pour la fin).
    @State private var depotVise: String?

    private struct PaireSousEtapes: Identifiable {
        let depart: Etape, arrivee: Etape
        var id: String { depart.uid }
    }

    private var enCadre: Bool { onFermer != nil && !imbriqueeDansFeuille }

    private func fermer() {
        if let onFermer { onFermer() } else { dismiss() }
    }

    /// Écran large (iPad, Mac) : les idées s'affichent dans un panneau à droite de la fiche.
    /// Dans un cadre, la place manque : elles restent dans une feuille.
    private var panneauLateral: Bool {
        #if os(macOS)
        !enCadre
        #else
        !enCadre && tailleHorizontale == .regular
        #endif
    }

    @State private var horaireOuvert = false
    @State private var suppressionDemandee = false
    /// Vrai si la fiche s'est ouverte sur une étape toute neuve (sans nom ni lieu) : « Annuler l'ajout » la retire sans question.
    @State private var nouvelle: Bool?

    /// Sans jour, l'étape n'a pas non plus d'horaires.
    private var jourChoisi: Binding<Date?> {
        Binding(get: { etape.jour },
                set: {
                    // Un hébergement qui n'était pas parmi les étapes d'un jour va dans la nuit qui suit le jour choisi.
                    let dansUnJour = etape.jour != nil && !etape.apresJour
                    etape.jour = $0
                    if let jour = $0, etape.categorie == .hebergement, !dansUnJour, let voyage = etape.voyage { voyage.placerEntreJours(etape, apres: jour) }
                    if $0 == nil { etape.heure = nil; etape.heureFin = nil; etape.apresJour = false; horaireOuvert = false }
                })
    }

    private var horaireActive: Binding<Bool> {
        Binding(get: { horaireOuvert || etape.heure != nil || etape.heureFin != nil },
                set: {
                    horaireOuvert = $0
                    if !$0 { etape.heure = nil; etape.heureFin = nil }
                })
    }

    /// Début : avec une durée connue, l'heure de fin suit.
    private var heureDebut: Binding<Date?> {
        Binding(get: { etape.heure },
                set: {
                    etape.heure = $0
                    if let debut = $0, let duree = etape.duree { etape.heureFin = debut.addingTimeInterval(duree * 60) }
                })
    }

    /// Fin : choisie après le début, elle redonne la durée.
    private var heureDeFin: Binding<Date?> {
        Binding(get: { etape.heureFin },
                set: {
                    etape.heureFin = $0
                    if let debut = etape.heure, let fin = $0, fin > debut { etape.duree = fin.timeIntervalSince(debut) / 60 }
                })
    }

    /// Durée : avec une heure de début, l'heure de fin suit.
    private var dureeChoisie: Binding<Double?> {
        Binding(get: { etape.duree },
                set: {
                    etape.duree = $0
                    if let debut = etape.heure {
                        etape.heureFin = $0.map { debut.addingTimeInterval($0 * 60) }
                    }
                })
    }

    /// Les heures et les minutes de la durée, saisies séparément ; les deux vides : durée non précisée.
    private var heuresDuree: Binding<Int?> {
        Binding(get: { etape.duree.map { Int($0.rounded()) / 60 } },
                set: { regler(heures: $0, minutes: etape.duree.map { Int($0.rounded()) % 60 }) })
    }

    private var minutesDuree: Binding<Int?> {
        Binding(get: { etape.duree.map { Int($0.rounded()) % 60 } },
                set: { regler(heures: etape.duree.map { Int($0.rounded()) / 60 }, minutes: $0) })
    }

    private func regler(heures: Int?, minutes: Int?) {
        let total = max(heures ?? 0, 0) * 60 + max(minutes ?? 0, 0)
        dureeChoisie.wrappedValue = (heures == nil && minutes == nil) || total == 0 ? nil : Double(total)
    }

    /// Sélectionne tout le texte de la case qui vient de prendre le focus : on tape la nouvelle valeur sans effacer l'ancienne.
    private func toutSelectionner() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        #else
        // Après la fin du clic : sinon le clic replace le curseur et annule la sélection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
        #endif
    }

    /// Une petite case blanche pour un nombre entier, comme celles des prix.
    private func caseDuree(_ valeur: Binding<Int?>, unite: String) -> some View {
        HStack(spacing: 3) {
            TextField("", value: valeur, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                // Sans libellé : dans un formulaire Mac, la place du libellé vide étirait la case en hauteur.
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(FondDePage.saisie, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.gray.opacity(0.35), lineWidth: 1))
                .foregroundStyle(.primary)
                .frame(width: 52)
                .focused($caseDureeActive, equals: unite)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(unite).foregroundStyle(.secondary).font(.callout)
        }
    }

    private func bulleHeure(_ valeur: Binding<Date?>, depart: Int) -> some View {
        BulleHeure(valeur: valeur, jour: etape.jourEffectif ?? .now, heureDeDepart: depart)
    }

    var body: some View {
        if enCadre || imbriqueeDansFeuille {
            ficheAffichee
        } else {
            ficheAffichee
                .modifier(TailleDePage())
                #if os(macOS)
                // Avec les idées, la fenêtre s'élargit pour que fiche et propositions tiennent côte à côte sans être tronquées.
                .frame(minWidth: suggestionsOuvertes ? 1020 : 420, idealWidth: suggestionsOuvertes ? 1080 : 520, minHeight: 600, idealHeight: 720)
                #endif
        }
    }

    /// La fiche de l'étape, ou celle de la sous-étape ouverte à sa place.
    @ViewBuilder private var ficheAffichee: some View {
        Group {
            if let sous = sousEtapeOuverte {
                EtapeEditView(etape: sous, jours: jours,
                              onSupprimer: { supprimerSousEtape(sous) },
                              onFermer: { fermerSousEtape() },
                              onDupliquer: { ouvrirSousEtape($0) },
                              imbriqueeDansFeuille: !enCadre)
                    .id(sous.uid)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                contenu
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .onAppear { if let s = sousEtapeAOuvrir { ouvrirSousEtape(s, anime: false) } }
        .onChange(of: sousEtapeAOuvrir?.uid) { if let s = sousEtapeAOuvrir { ouvrirSousEtape(s) } }
        .sheet(item: $transportSousEtapes) { TransportEditView(depart: $0.depart, arrivee: $0.arrivee) }
    }

    private var contenu: some View {
        HStack(spacing: 0) {
            formulaire
            if suggestionsOuvertes && panneauLateral {
                Divider()
                SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { valider($0) },
                                onFermer: { withAnimation { suggestionsOuvertes = false } })
                    .frame(minWidth: 480, idealWidth: 540, maxWidth: 620)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.default, value: suggestionsOuvertes)
        .sheet(isPresented: Binding(get: { suggestionsOuvertes && !panneauLateral }, set: { suggestionsOuvertes = $0 })) {
            SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { valider($0) },
                            onFermer: { suggestionsOuvertes = false })
        }
        .sheet(isPresented: $rechercheOuverte) {
            RechercheLieuView(requeteInitiale: etape.lieu.isEmpty ? etape.titre : etape.lieu,
                              pays: etape.voyage?.pays ?? []) { lieu in
                if etape.titre.trimmingCharacters(in: .whitespaces).isEmpty { etape.titre = lieu.nom }
                etape.lieu = lieu.adresse.isEmpty ? lieu.nom : "\(lieu.nom), \(lieu.adresse)"
                etape.latitude = lieu.coordonnee.latitude
                etape.longitude = lieu.coordonnee.longitude
            }
        }
        .onAppear {
            if etape.titre.isEmpty { titreActif = true }
            if nouvelle == nil { nouvelle = etape.titre.isEmpty && etape.lieu.isEmpty && etape.coordonnee == nil }
        }
        .onChange(of: caseDureeActive) { _, active in if active != nil { toutSelectionner() } }
    }

    /// En tête de la fiche : l'ampoule des idées, le nom de l'étape au centre (on le modifie en cliquant dessus), puis fermer.
    private var entete: some View {
        HStack(spacing: 10) {
            // Idées de lieux à visiter : une ampoule allumée, au niveau du titre.
            Button { suggestionsOuvertes = true } label: {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: .yellow.opacity(0.7), radius: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Idées de lieux à visiter")
            .help("Idées de lieux à visiter")
            // La catégorie, juste à gauche du nom.
            Image(systemName: etape.categorie.symbole)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.purple))
                .accessibilityLabel(etape.categorie.libelle)
                .help(etape.categorie.libelle)
            TextField(etape.categorie == .hebergement ? "Nom de l'hébergement" : "Nom de l'étape", text: $etape.titre)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .focused($titreActif)
                .onSubmit { titreActif = false }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4).padding(.horizontal, 6)
                // Un léger fond quand on écrit : on voit que le titre se modifie.
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(titreActif ? 0.12 : 0)))
                .help("Cliquer pour renommer")
            // Favori : un cœur, plein quand l'étape est gardée pour les prochains voyages dans son pays.
            if nouvelle != true, !etape.titre.trimmingCharacters(in: .whitespaces).isEmpty {
                let favorite = Favoris.partage.estFavorite(etape)
                Button {
                    Task {
                        rechercheFavori = true
                        sansPaysFavori = !(await Favoris.partage.basculer(etape))
                        rechercheFavori = false
                    }
                } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(favorite ? Color.red : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .opacity(rechercheFavori ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(rechercheFavori)
                .accessibilityLabel(favorite ? "Retirer des favoris" : "Ajouter aux favoris")
                .help(favorite ? "Retirer des favoris" : "Garder en favori : les voyageurs voient le cœur, et l'étape sera proposée dans les prochains voyages dans ce pays")
                .alert("Pays introuvable", isPresented: $sansPaysFavori) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Place l'étape sur la carte ou choisis les pays du voyage pour la garder en favori.")
                }
            }
            // Dupliquer : une icône discrète, à côté de la fermeture (pas en voyage : le programme est fixé).
            if !(etape.voyage?.lectureSeule ?? true), !enVoyage, nouvelle != true {
                Button { dupliquer() } label: {
                    Image(systemName: copieFaite ? "checkmark" : "plus.square.on.square")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(copieFaite ? Color.green : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dupliquer l'étape")
                .help(copieFaite ? "Copie créée" : "Dupliquer l'étape")
            }
            // « OK » bien visible : tout est enregistré au fil de la saisie, il ne reste qu'à refermer la fiche.
            Button { fermer() } label: {
                Text("OK")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("OK, fermer la fiche")
            .help("Fermer la fiche (tout est déjà enregistré)")
            // Échap ferme aussi la fiche.
            Button("") { fermer() }.keyboardShortcut(.cancelAction).hidden().frame(width: 0, height: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    /// Dans un cadre comme dans une feuille : l'en-tête, puis les sections.
    private var formulaire: some View {
        VStack(spacing: 0) {
            entete
            Divider()
            champs
        }
        .background(FondDePage.couleur)
    }

    /// Le transport pour aller à cette étape : porté par l'élément qui la précède, ou l'aller pour la toute première.
    private func transportPourArriver(_ voyage: Voyage) -> (transport: Transport?, vue: TransportEditView)? {
        let nom = etape.titre.isEmpty ? "Étape" : etape.titre
        if let depart = voyage.precedente(de: etape) {
            // Un hébergement parmi plusieurs dans la nuit : le transport de la dernière étape peut en viser un autre.
            let vise = !etape.apresJour || voyage.suivante(de: depart) === etape
            return (vise ? depart.transport : nil, TransportEditView(depart: depart, arrivee: etape))
        }
        guard voyage.elementsDuVoyage.first === etape else { return nil }
        let vue = TransportEditView(trajet: "Départ → \(nom)", jour: etape.jour ?? .now, coordonnees: nil,
                                    existant: voyage.transportAller, lieuxExtremites: true, voyage: voyage,
                                    cleLien: LienReservation.aller) { voyage.transportAller = $0 }
        return (voyage.transportAller, vue)
    }

    /// Les catégories proposées, hébergement en tête. Le transport a sa propre fenêtre, et « Nature » n'est plus proposée :
    /// on ne les garde que pour une étape qui l'est déjà.
    private var categories: [CategorieEtape] {
        [.hebergement] + CategorieEtape.allCases.filter {
            $0 != .hebergement && ((!CategorieEtape.retirees.contains($0)) || $0 == etape.categorie)
        }
    }

    /// Change la catégorie. Un hébergement de nuit qui n'en est plus un rejoint la fin des étapes de son jour.
    private func choisir(_ c: CategorieEtape) {
        withAnimation(.snappy) {
            etape.categorie = c
            if c != .hebergement, etape.apresJour, let jour = etape.jour, let voyage = etape.voyage {
                _ = voyage.deplacer(etape, vers: jour, avant: nil)
            }
        }
    }

    /// Une petite tuile par catégorie, côte à côte ; la catégorie choisie est remplie de couleur.
    private var tuilesCategories: some View {
        FlowLayout(espacement: 6) {
            ForEach(categories) { c in
                let choisie = etape.categorie == c
                Button { choisir(c) } label: {
                    Label(c.libelle, systemImage: c.symbole)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(choisie ? Color.white : Color.primary)
                        .background(Capsule().fill(choisie ? AnyShapeStyle(Color.purple) : AnyShapeStyle(FondDePage.carte)))
                        .overlay(Capsule().strokeBorder(Color.purple.opacity(choisie ? 0 : 0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choisie ? .isSelected : [])
            }
        }
    }

    /// En voyage, la catégorie, le jour et les horaires sont simplement rappelés, sans être modifiables.
    private var enVoyage: Bool { etape.voyage?.mode == .voyage }

    /// Les réservations liées à l'étape (ou à l'hébergement) : un bouton ouvre chacune d'elles.
    @ViewBuilder private var sectionReservations: some View {
        if let voyage = etape.voyage, !voyage.reservations(lieesA: LienReservation.etape(etape)).isEmpty {
            CadreSection("Réservation", symbole: "ticket", couleur: .indigo) {
                BoutonsReservations(voyage: voyage, cle: LienReservation.etape(etape))
            }
        }
    }

    private var sectionCategorie: some View {
        CadreSection("Catégorie", symbole: "square.grid.2x2", couleur: .purple) { tuilesCategories }
    }

    private func texteDuree(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min"
    }

    /// En voyage : la date, les horaires et la durée, en simple lecture, sans cadre ni titre.
    private var sectionJourHoraireLecture: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let parente = etape.etapeParente {
                Label("Dans « \(parente.titre.isEmpty ? "Sans titre" : parente.titre) »", systemImage: "point.3.connected.trianglepath.dotted")
            }
            if let jour = etape.jourEffectif {
                if etape.categorie == .hebergement, etape.apresJour, !etape.estSousEtape {
                    let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
                    Label("Nuit du \(jour.formatted(.dateTime.day().month(.wide))) au \(lendemain.formatted(.dateTime.day().month(.wide)))",
                          systemImage: "moon.stars")
                } else {
                    let date = jour.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    Label(date.prefix(1).uppercased() + date.dropFirst(), systemImage: "calendar")
                }
                if etape.heure != nil || etape.heureFin != nil {
                    Label([etape.heure, etape.heureFin].map { $0?.formatted(date: .omitted, time: .shortened) ?? "--:--" }.joined(separator: " → "),
                          systemImage: "clock")
                        .monospacedDigit()
                }
            } else {
                Label("Pas encore de jour", systemImage: "calendar").foregroundStyle(.secondary)
            }
            if let duree = etape.duree {
                Label(texteDuree(duree), systemImage: "hourglass")
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// La catégorie puis le moment ; en voyage, avec à droite l'appareil photo (iPhone, iPad) et le bouton qui guide jusqu'à l'étape.
    @ViewBuilder private var sectionCategorieEtMoment: some View {
        if enVoyage {
            HStack(alignment: .center, spacing: 12) {
                // La catégorie est dans la barre de titre, à gauche du nom.
                sectionJourHoraire
                #if os(iOS)
                // Une photo prise sur place va droit dans l'album de l'étape.
                BoutonPhotoAlbum(etape: etape)
                #endif
                BoutonYAller(etape: etape)
            }
        } else {
            sectionCategorie
            sectionJourHoraire
        }
    }

    @ViewBuilder private var sectionJourHoraire: some View {
        if enVoyage { sectionJourHoraireLecture } else { sectionJourHoraireEdition }
    }

    private var sectionJourHoraireEdition: some View {
        CadreSection("Jour et horaire", symbole: "calendar", couleur: .blue) {
            if let parente = etape.etapeParente {
                // Une sous-étape suit le jour de son étape.
                LabeledContent("Dans l'étape") {
                    Text(parente.titre.isEmpty ? "Sans titre" : parente.titre).foregroundStyle(.secondary).lineLimit(1)
                }
                if let jour = parente.jour {
                    let date = jour.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    LabeledContent("Jour") { Text(date.prefix(1).uppercased() + date.dropFirst()).foregroundStyle(.secondary) }
                }
            } else {
            LabeledContent("Jour") {
                Picker("Jour", selection: jourChoisi) {
                    Text("Pas encore de jour").tag(Date?.none)
                    ForEach(jours, id: \.self) { j in
                        Text(j.formatted(.dateTime.weekday(.wide).day().month())).tag(Date?.some(j))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            }
            if etape.jour != nil, etape.categorie == .hebergement, etape.apresJour, let jour = etape.jour {
                let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
                Text("Nuit du \(jour.formatted(.dateTime.day().month(.wide))) au \(lendemain.formatted(.dateTime.day().month(.wide)))")
                    .font(.footnote).foregroundStyle(.secondary)
                // Fait partie d'un séjour réservé sur plusieurs nuits : combien, et lesquelles.
                if let sejour = etape.voyage?.sejour(de: etape), let premiere = sejour.nuits.first, let derniere = sejour.nuits.last,
                   let depart = Calendar.current.date(byAdding: .day, value: 1, to: derniere) {
                    let rang = (sejour.nuits.firstIndex { Calendar.current.isDate($0, inSameDayAs: jour) } ?? 0) + 1
                    Label("Séjour de \(sejour.nuits.count) nuits (nuit \(rang)/\(sejour.nuits.count)), du \(premiere.formatted(.dateTime.day().month(.wide))) au \(depart.formatted(.dateTime.day().month(.wide)))",
                          systemImage: "moon.zzz")
                        .font(.footnote.weight(.medium)).foregroundStyle(.indigo)
                }
            }
            // Durée à la minute près : des heures et des minutes (au-delà de 59 min, elles passent en heures).
            HStack(spacing: 10) {
                Text("Durée").lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                caseDuree(heuresDuree, unite: "h")
                caseDuree(minutesDuree, unite: "min")
                if etape.duree != nil {
                    Button { dureeChoisie.wrappedValue = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer la durée")
                    .help("Effacer la durée")
                }
            }
            if etape.jourEffectif != nil { Toggle("Horaire", isOn: horaireActive) }
            if etape.jourEffectif != nil, horaireActive.wrappedValue {
                HStack {
                    Spacer()
                    bulleHeure(heureDebut, depart: 9)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    bulleHeure(heureDeFin, depart: (etape.heure.map { Calendar.current.component(.hour, from: $0) + 1 } ?? 10) % 24)
                }
                // L'heure saisie est celle du lieu de l'étape ; on peut la noter dans un autre fuseau.
                LigneFuseau(choisi: $etape.fuseauChoisi, parDefaut: etape.fuseauParDefaut,
                            coordonnees: etape.coordonnee.map { [$0] } ?? [])
            }
        }
    }

    /// Les photos prises sur place : celles de l'étape (ou de la sous-étape), réduites pour iCloud.
    @ViewBuilder private var sectionAlbum: some View {
        if etape.voyage != nil {
            CadreSection("Album photo", symbole: "photo.on.rectangle.angled", couleur: .indigo) {
                AlbumEtapeSection(etape: etape)
            }
        }
    }

    /// Ma note et mon commentaire, puis ce qu'en pensent les autres voyageurs.
    @ViewBuilder private var sectionAvis: some View {
        if let voyage = etape.voyage {
            CadreSection("Note et commentaires", symbole: "star.bubble", couleur: .pink) {
                AvisEtapeSection(voyage: voyage, etape: etape)
            }
        }
    }

    private var sectionBudget: some View {
        CadreSection("Budget", symbole: "eurosign.circle", couleur: .green, accessoire: { BoutonAutrePrix(autres: $etape.autresPrix) }) {
            // Une réservation liée avec un prix le remplace dans le Budget : le prix prévu est alors grisé.
            PrixPrevuOuReserve(voyage: etape.voyage, cle: LienReservation.etape(etape)) {
                LignesPrix(voyage: etape.voyage,
                           adulte: $etape.prixAdulte, adulteMonnaie: $etape.monnaieAdulte,
                           etudiant: $etape.prixEtudiant, etudiantMonnaie: $etape.monnaieEtudiant,
                           adolescent: $etape.prixAdolescent, adolescentMonnaie: $etape.monnaieAdolescent,
                           enfant: $etape.prixEnfant, enfantMonnaie: $etape.monnaieEnfant,
                           exclus: $etape.exclusBudget, bascules: $etape.basculesTarif,
                           autres: $etape.autresPrix)
            }
            // Séjour de plusieurs nuits : le prix de la réservation est réparti sur chacune.
            if let voyage = etape.voyage, let sejour = voyage.sejour(de: etape), let total = voyage.montant(de: sejour.reservation) {
                Label("Réservé pour \(sejour.nuits.count) nuits : \(Monnaies.formater(total.montant, total.devise)), soit \(Monnaies.formater(total.montant / Double(sejour.nuits.count), total.devise)) par nuit dans le Budget.",
                      systemImage: "moon.zzz")
                    .font(.footnote.weight(.medium)).foregroundStyle(.indigo)
            }
            piedBudget(etape.voyage).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Le lieu : la recherche d'abord (elle remplit le nom, l'adresse et les infos), la carte, les transports.
    private var sectionLieu: some View {
        CadreSection("Lieu", symbole: "mappin.and.ellipse", couleur: .orange) {
            TextField("Lieu ou adresse", text: $etape.lieu, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(FondDePage.carte))
            if etape.coordonnee == nil {
                Button { rechercheOuverte = true } label: {
                    Label("Chercher le lieu", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Cherche le lieu : son nom, son adresse et ses infos se remplissent")
            }
            if let coord = etape.coordonnee {
                // Dans un cadre, la grande carte à côté montre déjà le lieu.
                if !enCadre {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800)),
                        interactionModes: []) {
                        Marker(etape.titre, systemImage: etape.categorie.symbole, coordinate: coord)
                    }
                    .id("\(coord.latitude),\(coord.longitude)")
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Button("Retirer de la carte", systemImage: "mappin.slash", role: .destructive) {
                        etape.latitude = nil
                        etape.longitude = nil
                    }
                    Spacer()
                    Button("Changer de lieu", systemImage: "magnifyingglass") { rechercheOuverte = true }
                }
            }
            // Aller-retour : revenir là d'où l'on vient (l'hôtel, par exemple), juste après cette étape.
            if let depart = etape.departPourRetour, !(etape.voyage?.lectureSeule ?? true) {
                Button("Revenir à « \(depart.titre.isEmpty ? "l'étape précédente" : depart.titre) »", systemImage: "arrow.uturn.backward") {
                    guard let contexte = etape.modelContext, let retour = etape.ajouterRetour(dans: contexte) else { return }
                    onDupliquer?(retour)
                }
                .help("Ajoute après cette étape un retour vers l'étape d'où l'on vient, avec le même mode de transport")
            }
            if let voyage = etape.voyage, let existant = transportPourArriver(voyage) {
                Button(existant.transport == nil ? "Ajouter un transport" : "Modifier le transport", systemImage: "arrow.triangle.swap") {
                    transportOuvert = true
                }
                .sheet(isPresented: $transportOuvert) { existant.vue }
            }
        }
    }

    private var champs: some View {
        ScrollView {
            VStack(spacing: 14) {
                if depuisVote {
                    // Depuis un vote : de quoi comparer d'abord (le lieu, les avis, le prix), puis la catégorie et le moment.
                    if etape.aDesInfosDeLieu { infosDuLieu }
                    sectionAvis
                    sectionBudget
                    sectionCategorieEtMoment
                } else if enVoyage {
                    // En voyage : le moment (avec « Y aller »), les sous-étapes, les réservations, puis les infos du lieu avant les avis.
                    sectionCategorieEtMoment
                    // Sur place : on note l'heure réelle d'arrivée et de départ.
                    if etape.jourEffectif != nil { PointageEtape(etape: etape) }
                    sectionSousEtapes
                    sectionReservations
                    sectionAlbum
                    if etape.aDesInfosDeLieu { infosDuLieu }
                    sectionAvis
                    sectionBudget
                } else {
                    // En préparation : d'abord où (la recherche remplit le reste), puis quand, puis le coût et les avis.
                    sectionLieu
                    if etape.aDesInfosDeLieu { infosDuLieu }
                    sectionSousEtapes
                    sectionCategorieEtMoment
                    sectionReservations
                    sectionBudget
                    sectionAvis
                    sectionAlbum
                }
                // En préparation, le lieu est déjà plus haut ; ailleurs, il vient ici.
                if depuisVote || enVoyage { sectionLieu }
                CadreSection("Notes", symbole: "note.text", couleur: .yellow) {
                    TextEditor(text: $etape.notes)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 80)
                        .background(RoundedRectangle(cornerRadius: 8).fill(FondDePage.carte))
                }
                if nouvelle == true {
                    // Une étape toute neuve : on annule son ajout, sans question.
                    Button("Annuler l'ajout", systemImage: "xmark") { supprimerAvecSousEtapes(); fermer() }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.18)))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .buttonStyle(.plain)
                } else {
                Button(etape.categorie == .hebergement ? "Supprimer l'hébergement" : "Supprimer l'étape", systemImage: "trash", role: .destructive) {
                    // Une étape encore vide part sans question ; sinon on confirme.
                    if etape.sansContenu { onSupprimer(); fermer() }
                    else { suppressionDemandee = true }
                }
                .confirmerSuppression($suppressionDemandee,
                                      titre: titreSuppression) {
                    supprimerAvecSousEtapes()
                    fermer()
                }
                // Rouge plein, texte blanc : le bouton se voit bien, même en mode sombre.
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
                }
            }
            .buttonStyle(.borderless)
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .disabled(etape.voyage?.lectureSeule ?? false)
    }

    // MARK: Sous-étapes

    private var titreSuppression: String {
        let nom = etape.titre.isEmpty ? etape.categorie.libelle : etape.titre
        let n = etape.sousEtapes.count
        return n == 0 ? "Supprimer « \(nom) » ?" : "Supprimer « \(nom) » et ses \(n) sous-étape\(n > 1 ? "s" : "") ?"
    }

    /// L'étape part avec ses sous-étapes.
    private func supprimerAvecSousEtapes() {
        for s in etape.sousEtapes { contexte.delete(s) }
        onSupprimer()
    }

    private func ouvrirSousEtape(_ s: Etape, anime: Bool = true) {
        withAnimation(anime ? .snappy : nil) { sousEtapeOuverte = s }
        onSousEtape?(s)
    }

    /// « OK » sur une sous-étape : retour à l'étape. Une sous-étape laissée vide est retirée.
    private func fermerSousEtape() {
        if let s = sousEtapeOuverte, s.sansContenu { contexte.delete(s) }
        withAnimation(.snappy) { sousEtapeOuverte = nil }
        onSousEtape?(nil)
    }

    private func supprimerSousEtape(_ s: Etape) {
        contexte.delete(s)
        withAnimation(.snappy) { sousEtapeOuverte = nil }
        onSousEtape?(nil)
    }

    private func ajouterSousEtape() {
        ouvrirSousEtape(etape.ajouterSousEtape(dans: contexte))
    }

    /// Étapes à placer qui peuvent devenir des sous-étapes de celle-ci.
    private var etapesAPrendre: [Etape] {
        (etape.voyage?.etapesSansJour ?? []).filter { etape.peutRecevoir($0) }
    }

    private func etapeDeposee(_ elements: [String]) -> Etape? {
        guard let texte = elements.first(where: { $0.hasPrefix(Etape.prefixeGlisser) }) else { return nil }
        let uid = String(texte.dropFirst(Etape.prefixeGlisser.count))
        return etape.voyage?.etapes.first { $0.uid == uid }
    }

    /// Les sous-étapes (un circuit, une visite en plusieurs points), avec les transports de l'une à l'autre.
    /// On y glisse une étape à placer, ou on range les sous-étapes en les glissant.
    @ViewBuilder private var sectionSousEtapes: some View {
        if !etape.estSousEtape, !depuisVote {
            let sous = etape.sousEtapes
            let modifiable = !(etape.voyage?.lectureSeule ?? true)
            CadreSection("Sous-étapes", symbole: "point.3.connected.trianglepath.dotted", couleur: .mint) {
                if sous.isEmpty {
                    Text("Les points d'un circuit, d'une visite : ils restent dans l'étape, et n'apparaissent sur la carte que quand on la touche.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(sous.enumerated()), id: \.element.id) { i, s in
                        ligneSousEtape(s, rang: i + 1, modifiable: modifiable)
                        if i + 1 < sous.count { ligneTransportSousEtapes(s, sous[i + 1]) }
                    }
                }
                if modifiable {
                    HStack(spacing: 16) {
                        Button("Ajouter une sous-étape", systemImage: "plus.circle.fill") { ajouterSousEtape() }
                            .fontWeight(.semibold)
                        // Sur iPhone, la liste des étapes à placer est cachée par la fiche : on les prend d'ici.
                        if !etapesAPrendre.isEmpty {
                            Menu {
                                ForEach(etapesAPrendre) { e in
                                    Button(e.titre.isEmpty ? "Sans titre" : e.titre, systemImage: e.categorie.symbole) {
                                        withAnimation(.snappy) { _ = etape.rattacher(e, avant: nil) }
                                    }
                                }
                            } label: {
                                Label("Étapes à placer", systemImage: "tray.and.arrow.down")
                            }
                            .help("Faire d'une étape à placer une sous-étape")
                        }
                    }
                    if !etapesAPrendre.isEmpty {
                        Text("Tu peux aussi glisser ici une étape à placer.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            // Une étape à placer déposée sur la section devient la dernière sous-étape.
            .overlay {
                if depotVise == "" {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.mint, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                }
            }
            .dropDestination(for: String.self) { elements, _ in
                depotVise = nil
                guard modifiable, let e = etapeDeposee(elements) else { return false }
                return withAnimation(.snappy) { etape.rattacher(e, avant: nil) }
            } isTargeted: { vise in
                if vise { depotVise = "" } else if depotVise == "" { depotVise = nil }
            }
        }
    }

    /// Une sous-étape : son numéro, son nom, son lieu et son horaire. Un appui ouvre sa fiche ; on la glisse pour la ranger.
    private func ligneSousEtape(_ s: Etape, rang: Int, modifiable: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(rang)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.mint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(s.titre.isEmpty ? "Sans titre" : s.titre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !s.lieu.isEmpty {
                    Text(s.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if enVoyage { PastillePointage(etape: s).font(.caption) }
            if let heure = s.heure {
                Text(s.heureFin.map { "\(s.heureAffichee(heure)) – \(s.heureAffichee($0))" } ?? s.heureAffichee(heure))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else if let duree = s.duree {
                Label(CategorieEtape.texteDuree(duree), systemImage: "hourglass").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        // Trait d'insertion : l'étape glissée viendra juste avant celle-ci.
        .overlay(alignment: .top) {
            if depotVise == s.uid { Capsule().fill(Color.mint).frame(height: 3).offset(y: -2) }
        }
        .contentShape(Rectangle())
        // Pas de Button : sur Mac, un bouton capte le clic et empêche de glisser la ligne.
        .onTapGesture { ouvrirSousEtape(s) }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if modifiable {
                Button("Remettre dans les étapes à placer", systemImage: "tray.and.arrow.up") {
                    withAnimation(.snappy) { s.detacherDeSonEtape() }
                }
                Button("Supprimer la sous-étape", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy) { contexte.delete(s) }
                }
            }
        }
        .draggable(Etape.prefixeGlisser + s.uid) {
            Label(s.titre.isEmpty ? "Sous-étape" : s.titre, systemImage: s.categorie.symbole)
                .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { elements, _ in
            depotVise = nil
            guard modifiable, let e = etapeDeposee(elements) else { return false }
            return withAnimation(.snappy) { etape.rattacher(e, avant: s) }
        } isTargeted: { vise in
            if vise { depotVise = s.uid } else if depotVise == s.uid { depotVise = nil }
        }
    }

    /// Entre deux sous-étapes : le transport prévu (mode, distance, temps), ou de quoi en ajouter un.
    private func ligneTransportSousEtapes(_ a: Etape, _ b: Etape) -> some View {
        Button { transportSousEtapes = PaireSousEtapes(depart: a, arrivee: b) } label: {
            HStack(spacing: 6) {
                if let t = a.transport {
                    Image(systemName: t.mode.symbole).font(.caption).frame(width: 24)
                    Text(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt).font(.caption.weight(.medium))
                    if t.mode.aUnItineraire, let ca = a.coordonnee, let cb = b.coordonnee {
                        Text("·").font(.caption)
                        ResumeItineraire(a: ca, b: cb, mode: t.mode, dureeModifiee: t.dureeModifiee, google: t.itineraireGoogle(ca, cb))
                    } else if let resume = t.resume(depuis: a, vers: b) {
                        Text("· \(resume)").font(.caption)
                    }
                } else {
                    Image(systemName: "arrow.triangle.swap").font(.caption).frame(width: 24)
                    Text("Ajouter un transport").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Crée une copie de l'étape, juste après elle dans son jour (dans la même nuit pour un hébergement).
    private func dupliquer() {
        guard let contexte = etape.modelContext else { return }
        let copie = etape.copie(dans: contexte)
        if let onDupliquer {
            onDupliquer(copie)
        } else {
            withAnimation { copieFaite = true }
            Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { copieFaite = false } }
        }
    }

    /// Valide un lieu proposé : l'étape reprend titre, adresse, position, notes, et on rapatrie les photos.
    private func valider(_ lieu: LieuPropose) {
        etape.appliquer(lieu)
        let urls = Array(lieu.photos.prefix(6))
        guard !urls.isEmpty else { return }
        photosEnCours = true
        Task { @MainActor in
            let images = await PhotosLieu.telecharger(urls)
            rangerPhotos(images, de: lieu)
            photosEnCours = false
        }
    }

    @MainActor private func rangerPhotos(_ images: [PhotosLieu.Image], de lieu: LieuPropose) {
        guard let contexte = etape.modelContext, let voyage = etape.voyage else { return }
        for ancienne in etape.photosDuLieu where ancienne.nom.hasPrefix("\(lieu.nom) – photo") { contexte.delete(ancienne) }
        for (i, image) in images.enumerated() {
            let photo = Document(nom: "\(lieu.nom) – photo \(i + 1)", extensionFichier: image.extensionFichier, donnees: image.donnees)
            photo.voyage = voyage
            photo.etape = etape
            contexte.insert(photo)
        }
    }

    private var infosDuLieu: some View {
        CadreSection("Infos du lieu", symbole: "info.circle", couleur: .teal) {
            if !etape.photosDuLieu.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(etape.photosDuLieu.sorted { $0.nom < $1.nom }) { photo in
                            ImageDonnees(donnees: photo.donnees)
                                .frame(width: 220, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .contextMenu {
                                    Button("Supprimer la photo", systemImage: "trash", role: .destructive) { etape.modelContext?.delete(photo) }
                                }
                        }
                    }
                }
            } else if let url = etape.photoURL.flatMap(URL.init) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            NotesView(google: etape.noteGoogle.flatMap { n in etape.avisGoogle.map { (n, $0) } },
                      tripadvisor: etape.noteTripadvisor.flatMap { n in etape.avisTripadvisor.map { (n, $0) } })
            if let resume = etape.resume { Text(resume).font(.callout) }
            if let horaires = etape.horaires {
                DisclosureGroup("Horaires") { Text(horaires).font(.footnote) }
            }
            if let url = etape.siteWeb.flatMap(URL.init) { Link("Site web", destination: url) }
            if let url = etape.lienGoogle.flatMap(URL.init) { Link("Voir sur Google", destination: url) }
            if let url = etape.lienTripadvisor.flatMap(URL.init) { Link("Voir sur Tripadvisor", destination: url) }
            Link("Chercher des vidéos", destination: Etape.lienVideos(pour: etape.titre.isEmpty ? etape.lieu : etape.titre))
            if photosEnCours {
                Label("Téléchargement des photos…", systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Une section de la fiche : un cadre teinté et bordé de sa couleur, avec son titre et son icône.
private struct CadreSection<Contenu: View, Accessoire: View>: View {
    let titre: String
    let symbole: String
    let couleur: Color
    @ViewBuilder let contenu: Contenu
    /// Placé à côté du titre (par exemple un bouton « + »).
    @ViewBuilder let accessoire: Accessoire

    init(_ titre: String, symbole: String, couleur: Color, @ViewBuilder contenu: () -> Contenu) where Accessoire == EmptyView {
        self.init(titre, symbole: symbole, couleur: couleur, accessoire: { EmptyView() }, contenu: contenu)
    }

    init(_ titre: String, symbole: String, couleur: Color, @ViewBuilder accessoire: () -> Accessoire, @ViewBuilder contenu: () -> Contenu) {
        self.titre = titre
        self.symbole = symbole
        self.couleur = couleur
        self.accessoire = accessoire()
        self.contenu = contenu()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(titre, systemImage: symbole)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(couleur)
                accessoire
            }
            contenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Fond de carte surélevé puis teinte de la section : chaque partie ressort, même en mode sombre.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FondDePage.carte)
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(couleur.opacity(0.16))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(couleur.opacity(0.75), lineWidth: 1.5))
    }
}

/// iPad : fenêtre plus large pour loger la fiche et le panneau d'idées côte à côte.
private struct TailleDePage: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}


/// Bulle d'heure : vide tant qu'on n'a rien choisi.
/// iPhone, iPad : un toucher ouvre une roue, rien n'est enregistré avant « OK ».
/// Mac : un clic met l'heure proposée dans un champ où l'on tape heures et minutes au clavier (pas d'horloge à aiguilles).
struct BulleHeure: View {
    @Binding var valeur: Date?
    let jour: Date
    let heureDeDepart: Int
    @State private var ouvert = false
    @State private var brouillon = Date()

    private var heureProposee: Date {
        Calendar.current.date(bySettingHour: heureDeDepart, minute: 0, second: 0, of: jour) ?? jour
    }

    var body: some View {
        if let date = valeur {
            DatePicker("", selection: Binding(get: { date }, set: { valeur = $0 }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                #if os(macOS)
                .datePickerStyle(.field)
                #endif
        } else {
            Button {
                #if os(macOS)
                valeur = heureProposee
                #else
                brouillon = heureProposee
                ouvert = true
                #endif
            } label: {
                Text("--:--")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .popover(isPresented: $ouvert) {
                VStack(spacing: 8) {
                    DatePicker("", selection: $brouillon, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                    Button("OK") { valeur = brouillon; ouvert = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
            #endif
        }
    }
}

/// Ouvre Plans avec l'itinéraire depuis la position actuelle jusqu'à l'étape, avec le transport prévu pour y arriver.
struct BoutonYAller: View {
    let etape: Etape
    var taille: CGFloat = 50

    /// Le transport prévu pour arriver à l'étape : celui de l'étape précédente, ou l'aller pour la toute première.
    private var modeDeTransport: ModeTransport? {
        guard let voyage = etape.voyage else { return nil }
        if let depart = voyage.precedente(de: etape) {
            // Un hébergement que le transport de la dernière étape ne vise pas (la nuit en a plusieurs) : pas de mode connu.
            return etape.apresJour && voyage.suivante(de: depart) !== etape ? nil : depart.transport?.mode
        }
        return voyage.elementsDuVoyage.first === etape ? voyage.transportAller?.mode : nil
    }

    var body: some View {
        if let coord = etape.coordonnee {
            Button { yAller(coord) } label: {
                VStack(spacing: 4) {
                    Image(systemName: modeDeTransport?.symbole ?? "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: taille * 0.4, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: taille, height: taille)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    Text("Y aller").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Itinéraire jusqu'à l'étape dans Plans")
            .help("Ouvre Plans avec l'itinéraire depuis ta position actuelle")
        }
    }

    private func yAller(_ coord: CLLocationCoordinate2D) {
        let cible = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        cible.name = etape.titre.isEmpty ? nil : etape.titre
        let mode: String
        switch modeDeTransport {
        case .pied: mode = MKLaunchOptionsDirectionsModeWalking
        case .velo: mode = MKLaunchOptionsDirectionsModeCycling
        case .commun: mode = MKLaunchOptionsDirectionsModeTransit
        case .voiture: mode = MKLaunchOptionsDirectionsModeDriving
        default: mode = MKLaunchOptionsDirectionsModeDefault
        }
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), cible], launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}
