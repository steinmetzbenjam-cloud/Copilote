import SwiftUI
import SwiftData
import MapKit

/// Tableau de bord du voyage : compte à rebours, programme du jour, météo, rappels, état de la synchronisation et résumé à partager.
struct ApercuView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @Query private var tousLesVoyages: [Voyage]
    private var reseau = Reseau.shared
    private var cloud = PartageCloud.shared
    private var meteo = Meteo.shared

    @State private var lieu: CLLocationCoordinate2D?
    @State private var rappelsActifs = Rappels.actifs
    @State private var rappelsProgrammes = 0
    @State private var autorisationRefusee = false
    @State private var fichiers: (pdf: URL, image: URL)?
    @State private var enPreparation = false
    /// Étape touchée dans le programme du jour : son détail s'ouvre.
    @State private var etapeOuverte: Etape?
    @State private var extremiteOuverte: TimingView.ExtremiteTransport?

    init(voyage: Voyage) { self.voyage = voyage }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                compteARebours
                // La météo n'a de sens qu'en voyage ; le résumé, qu'en souvenir.
                if voyage.mode == .souvenir { cadreResume }
                if voyage.mode != .souvenir { cadreProgramme }
                if voyage.mode == .voyage { cadreMeteo }
                cadreRappels
                cadreSynchro
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
        .sheet(item: $etapeOuverte) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
        .sheet(item: $extremiteOuverte) { FicheExtremite(voyage: voyage, extremite: $0) }
        .task {
            guard voyage.mode == .voyage else { return }
            lieu = await voyage.lieuMeteo()
            if let lieu { await meteo.actualiser(lieu) }
        }
        .task(id: voyage.mode) {
            guard voyage.mode == .voyage, lieu == nil else { return }
            lieu = await voyage.lieuMeteo()
            if let lieu { await meteo.actualiser(lieu) }
        }
        .task { rappelsProgrammes = await Rappels.nombreProgramme() }
        // Prévisions des jours à venir, à l'endroit de chaque jour : le fond du programme suit leurs mises à jour.
        .task(id: voyage.cleMeteo) {
            guard voyage.mode != .souvenir, !voyage.joursPrevisibles.isEmpty else { return }
            if lieu == nil { lieu = await voyage.lieuMeteo() }
            await meteo.chargerJours(de: voyage, lieuVoyage: lieu)
        }
    }

    // MARK: Compte à rebours

    private var compteARebours: some View {
        let mode = voyage.mode
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(voyage.pays.compactMap { Pays.avec(code: $0)?.drapeau }.joined(separator: " ")).font(.title2)
                Spacer()
                Label(mode.nom, systemImage: mode.symbole).font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.22), in: Capsule())
            }
            switch voyage.etat {
            case .avant(let jours):
                Text(jours == 0 ? "Départ demain" : "J-\(jours)").font(.system(size: 54, weight: .heavy, design: .rounded))
                Text("Départ le \(voyage.debut.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
            case .pendant(let jour, let sur):
                Text("Jour \(jour) sur \(sur)").font(.system(size: 44, weight: .heavy, design: .rounded))
                ProgressView(value: Double(jour), total: Double(sur)).tint(.white)
                Text("Retour le \(voyage.fin.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
            case .apres(let jours):
                Text("Voyage terminé").font(.system(size: 38, weight: .heavy, design: .rounded))
                Text(jours == 0 ? "Retour aujourd'hui" : "Il y a \(jours) jour\(jours > 1 ? "s" : "")")
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [mode.couleur, mode.couleur.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .shadow(color: mode.couleur.opacity(0.35), radius: 8, y: 3)
    }

    // MARK: Programme du jour

    @ViewBuilder private var cadreProgramme: some View {
        if let (jour, aujourdhui) = voyage.jourEnAvant {
            let elements = voyage.etapes(du: jour) + voyage.hebergements(apres: jour)
            let prochaine = aujourdhui ? elements.first { ($0.dateHeure ?? .distantPast) > .now } : nil
            // Le temps prévu là où l'on est ce jour-là : la carte en prend l'aspect.
            let temps = meteo.prevision(jour, de: voyage, lieuVoyage: lieu) ?? meteoDuJour(jour)
            CadreInfos(titre: aujourdhui ? "Aujourd'hui" : "Premier jour", symbole: "sun.horizon.fill", couleur: .orange, meteo: temps) {
                if let temps { ligneMeteo(temps) }
                // Le vol d'aller le premier jour, celui du retour le dernier, avec terminal, porte et tapis à jour.
                let cal = Calendar.current
                let premier = voyage.jours.first.map { cal.isDate($0, inSameDayAs: jour) } ?? false
                let dernier = voyage.jours.last.map { cal.isDate($0, inSameDayAs: jour) } ?? false
                if premier, voyage.transportAller != nil {
                    PaveExtremite(voyage: voyage, extremite: .aller) { extremiteOuverte = .aller }
                }
                if elements.isEmpty {
                    Text("Rien de prévu ce jour-là pour l'instant.").foregroundStyle(.secondary)
                }
                // Le matin : le trajet depuis l'hôtel de la veille (ou la dernière étape de la veille) vers la première étape.
                if let (depart, arrivee) = trajetDuMatin(jour), let t = depart.transport {
                    ligneTransport(t, depuis: depart, vers: arrivee, jour: jour)
                }
                ForEach(elements) { etape in
                    ligne(etape, estProchaine: etape === prochaine)
                    // Le transport vers l'élément suivant, entre les deux ; en fin de journée, vers celui du lendemain.
                    if let t = etape.transport, let vers = destination(de: etape, jour: jour) {
                        ligneTransport(t, depuis: etape, vers: vers, jour: jour)
                    }
                }
                if dernier, voyage.transportRetour != nil {
                    PaveExtremite(voyage: voyage, extremite: .retour) { extremiteOuverte = .retour }
                }
            }
        }
    }

    /// L'élément vers lequel part le transport d'une étape : la suivante du jour, l'hébergement, ou la première étape du lendemain.
    private func destination(de etape: Etape, jour: Date) -> Etape? {
        if let suivante = voyage.suivante(de: etape) { return suivante }
        if let nuit = voyage.transportDeNuit(apres: jour), nuit.depart === etape { return nuit.arrivee }
        return nil
    }

    /// Le trajet qui ouvre la journée : depuis l'hôtel de la veille, ou depuis la dernière étape de la veille sans hôtel.
    private func trajetDuMatin(_ jour: Date) -> (Etape, Etape)? {
        guard let veille = Calendar.current.date(byAdding: .day, value: -1, to: jour), let premiere = voyage.etapes(du: jour).first else { return nil }
        if let h = voyage.hebergements(apres: veille).first, h.transport != nil, voyage.suivante(de: h) === premiere { return (h, premiere) }
        if let nuit = voyage.transportDeNuit(apres: veille), nuit.arrivee === premiere { return (nuit.depart, nuit.arrivee) }
        return nil
    }

    /// Un transport entre deux éléments du programme : son mode, vers où il mène (et quel jour, s'il change de jour),
    /// sa distance et son temps de trajet.
    private func ligneTransport(_ t: Transport, depuis depart: Etape, vers arrivee: Etape, jour: Date) -> some View {
        let cal = Calendar.current
        let nom: (Etape) -> String = { $0.titre.isEmpty ? $0.categorie.libelle : $0.titre }
        let jourArrivee = arrivee.apresJour ? nil : arrivee.jour
        let autreJour = jourArrivee.map { !cal.isDate($0, inSameDayAs: jour) } ?? false
        let quand = jourArrivee.map { j -> String in
            if let demain = cal.date(byAdding: .day, value: 1, to: jour), cal.isDate(j, inSameDayAs: demain) { return "demain" }
            return j.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        let depuisVeille = depart.jour.map { !cal.isDate($0, inSameDayAs: jour) } ?? false
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: t.mode.symbole).font(.footnote.weight(.semibold)).foregroundStyle(.indigo)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if depuisVeille {
                        Text("\(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt) depuis \(nom(depart)) → \(nom(arrivee))")
                    } else {
                        Text("\(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelleCourt) → \(nom(arrivee))")
                            + Text(autreJour ? " (\(quand ?? "le lendemain"))" : "").foregroundColor(.orange)
                    }
                }
                .font(.footnote.weight(.medium)).foregroundStyle(.indigo)
                // Distance et temps seulement s'ils sont connus ; sinon, le mode suffit.
                if t.mode.aUnItineraire, let a = depart.coordonnee, let b = arrivee.coordonnee {
                    ResumeItineraire(a: a, b: b, mode: t.mode, dureeModifiee: t.dureeModifiee, google: t.itineraireGoogle(a, b), masquerSiVide: true)
                } else if let resume = t.resume(depuis: depart, vers: arrivee) {
                    Text(resume).font(.caption).foregroundStyle(.secondary)
                }
                // Ce qui a été saisi en plus du mode : compagnie, numéro, horaires.
                let details = [[t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " "),
                               t.depart.map { d in d.formatted(date: .omitted, time: .shortened) + (t.arrivee.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? "") } ?? ""]
                    .filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.leading, 20)
    }

    private func ligne(_ etape: Etape, estProchaine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: etape.categorie.symbole).foregroundStyle(.white).frame(width: 32, height: 32)
                    .background(Circle().fill(estProchaine ? Color.orange : Color.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(etape.titre.isEmpty ? etape.categorie.libelle : etape.titre).fontWeight(.semibold)
                    if !etape.lieu.isEmpty { Text(etape.lieu).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if estProchaine { Text("Prochaine").font(.caption2.bold()).foregroundStyle(.orange) }
                if let h = etape.heure { Text(h.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(.secondary) }
                // Sur chaque étape placée sur la carte : l'itinéraire dans Plans depuis la position actuelle.
                BoutonYAller(etape: etape, taille: 40)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(estProchaine ? Color.orange.opacity(0.14) : .clear))
        // Toucher la ligne ouvre le détail de l'étape (le bouton « Y aller » garde son propre geste).
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { etapeOuverte = etape }
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Météo

    private var previsions: [MeteoJour] { lieu.map { meteo.jours(pour: $0) } ?? [] }

    private func meteoDuJour(_ jour: Date) -> MeteoJour? {
        previsions.first { Calendar.current.isDate($0.date, inSameDayAs: jour) }
    }

    private func ligneMeteo(_ m: MeteoJour) -> some View {
        HStack(spacing: 10) {
            Image(systemName: m.symbole).symbolRenderingMode(.multicolor).font(.title2)
            Text("\(m.libelle) · \(Int(m.tMin.rounded()))° / \(Int(m.tMax.rounded()))°")
            if let p = m.pluie, p >= 20 { Label("\(p) %", systemImage: "drop.fill").font(.footnote).foregroundStyle(.blue) }
        }
        .font(.subheadline)
    }

    private var cadreMeteo: some View {
        let jours = voyage.jours
        let utiles = jours.compactMap { j in meteoDuJour(j).map { (j, $0) } }
        return CadreInfos(titre: "Météo à destination", symbole: "cloud.sun.fill", couleur: .cyan) {
            if lieu == nil {
                Text("Choisis un pays ou place des étapes sur la carte pour voir la météo.").foregroundStyle(.secondary)
            } else if utiles.isEmpty {
                Text(previsions.isEmpty ? "Prévisions indisponibles pour l'instant (connexion requise)." : "Les prévisions couvrent 16 jours : elles apparaîtront ici à l'approche du départ.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(utiles, id: \.0) { jour, m in
                            VStack(spacing: 4) {
                                Text(jour.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                                Image(systemName: m.symbole).symbolRenderingMode(.multicolor).font(.title2)
                                Text("\(Int(m.tMax.rounded()))°").fontWeight(.semibold)
                                Text("\(Int(m.tMin.rounded()))°").font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(width: 62).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(m.couleur.opacity(0.14)))
                        }
                    }
                }
                if let lieu, let date = meteo.misAJour[Meteo.cle(lieu)] {
                    Text("Mis à jour \(date.formatted(.relative(presentation: .named)))\(reseau.enLigne ? "" : " · hors ligne")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Résumé à partager

    private var cadreResume: some View {
        CadreInfos(titre: "Résumé du voyage", symbole: "doc.richtext.fill", couleur: .pink,
                   pied: "Budget, familles, comptes et jour par jour, prêts à envoyer à tout le groupe.") {
            HStack(spacing: 12) {
                Button(enPreparation ? "Création…" : (fichiers == nil ? "Créer le résumé" : "Mettre à jour"), systemImage: "wand.and.stars") {
                    enPreparation = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        fichiers = ExportResume.fichiers(voyage)
                        enPreparation = false
                    }
                }
                .disabled(enPreparation)
                if let fichiers {
                    ShareLink(item: fichiers.pdf) { Label("PDF", systemImage: "square.and.arrow.up") }
                    ShareLink(item: fichiers.image) { Label("Image", systemImage: "photo") }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Rappels

    private var cadreRappels: some View {
        CadreInfos(titre: "Rappels", symbole: "bell.badge.fill", couleur: .red,
                   pied: "Veille et jour du départ, étapes (30 minutes avant), vols (3 h avant), autres transports (45 minutes avant), et dépenses déclarées par les autres voyageurs. Tout reste sur l'appareil.") {
            Toggle("Activer les rappels", isOn: Binding(get: { rappelsActifs }, set: { changerRappels($0) }))
            if rappelsActifs {
                Text(rappelsProgrammes == 0 ? "Aucun rappel programmé pour l'instant." : "\(rappelsProgrammes) rappel\(rappelsProgrammes > 1 ? "s" : "") programmé\(rappelsProgrammes > 1 ? "s" : "").")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if autorisationRefusee {
                Label("Les notifications sont refusées : autorise-les dans les réglages du système.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func changerRappels(_ actif: Bool) {
        rappelsActifs = actif
        Rappels.actifs = actif
        autorisationRefusee = false
        Task {
            if actif, !(await Rappels.autorise()) {
                if !(await Rappels.autoriser()) { autorisationRefusee = true }
            }
            await Rappels.planifier(tousLesVoyages)
            rappelsProgrammes = await Rappels.nombreProgramme()
        }
    }

    // MARK: Synchronisation et hors-ligne

    private var cadreSynchro: some View {
        let etat = etatSynchro
        return CadreInfos(titre: "Synchronisation", symbole: etat.symbole, couleur: etat.couleur,
                          pied: "Les voyages, étapes, dépenses, budgets et documents sont enregistrés sur l'appareil : ils s'ouvrent sans connexion. La carte, la recherche de lieux, la météo et les taux de change demandent le réseau.") {
            Label(etat.titre, systemImage: etat.symbole).foregroundStyle(etat.couleur).font(.headline)
            if let detail = etat.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private var etatSynchro: (titre: String, detail: String?, symbole: String, couleur: Color) {
        if !reseau.enLigne {
            let attente = cloud.actif && cloud.enAttente > 0 ? " \(cloud.enAttente) modification\(cloud.enAttente > 1 ? "s" : "") attend\(cloud.enAttente > 1 ? "ent" : "") le retour du réseau." : ""
            return ("Hors ligne", "Tu peux continuer à travailler : tout est gardé sur l'appareil.\(attente)", "wifi.slash", .orange)
        }
        if !PartageCloud.disponible || !cloud.actif {
            return ("Sur cet appareil seulement", "La synchronisation iCloud n'est pas activée : ce voyage n'est pas envoyé aux autres appareils ni au groupe.", "internaldrive", .gray)
        }
        if cloud.synchroEnCours || cloud.enAttente > 0 {
            return ("Synchronisation en cours…", cloud.enAttente > 0 ? "\(cloud.enAttente) modification\(cloud.enAttente > 1 ? "s" : "") à envoyer." : nil, "arrow.triangle.2.circlepath.icloud", .blue)
        }
        let quand = cloud.derniereSynchro.map { "Dernier échange \($0.formatted(.relative(presentation: .named)))." }
        return ("Synchronisé", quand ?? cloud.statut, "checkmark.icloud.fill", .green)
    }
}
