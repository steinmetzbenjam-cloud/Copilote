import SwiftUI
import SwiftData

struct ReservationEditView: View {
    @Bindable var reservation: Reservation
    var voyage: Voyage
    var onSupprimer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @FocusState private var titreActif: Bool

    private var finActivee: Binding<Bool> {
        Binding(get: { reservation.fin != nil },
                set: { reservation.fin = $0 ? max(reservation.debut, reservation.fin ?? reservation.debut).addingTimeInterval(3600) : nil })
    }

    private var finChoisie: Binding<Date> {
        Binding(get: { reservation.fin ?? reservation.debut }, set: { reservation.fin = $0 })
    }

    private var prixTexte: Binding<String> {
        Binding(get: { reservation.prix.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "" },
                set: { reservation.prix = Double($0.replacingOccurrences(of: ",", with: ".")) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $reservation.type) {
                        ForEach(TypeReservation.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                    }
                    TextField(placeholderTitre, text: $reservation.titre).focused($titreActif)
                    TextField("Compagnie, hôtel, loueur…", text: $reservation.fournisseur)
                    HStack {
                        TextField("N° de confirmation", text: $reservation.numeroConfirmation)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                        if !reservation.numeroConfirmation.isEmpty {
                            Button("Copier", systemImage: "doc.on.doc") { copier(reservation.numeroConfirmation) }
                                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    DatePicker(reservation.type == .hebergement ? "Arrivée" : "Début", selection: $reservation.debut)
                    Toggle(reservation.type == .hebergement ? "Départ" : "Fin", isOn: finActivee)
                    if reservation.fin != nil {
                        DatePicker("Jusqu'au", selection: finChoisie, in: reservation.debut...)
                    }
                    TextField("Lieu ou adresse", text: $reservation.lieu)
                }

                Section("Prix") {
                    HStack {
                        TextField("Montant", text: prixTexte)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("Devise", text: $reservation.devise)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                DocumentsSection(voyage: voyage, reservation: reservation, titre: "Billets et justificatifs")

                Section("Notes") {
                    TextEditor(text: $reservation.notes).frame(minHeight: 70)
                }

                Section {
                    Button(reservation.ajouteeAItineraire ? "Déjà dans l'itinéraire" : "Ajouter à l'itinéraire",
                           systemImage: "calendar.badge.plus", action: ajouterALItineraire)
                        .disabled(reservation.ajouteeAItineraire)
                    Button("Supprimer la réservation", role: .destructive) {
                        onSupprimer()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Réservation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .onAppear { if reservation.titre.isEmpty { titreActif = true } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    private var placeholderTitre: String {
        switch reservation.type {
        case .vol: "Vol Paris → San José"
        case .hebergement: "Nom de l'hébergement"
        case .voiture: "Voiture, modèle"
        case .train: "Trajet"
        case .restaurant: "Nom du restaurant"
        default: "Titre"
        }
    }

    private func copier(_ texte: String) {
        #if os(iOS)
        UIPasteboard.general.string = texte
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
        #endif
    }

    /// Crée l'étape correspondante dans l'itinéraire, à la date et à l'heure de la réservation.
    private func ajouterALItineraire() {
        let etape = Etape(titre: reservation.titre, jour: reservation.debut, categorie: reservation.type.categorieEtape)
        etape.lieu = reservation.lieu
        etape.heure = reservation.debut
        if !reservation.numeroConfirmation.isEmpty {
            etape.notes = "Confirmation : \(reservation.numeroConfirmation)"
        }
        etape.voyage = voyage
        contexte.insert(etape)
        reservation.ajouteeAItineraire = true
    }
}
