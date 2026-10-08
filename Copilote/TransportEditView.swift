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
    /// Reçoit le transport enregistré, ou nil quand on le supprime.
    let enregistrer: (Transport?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var transport: Transport

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
                .onChange(of: transport.mode) { _, _ in transport.sousType = "" }

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

    private func horaires() -> some View {
        LabeledContent("Horaires") {
            HStack {
                BulleHeure(valeur: $transport.depart, jour: jour, heureDeDepart: 9)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                BulleHeure(valeur: $transport.arrivee, jour: jour, heureDeDepart: 10)
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
        }
    }

    /// Distance et durée de l'itinéraire le plus court, si les deux étapes sont localisées.
    @ViewBuilder private var infoItineraire: some View {
        if let (a, b) = coordonnees {
            LigneItineraire(a: a, b: b, mode: transport.mode)
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
    @State private var itineraires = Itineraires.shared

    var body: some View {
        LabeledContent("Itinéraire le plus court") {
            Text(itineraires.trajet(a, b, mode)?.resume ?? "Calcul…").foregroundStyle(.secondary)
        }
        .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
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
    var descriptif: String {
        let t = self
        var morceaux = [t.mode.libelle]
        if t.mode == .commun, !t.sousType.isEmpty { morceaux = [t.sousType] }
        let ligne = [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " ")
        if !ligne.isEmpty { morceaux.append(ligne) }
        if let d = t.depart {
            morceaux.append(d.formatted(date: .omitted, time: .shortened) + (t.arrivee.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
        }
        return morceaux.joined(separator: " · ")
    }
}
