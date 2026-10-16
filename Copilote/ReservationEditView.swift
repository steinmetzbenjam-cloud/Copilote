import SwiftUI
import SwiftData

struct ReservationEditView: View {
    @Bindable var reservation: Reservation
    var voyage: Voyage
    var onSupprimer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @FocusState private var titreActif: Bool
    @State private var suppressionDemandee = false
    /// Hébergements remplacés en reportant la réservation sur ses nuits : une alerte les signale avant de fermer.
    @State private var remplacements: String?

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
                } header: {
                    EnTeteColore(reservation.type.libelle, symbole: reservation.type.symbole, couleur: reservation.type.couleur)
                }
                .teinte(reservation.type.couleur)

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
                } header: {
                    EnTeteColore("Dates et lieu", symbole: "calendar", couleur: .blue)
                }
                .teinte(.blue)

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
                    EnTeteColore("Lien Internet", symbole: "safari", couleur: .orange)
                } footer: {
                    Text("Colle le lien de la réservation (celui du courriel de confirmation de Booking.com, par exemple) : un bouton l'ouvre depuis la fiche de l'étape liée. Sur iPhone et iPad, l'app du site s'ouvre si elle est installée.")
                }
                .teinte(.orange)

                sectionBudget

                sectionLien

                sectionVisibilite

                DocumentsSection(voyage: voyage, reservation: reservation, titre: "Billets et justificatifs", couleur: .teal)

                Section {
                    TextEditor(text: $reservation.notes)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70)
                } header: {
                    EnTeteColore("Notes", symbole: "note.text", couleur: .yellow)
                }
                .teinte(.yellow)

                Section {
                    Button(reservation.ajouteeAItineraire ? "Déjà dans l'itinéraire" : "Ajouter à l'itinéraire",
                           systemImage: "calendar.badge.plus", action: ajouterALItineraire)
                        .disabled(reservation.ajouteeAItineraire)
                    Button("Supprimer la réservation", role: .destructive) { suppressionDemandee = true }
                        .confirmerSuppression($suppressionDemandee, titre: "Supprimer cette réservation ?") {
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
                ToolbarItem(placement: .confirmationAction) { Button("OK", action: valider) }
            }
            .onAppear { if reservation.titre.isEmpty { titreActif = true } }
            .onChange(of: reservation.lien) { _, nouveau in reprendre(nouveau) }
            // Réservation validée (OK ou fiche fermée) : un hébergement de plusieurs nuits est reporté sur chacune.
            .onDisappear {
                guard !reservation.isDeleted, reservation.modelContext != nil, !voyage.lectureSeule else { return }
                voyage.reporterHebergement(de: reservation, dans: contexte)
            }
            // Si le report doit remplacer un autre hébergement, on passe par « OK » pour voir l'alerte.
            .interactiveDismissDisabled(!voyage.lectureSeule && !(voyage.reportHebergement(de: reservation)?.remplaces.isEmpty ?? true))
            .alert("Hébergements remplacés", isPresented: Binding(get: { remplacements != nil }, set: { if !$0 { remplacements = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                Text(remplacements ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 620)
        #endif
    }

    private var moi: String { MoiVoyage.lire(voyage) }

    /// « OK » : reporte un hébergement de plusieurs nuits sur chacune, et prévient si d'autres hébergements ont dû céder leur place.
    private func valider() {
        guard !voyage.lectureSeule, let report = voyage.reporterHebergement(de: reservation, dans: contexte),
              !report.remplaces.isEmpty else { dismiss(); return }
        let nom = report.hebergement.titre.isEmpty ? "L'hébergement réservé" : "« \(report.hebergement.titre) »"
        let lignes = report.remplaces.map { r in
            let titre = r.etape.titre.isEmpty ? r.etape.categorie.libelle : r.etape.titre
            return "• « \(titre) », nuit du \(r.nuit.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
        }
        remplacements = "\(nom) occupe maintenant toutes les nuits de la réservation. Ces hébergements sont passés dans « Étapes à placer » :\n"
            + lignes.joined(separator: "\n")
    }

    /// Le prix par personne (adulte, étudiant, adolescent, enfant), comme dans la fiche d'une étape ; sinon un prix total.
    private var sectionBudget: some View {
        Section {
            LignesPrix(voyage: voyage,
                       adulte: $reservation.prixAdulte, adulteMonnaie: $reservation.monnaieAdulte,
                       etudiant: $reservation.prixEtudiant, etudiantMonnaie: $reservation.monnaieEtudiant,
                       adolescent: $reservation.prixAdolescent, adolescentMonnaie: $reservation.monnaieAdolescent,
                       enfant: $reservation.prixEnfant, enfantMonnaie: $reservation.monnaieEnfant)
            if reservation.aDesPrixParPersonne {
                let nombre = voyage.concernes(par: reservation).count
                LabeledContent(nombre > 1 ? "Total pour \(nombre) voyageurs" : "Total") {
                    Text(voyage.montant(de: reservation).map { Monnaies.formater($0.montant, $0.devise) } ?? "—")
                        .monospacedDigit()
                }
            } else {
                // Le montant, puis juste le code de la monnaie (sans libellé) : un menu propose les monnaies du voyage.
                HStack {
                    Text("Ou prix total")
                    TextField("Montant", text: prixTexte)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("", selection: $reservation.devise) {
                        ForEach(devisesProposees, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        } header: {
            EnTeteColore("Budget", symbole: "eurosign.circle", couleur: .green)
        } footer: {
            Text(reservation.aDesPrixParPersonne
                 ? "Chaque voyageur qui peut voir la réservation compte le prix de son tarif (sans prix étudiant, le prix adulte ; sans prix adolescent, le prix enfant). Efface les prix par personne pour saisir un prix total."
                 : "Saisis le prix par personne, ou un prix total partagé à parts égales entre les voyageurs qui peuvent voir la réservation.")
            + Text(" Liée à une étape, un hébergement ou un transport, la réservation remplace son prix prévu dans le Budget.")
        }
        .teinte(.green)
    }

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
            EnTeteColore("Qui peut la voir", symbole: "person.2", couleur: .pink)
        } footer: {
            Text(reservation.estRestreinte
                 ? "Les voyageurs non cochés ne voient ni la réservation, ni son bouton dans les fiches. Elle reste enregistrée dans le voyage partagé : c'est un affichage, pas un coffre-fort."
                 : "Décoche « Tout le monde » pour réserver cette réservation à certains voyageurs.")
        }
        .teinte(.pink)
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
            EnTeteColore("Lien avec le voyage", symbole: "link", couleur: .purple)
        } footer: {
            Text("La fiche de l'étape, de l'hébergement ou du transport choisi affiche alors un bouton pour ouvrir cette réservation.")
        }
        .teinte(.purple)
    }

    /// En liant la réservation, elle reprend le type et les dates de l'élément lié ; le nom, le lieu et la compagnie
    /// seulement s'ils sont encore vides (ce qui a déjà été saisi n'est pas écrasé).
    private func reprendre(_ cle: String?) {
        guard let cle, let infos = voyage.infos(deLaCible: cle) else { return }
        reservation.type = infos.type
        // Un séjour de plusieurs nuits qui comprend la nuit liée garde ses dates : les autres nuits y seront reportées.
        let cal = Calendar.current
        let sejourDejaSaisi = infos.type == .hebergement && reservation.fin.map { fin in
            cal.startOfDay(for: reservation.debut) <= cal.startOfDay(for: infos.debut)
                && cal.startOfDay(for: fin) >= cal.startOfDay(for: infos.fin ?? infos.debut)
                && cal.startOfDay(for: fin) > cal.startOfDay(for: reservation.debut)
        } == true
        if !sejourDejaSaisi {
            reservation.debut = infos.debut
            reservation.fin = infos.fin
        }
        if reservation.titre.trimmingCharacters(in: .whitespaces).isEmpty { reservation.titre = infos.titre }
        if reservation.lieu.trimmingCharacters(in: .whitespaces).isEmpty { reservation.lieu = infos.lieu }
        if reservation.fournisseur.isEmpty { reservation.fournisseur = infos.fournisseur }
    }

    /// Les monnaies du voyage (euro, locale, troisième), plus celle déjà choisie si elle n'en fait pas partie.
    private var devisesProposees: [String] {
        var codes = voyage.codesMonnaies
        if !reservation.devise.isEmpty, !codes.contains(reservation.devise) { codes.append(reservation.devise) }
        return codes
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
        etape.voyage = voyage
        contexte.insert(etape)
        // Un hébergement va dans la nuit de l'arrivée (les nuits suivantes sont reportées en fermant la fiche).
        if reservation.type == .hebergement, voyage.hebergements(apres: reservation.debut).isEmpty {
            voyage.placerEntreJours(etape, apres: reservation.debut)
        } else {
            etape.ordre = voyage.prochainOrdre(du: reservation.debut)
        }
        reservation.ajouteeAItineraire = true
        if reservation.lien == nil { reservation.lien = LienReservation.etape(etape) }
    }
}
