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
                        TextField("N° de réservation", text: $reservation.numeroConfirmation)
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
                    // L'heure saisie est l'heure locale du lieu ; on indique un autre fuseau s'il le faut (vol : heure de départ de Paris…).
                    LigneFuseau(titre: reservation.type == .hebergement ? "Fuseau de l'arrivée" : "Fuseau du début",
                                choisi: $reservation.fuseauDebutId, parDefaut: reservation.voyage?.fuseauParDefaut ?? .current)
                    Toggle(reservation.type == .hebergement ? "Départ" : "Fin", isOn: finActivee)
                    if reservation.fin != nil {
                        DatePicker("Jusqu'au", selection: finChoisie, in: reservation.debut...)
                        LigneFuseau(titre: reservation.type == .hebergement ? "Fuseau du départ" : "Fuseau de la fin",
                                    choisi: $reservation.fuseauFinId,
                                    parDefaut: reservation.fuseauDebutId.flatMap(TimeZone.init(identifier:)) ?? reservation.voyage?.fuseauParDefaut ?? .current)
                    }
                    TextField("Lieu ou adresse", text: $reservation.lieu)
                }

                Section {
                    HStack {
                        TextField("Lien Internet (réservation en ligne, site…)", text: siteWeb)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        if let url = reservation.urlSite {
                            Link(destination: url) {
                                if reservation.estBooking { LogoBooking(taille: 22) } else { Image(systemName: "safari") }
                            }
                                .help("Ouvrir dans le navigateur")
                        }
                    }
                    if reservation.siteWeb == nil, reservation.type == .hebergement {
                        Button("Mes réservations Booking.com", systemImage: "link") {
                            reservation.siteWeb = "https://secure.booking.com/myreservations.html"
                        }
                    }
                } header: {
                    Text("Lien Internet")
                } footer: {
                    Text("Colle le lien de la réservation (celui du courriel de confirmation de Booking.com, par exemple) : un bouton l'ouvre depuis la fiche de l'étape liée. Sur iPhone et iPad, l'app du site s'ouvre si elle est installée.")
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

                sectionLien

                sectionVisibilite

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
            .disabled(reservation.voyage?.lectureSeule ?? false)
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

    private var moi: String { MoiVoyage.lire(voyage) }

    /// Qui voit la réservation : tout le monde, ou seulement certains voyageurs (moi toujours compris).
    private var sectionVisibilite: some View {
        let membres = voyage.membresTries
        let pourTous = Binding<Bool>(
            get: { !reservation.estRestreinte },
            set: { tous in reservation.visiblePour = tous ? nil : membres.map(\.uid) })
        return Section {
            Toggle("Tout le monde", isOn: pourTous)
            if reservation.estRestreinte {
                ForEach(membres) { m in
                    let estMoi = m.uid == moi
                    Toggle(isOn: Binding(
                        get: { reservation.visiblePour?.contains(m.uid) ?? false || estMoi },
                        set: { coche in
                            var liste = reservation.visiblePour ?? []
                            liste.removeAll { $0 == m.uid }
                            if coche { liste.append(m.uid) }
                            if !moi.isEmpty, !liste.contains(moi) { liste.append(moi) }
                            reservation.visiblePour = liste
                        })) {
                        Text(estMoi ? "\(m.nom) (moi)" : m.nom) + Text(m.famille.isEmpty ? "" : " · \(m.famille)").foregroundColor(.secondary)
                    }
                    .disabled(estMoi)
                }
            }
        } header: {
            Text("Qui peut la voir")
        } footer: {
            Text(reservation.estRestreinte
                 ? "Les voyageurs non cochés ne voient ni la réservation, ni son bouton dans les fiches. Elle reste enregistrée dans le voyage partagé : c'est un affichage, pas un coffre-fort."
                 : "Décoche « Tout le monde » pour réserver cette réservation à certains voyageurs.")
        }
    }

    /// Les groupes proposés, dans l'ordre qui convient au type de réservation (un hôtel cherche d'abord parmi les hébergements…).
    private var groupes: [CibleReservation.Groupe] {
        switch reservation.type {
        case .hebergement: [.hebergements, .etapes, .transports]
        case .vol, .train, .voiture: [.transports, .etapes, .hebergements]
        default: [.etapes, .hebergements, .transports]
        }
    }

    /// Lier la réservation à une étape, un hébergement ou un transport : un bouton l'ouvre ensuite depuis leur fiche.
    private var sectionLien: some View {
        let cibles = voyage.ciblesReservation
        return Section {
            Picker("Lier à", selection: $reservation.lien) {
                Text("Rien").tag(String?.none)
                if let lien = reservation.lien, !cibles.contains(where: { $0.cle == lien }) {
                    Text("Élément supprimé").tag(String?.some(lien))
                }
                ForEach(groupes, id: \.self) { groupe in
                    let liste = cibles.filter { $0.groupe == groupe }
                    if !liste.isEmpty {
                        Section(groupe.rawValue) {
                            ForEach(liste) { c in Label(c.libelle, systemImage: c.symbole).tag(String?.some(c.cle)) }
                        }
                    }
                }
            }
        } header: {
            Text("Lien")
        } footer: {
            Text("La fiche de l'étape, de l'hébergement ou du transport choisi affiche alors un bouton pour ouvrir cette réservation.")
        }
    }

    private var siteWeb: Binding<String> {
        Binding(get: { reservation.siteWeb ?? "" },
                set: { reservation.siteWeb = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
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
            etape.notes = "Réservation : \(reservation.numeroConfirmation)"
        }
        etape.ordre = voyage.prochainOrdre(du: reservation.debut)
        etape.voyage = voyage
        contexte.insert(etape)
        reservation.ajouteeAItineraire = true
        if reservation.lien == nil { reservation.lien = LienReservation.etape(etape) }
    }
}
