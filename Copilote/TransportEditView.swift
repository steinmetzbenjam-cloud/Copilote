import SwiftUI
import CoreLocation

/// Fenêtre du transport entre une étape et la suivante : un onglet par mode, avec les champs qui conviennent.
struct TransportEditView: View {
    /// « Étape → Étape », « Départ → Étape »…
    let trajet: String
    let jour: Date
    /// Les deux extrémités, quand elles sont localisées (pour l'itinéraire le plus court).
    let coordonnees: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
    let existant: Transport?
    /// Pour l'aller et le retour : on choisit un lieu de départ et un lieu d'arrivée.
    var lieuxExtremites = false
    /// Le voyage, pour convertir les prix saisis en monnaie locale.
    var voyageDuTransport: Voyage?
    /// Les étapes de départ et d'arrivée (pour connaître les fuseaux horaires de leurs lieux).
    var etapeDepart: Etape?
    var etapeArrivee: Etape?
    /// Reçoit le transport enregistré, ou nil quand on le supprime.
    let enregistrer: (Transport?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var transport: Transport
    @State private var planOuvert = false
    @State private var rechercheEnCours = false
    @State private var erreurRecherche: String?

    private enum ChoixLieu: String, Identifiable {
        case depart, arrivee
        var id: String { rawValue }
    }
    @State private var rechercheLieu: ChoixLieu?

    init(trajet: String, jour: Date, coordonnees: (CLLocationCoordinate2D, CLLocationCoordinate2D)?,
         existant: Transport?, lieuxExtremites: Bool = false, voyage: Voyage? = nil, enregistrer: @escaping (Transport?) -> Void) {
        self.lieuxExtremites = lieuxExtremites
        self.voyageDuTransport = voyage
        self.trajet = trajet
        self.jour = jour
        self.coordonnees = coordonnees
        self.existant = existant
        self.enregistrer = enregistrer
        _transport = State(initialValue: existant ?? Transport())
    }

    /// Transport entre deux étapes : il est gardé sur l'étape de départ.
    init(depart: Etape, arrivee: Etape) {
        let titre: (Etape) -> String = { $0.titre.isEmpty ? "Étape" : $0.titre }
        self.init(trajet: "\(titre(depart)) → \(titre(arrivee))", jour: depart.jour ?? .now,
                  coordonnees: depart.coordonnee.flatMap { a in arrivee.coordonnee.map { (a, $0) } },
                  existant: depart.transport, voyage: depart.voyage, enregistrer: { depart.transport = $0 })
        self.etapeDepart = depart
        self.etapeArrivee = arrivee
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $transport.mode) {
                        ForEach(ModeTransport.allCases) { m in
                            Label(m.libelleCourt, systemImage: m.symbole).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    Text(trajet)
                }
                .onChange(of: transport.mode) { _, _ in transport.sousType = ""; transport.dureeModifiee = nil }

                if lieuxExtremites {
                    Section {
                        ligneLieu("Lieu de départ", transport.departLieu, .depart)
                        ligneLieu("Lieu d'arrivée", transport.arriveeLieu, .arrivee)
                    } footer: {
                        Text("Le trait de la carte relie ces deux lieux ; elle ne s'élargit pas pour les montrer en entier.")
                    }
                }

                switch transport.mode {
                case .avion: avion
                case .voiture: voiture
                case .pied: pied
                case .velo: velo
                case .commun: commun
                }

                SectionBudgetTransport(voyage: voyageDuTransport, transport: $transport)

                Section("Notes") {
                    TextEditor(text: $transport.notes).frame(minHeight: 60)
                }
                if existant != nil {
                    Section {
                        Button("Supprimer le transport", role: .destructive) {
                            enregistrer(nil)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(voyageDuTransport?.lectureSeule ?? false)
            .navigationTitle("Transport")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(item: $rechercheLieu) { choix in
                RechercheLieuView(requeteInitiale: (choix == .depart ? transport.departLieu : transport.arriveeLieu) ?? "",
                                  invite: "Ville, aéroport, gare, adresse…") { trouve in
                    let nom = trouve.adresse.isEmpty ? trouve.nom : "\(trouve.nom), \(trouve.adresse)"
                    if choix == .depart {
                        transport.departLieu = nom
                        transport.departLatitude = trouve.coordonnee.latitude
                        transport.departLongitude = trouve.coordonnee.longitude
                    } else {
                        transport.arriveeLieu = nom
                        transport.arriveeLatitude = trouve.coordonnee.latitude
                        transport.arriveeLongitude = trouve.coordonnee.longitude
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { enregistrer(transport); dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// Une ligne « Lieu de départ / d'arrivée » : toucher ouvre la recherche ; un bouton permet de retirer le lieu.
    private func ligneLieu(_ titre: String, _ valeur: String?, _ choix: ChoixLieu) -> some View {
        HStack {
            Button { rechercheLieu = choix } label: {
                LabeledContent(titre) {
                    Text(valeur ?? "Choisir un lieu").foregroundStyle(valeur == nil ? .secondary : .primary)
                        .multilineTextAlignment(.trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if valeur != nil {
                Button("Retirer", systemImage: "xmark.circle.fill") {
                    if choix == .depart { transport.departLieu = nil; transport.departLatitude = nil; transport.departLongitude = nil }
                    else { transport.arriveeLieu = nil; transport.arriveeLatitude = nil; transport.arriveeLongitude = nil }
                }
                .labelStyle(.iconOnly).foregroundStyle(.secondary).buttonStyle(.plain)
            }
        }
    }

    private func choix(_ m: ModeTransport) -> some View {
        Picker(m.titreSousType, selection: $transport.sousType) {
            Text("—").tag("")
            ForEach(m.sousTypes, id: \.self) { Text($0).tag($0) }
        }
    }

    private func champ(_ titre: String, _ texte: Binding<String>) -> some View {
        LabeledContent(titre) {
            TextField(titre, text: texte).multilineTextAlignment(.trailing)
        }
    }

    /// Les fuseaux par défaut (ceux des deux lieux) et les fuseaux en vigueur (avec les choix faits à la main).
    private var fuseauxParDefaut: (depart: TimeZone, arrivee: TimeZone) {
        let base = voyageDuTransport?.fuseauxParDefaut(de: transport, depuis: etapeDepart, vers: etapeArrivee)
        let a = coordonnees?.0, b = coordonnees?.1
        let cache = FuseauxHoraires.shared
        let d = transport.departCoordonnee.flatMap(cache.fuseau) ?? a.flatMap(cache.fuseau) ?? base?.depart ?? .current
        return (d, transport.arriveeCoordonnee.flatMap(cache.fuseau) ?? b.flatMap(cache.fuseau) ?? base?.arrivee ?? d)
    }

    private var fuseauxEffectifs: (depart: TimeZone, arrivee: TimeZone) {
        let ref = fuseauxParDefaut
        return (transport.fuseauDepart.flatMap(TimeZone.init(identifier:)) ?? ref.depart,
                transport.fuseauArrivee.flatMap(TimeZone.init(identifier:)) ?? ref.arrivee)
    }

    @ViewBuilder private func horaires() -> some View {
        LabeledContent("Horaires") {
            HStack {
                BulleHeure(valeur: $transport.depart, jour: jour, heureDeDepart: 9)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                BulleHeure(valeur: $transport.arrivee, jour: jour, heureDeDepart: 10)
            }
        }
        // Chaque heure est lue dans son fuseau : l'heure locale du départ, et celle de l'arrivée.
        let lieux = [transport.departCoordonnee, transport.arriveeCoordonnee, coordonnees?.0, coordonnees?.1].compactMap { $0 }
        LigneFuseau(titre: "Fuseau du départ", choisi: $transport.fuseauDepart, parDefaut: fuseauxParDefaut.depart, coordonnees: lieux)
        LigneFuseau(titre: "Fuseau de l'arrivée", choisi: $transport.fuseauArrivee, parDefaut: fuseauxParDefaut.arrivee, coordonnees: lieux)
        if transport.depart != nil, transport.arrivee != nil {
            let z = fuseauxEffectifs
            if let duree = Horaires.duree(transport, jour: jour, depart: z.depart, arrivee: z.arrivee) {
                let minutes = Int((duree / 60).rounded())
                LabeledContent("Durée réelle", value: minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min")
                if z.depart.identifier != z.arrivee.identifier {
                    Text("Départ à l'heure de \(z.depart.ville), arrivée à l'heure de \(z.arrivee.ville) : \(z.depart.decalage()) → \(z.arrivee.decalage()).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var avion: some View {
        Section("Vol") {
            champ("Compagnie", $transport.compagnie)
            champ("N° de vol", $transport.numero)
            champ("Aéroport de départ", $transport.de)
            champ("Aéroport d'arrivée", $transport.vers)
            horaires()
            choix(.avion)
        }
    }

    private var voiture: some View {
        Section("Voiture") {
            choix(.voiture)
            if transport.sousType == "Location" { champ("Loueur", $transport.compagnie) }
            infoItineraire
        }
    }

    private var pied: some View {
        Section("À pied") { infoItineraire }
    }

    private var velo: some View {
        Section("Vélo") {
            choix(.velo)
            if transport.sousType == "Location" || transport.sousType == "Libre-service" { champ("Service", $transport.compagnie) }
            infoItineraire
        }
    }

    private var commun: some View {
        Section("Transports en commun") {
            choix(.commun)
            champ("Opérateur", $transport.compagnie)
            champ("Ligne / n°", $transport.numero)
            champ("Station de départ", $transport.de)
            champ("Station d'arrivée", $transport.vers)
            horaires()
            rechercheCommun
        }
    }

    // MARK: Itinéraire en transports en commun

    /// Les lieux entre lesquels chercher : ceux de l'aller ou du retour, sinon ceux des deux étapes.
    private var lieuxDeRecherche: (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        if lieuxExtremites {
            if let a = transport.departCoordonnee, let b = transport.arriveeCoordonnee { return (a, b) }
            return nil
        }
        return coordonnees
    }

    @ViewBuilder private var rechercheCommun: some View {
        if let voyage = voyageDuTransport {
            Button("Plan du métro", systemImage: "map") { planOuvert = true }
                .buttonStyle(.borderless)
                .sheet(isPresented: $planOuvert) { PlanMetroView(voyage: voyage) }
        }
        Button { Task { await chercherCommun() } } label: {
            Label(rechercheEnCours ? "Recherche…" : (transport.itineraireCommun == nil ? "Chercher l'itinéraire" : "Relancer la recherche"),
                  systemImage: "magnifyingglass")
        }
        .disabled(rechercheEnCours || lieuxDeRecherche == nil)
        if lieuxDeRecherche == nil {
            Text(lieuxExtremites ? "Choisis un lieu de départ et un lieu d'arrivée pour chercher l'itinéraire."
                 : "Place les deux étapes sur la carte (lieu) pour chercher l'itinéraire.")
                .font(.footnote).foregroundStyle(.secondary)
        } else if Cles.lire(.google) == nil {
            Text("La recherche utilise Google : ajoute ta clé dans les Réglages et active « Routes API » dans ton projet Google Cloud.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let erreurRecherche {
            Text(erreurRecherche).font(.footnote).foregroundStyle(.red)
            Text("Google ne fournit pas toujours les transports en commun (couverture variable selon les pays). Plans peut au moins estimer la durée, ou ouvrir l'itinéraire dans son app.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let (a, b) = lieuxDeRecherche {
            HStack(spacing: 14) {
                Button("Estimer la durée (Plans)", systemImage: "clock") { Task { await estimerAvecPlans() } }
                    .disabled(rechercheEnCours)
                Button("Ouvrir dans Plans", systemImage: "map") {
                    EstimationPlans.ouvrir(de: a, vers: b, depart: transport.de.isEmpty ? nil : transport.de, arrivee: transport.vers.isEmpty ? nil : transport.vers)
                }
            }
            .buttonStyle(.borderless)
        }
        if let itineraire = transport.itineraireCommun {
            DetailItineraireCommun(itineraire: itineraire)
            Text("Enregistré avec le transport et tracé sur la carte. Calculé \(itineraire.calculeLe.formatted(.relative(presentation: .named))).")
                .font(.footnote).foregroundStyle(.secondary)
            DureeDuTrajet(calculee: Double(itineraire.secondes) / 60, modifiee: $transport.dureeModifiee)
            Button("Retirer l'itinéraire", systemImage: "xmark.circle", role: .destructive) { transport.itineraireCommun = nil; transport.dureeModifiee = nil }
                .buttonStyle(.borderless)
        }
    }

    private func estimerAvecPlans() async {
        guard let (a, b) = lieuxDeRecherche else { return }
        rechercheEnCours = true
        defer { rechercheEnCours = false }
        if let estimation = await EstimationPlans.estimer(de: a, vers: b) {
            transport.itineraireCommun = estimation
            transport.dureeModifiee = nil
            erreurRecherche = nil
        } else {
            erreurRecherche = "Plans n'a pas pu estimer la durée de ce trajet."
        }
    }

    private func chercherCommun() async {
        guard let (a, b) = lieuxDeRecherche else { return }
        rechercheEnCours = true
        erreurRecherche = nil
        defer { rechercheEnCours = false }
        // L'heure de départ prévue, sur le jour du transport, oriente la recherche vers les bons horaires.
        var quand: Date?
        if let d = transport.depart {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            quand = Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: Calendar.current.startOfDay(for: jour))
        }
        do {
            let resultat = try await RoutesGoogle.chercher(de: a, vers: b, sousType: transport.sousType, depart: quand)
            transport.itineraireCommun = resultat
            transport.dureeModifiee = nil
            // Les stations et l'opérateur se remplissent s'ils sont vides.
            let premiere = resultat.etapes.first { !$0.estMarche }, derniere = resultat.etapes.last { !$0.estMarche }
            if transport.de.isEmpty { transport.de = premiere?.depart ?? "" }
            if transport.vers.isEmpty { transport.vers = derniere?.arrivee ?? "" }
            if transport.numero.isEmpty { transport.numero = resultat.lignes }
        } catch {
            erreurRecherche = error.localizedDescription
        }
    }

    /// Distance et durée de l'itinéraire le plus court, si les deux étapes sont localisées.
    @ViewBuilder private var infoItineraire: some View {
        if let (a, b) = coordonnees {
            LigneItineraire(a: a, b: b, mode: transport.mode, dureeModifiee: $transport.dureeModifiee)
        } else {
            Text("Place les deux étapes sur la carte (lieu) pour voir l'itinéraire.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

import CoreLocation

/// Distance et durée du trajet ; l'itinéraire est calculé au moment de l'afficher.
struct LigneItineraire: View {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D
    let mode: ModeTransport
    @Binding var dureeModifiee: Double?
    @State private var itineraires = Itineraires.shared
    @State private var recalcul = false

    var body: some View {
        let trajet = itineraires.trajet(a, b, mode)
        LabeledContent("Itinéraire le plus court") {
            Text(trajet?.resume ?? "Calcul…").foregroundStyle(.secondary)
        }
        .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
        if let duree = trajet?.duree {
            DureeDuTrajet(calculee: duree / 60, modifiee: $dureeModifiee)
        }
        // Un nouveau calcul repart de zéro : la durée corrigée à la main est effacée.
        Button(recalcul ? "Calcul…" : "Recalculer l'itinéraire", systemImage: "arrow.triangle.2.circlepath") {
            recalcul = true
            dureeModifiee = nil
            Task {
                await itineraires.recalculer(a, b, mode)
                recalcul = false
            }
        }
        .buttonStyle(.borderless)
        .disabled(recalcul)
    }
}

/// Durée du trajet, réglable à la minute après le calcul : seule la durée change, le tracé trouvé reste sur la carte.
struct DureeDuTrajet: View {
    /// Durée trouvée par le calcul, en minutes.
    let calculee: Double
    @Binding var modifiee: Double?
    @FocusState private var caseActive: String?

    private var minutesAffichees: Int { Int((modifiee ?? calculee).rounded()) }

    private var heures: Binding<Int?> {
        Binding(get: { minutesAffichees / 60 }, set: { regler(heures: $0 ?? 0, minutes: minutesAffichees % 60) })
    }

    private var minutes: Binding<Int?> {
        Binding(get: { minutesAffichees % 60 }, set: { regler(heures: minutesAffichees / 60, minutes: $0 ?? 0) })
    }

    /// Revenir exactement à la durée calculée efface la correction.
    private func regler(heures: Int, minutes: Int) {
        let total = Double(max(heures, 0) * 60 + max(minutes, 0))
        guard total > 0 else { return }
        modifiee = Int(total) == Int(calculee.rounded()) ? nil : total
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Durée du trajet").lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            caseNombre(heures, unite: "h")
            caseNombre(minutes, unite: "min")
        }
        .onChange(of: caseActive) { _, active in if active != nil { toutSelectionner() } }
        if modifiee != nil {
            HStack {
                Text("Modifiée à la main (calcul : \(CategorieEtape.texteDuree(calculee))).")
                    .font(.footnote).foregroundStyle(.orange)
                Spacer()
                Button("Reprendre le calcul") { modifiee = nil }
                    .font(.footnote).buttonStyle(.borderless)
            }
        }
    }

    private func caseNombre(_ valeur: Binding<Int?>, unite: String) -> some View {
        HStack(spacing: 3) {
            TextField("", value: valeur, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder((modifiee != nil ? Color.orange : .gray).opacity(0.5), lineWidth: 1))
                .foregroundStyle(.black)
                .frame(width: 52)
                .focused($caseActive, equals: unite)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(unite).foregroundStyle(.secondary).font(.callout)
        }
    }

    /// Le contenu de la case est sélectionné : on tape la nouvelle valeur sans effacer l'ancienne.
    private func toutSelectionner() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
        #endif
    }
}

/// Une nuit à renseigner : l'hébergement (déjà créé, vide) ou le transport entre le jour et le suivant.
struct NuitAjout: Identifiable {
    let etape: Etape
    let jour: Date
    var id: String { etape.uid }
}

/// Fenêtre ouverte depuis la bande entre deux jours : deux onglets, Hébergement et Transport.
struct NuitAjoutView: View {
    let voyage: Voyage
    let nuit: NuitAjout
    @State private var onglet = Onglet.hebergement
    @Environment(\.modelContext) private var contexte
    @Environment(\.dismiss) private var dismiss

    private enum Onglet: String, CaseIterable, Identifiable {
        case hebergement = "Hébergement", transport = "Transport"
        var id: String { rawValue }
    }

    /// Transport entre la dernière étape du jour et la première du lendemain.
    private var trajet: (Etape, Etape)? {
        let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: nuit.jour) ?? nuit.jour
        guard let depart = voyage.etapes(du: nuit.jour).last, let arrivee = voyage.etapes(du: lendemain).first else { return nil }
        return (depart, arrivee)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $onglet) {
                ForEach(Onglet.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            switch onglet {
            case .hebergement:
                EtapeEditView(etape: nuit.etape, jours: voyage.jours) { contexte.delete(nuit.etape) }
            case .transport:
                if let (depart, arrivee) = trajet {
                    TransportEditView(depart: depart, arrivee: arrivee)
                } else {
                    NavigationStack {
                        ContentUnavailableView("Pas de transport possible", systemImage: "arrow.triangle.swap",
                                               description: Text("Il faut une étape ce jour-là et une autre le lendemain."))
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}

extension Transport {
    /// « Avion · AF 123 · 10:00 → 12:30 » : le résumé affiché sur les lignes de transport.
    var descriptif: String { descriptif(avecHoraires: true) }

    func descriptif(avecHoraires: Bool) -> String {
        let t = self
        var morceaux = [t.mode.libelle]
        if t.mode == .commun, !t.sousType.isEmpty { morceaux = [t.sousType] }
        let ligne = [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " ")
        if t.mode == .commun, t.depart == nil {
            if let m = t.dureeModifiee { morceaux.append(CategorieEtape.texteDuree(m)) }
            else if let duree = t.itineraireCommun?.resume.split(separator: " · ").first { morceaux.append(String(duree)) }
        }
        if !ligne.isEmpty { morceaux.append(ligne) }
        if avecHoraires, let d = t.depart {
            morceaux.append(d.formatted(date: .omitted, time: .shortened) + (t.arrivee.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
        }
        return morceaux.joined(separator: " · ")
    }
}
