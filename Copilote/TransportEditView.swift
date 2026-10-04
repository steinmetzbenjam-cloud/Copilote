import SwiftUI

/// Fenêtre du transport entre une étape et la suivante : un onglet par mode, avec les champs qui conviennent.
struct TransportEditView: View {
    let depart: Etape
    let arrivee: Etape
    @Environment(\.dismiss) private var dismiss
    @State private var transport: Transport

    init(depart: Etape, arrivee: Etape) {
        self.depart = depart
        self.arrivee = arrivee
        _transport = State(initialValue: depart.transport ?? Transport())
    }

    private var jour: Date { depart.jour ?? .now }

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
                    Text("\(titre(depart)) → \(titre(arrivee))")
                }
                .onChange(of: transport.mode) { _, _ in transport.sousType = "" }

                switch transport.mode {
                case .avion: avion
                case .voiture: voiture
                case .pied: pied
                case .velo: velo
                case .commun: commun
                }

                Section("Notes") {
                    TextEditor(text: $transport.notes).frame(minHeight: 60)
                }
                if depart.transport != nil {
                    Section {
                        Button("Supprimer le transport", role: .destructive) {
                            depart.transport = nil
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { depart.transport = transport; dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func titre(_ e: Etape) -> String { e.titre.isEmpty ? "Étape" : e.titre }

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
        if let a = depart.coordonnee, let b = arrivee.coordonnee {
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
