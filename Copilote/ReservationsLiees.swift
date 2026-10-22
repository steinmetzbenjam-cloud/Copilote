import SwiftUI
import SwiftData

/// Ce à quoi une réservation peut être liée : une étape, un hébergement ou un transport (vol, train…).
/// Le lien est gardé dans la réservation sous forme de clé : « etape:UID », « transport:UID » (le transport qui part de l'étape UID),
/// « aller » ou « retour ».
enum LienReservation {
    static func etape(_ e: Etape) -> String { "etape:\(e.uid)" }
    static func transport(depart e: Etape) -> String { "transport:\(e.uid)" }
    static let aller = "aller"
    static let retour = "retour"
}

extension TypeReservation {
    /// Une couleur par type de réservation, reprise dans la liste et dans la fiche.
    var couleur: Color {
        switch self {
        case .vol: .blue
        case .train: .teal
        case .hebergement: .indigo
        case .voiture: .orange
        case .activite: .green
        case .restaurant: .red
        case .autre: .gray
        }
    }
}

/// Titre de section en couleur, avec son icône : comme les cadres de la fiche d'une étape.
struct EnTeteColore: View {
    let titre: String
    let symbole: String
    let couleur: Color

    init(_ titre: String, symbole: String, couleur: Color) {
        self.titre = titre
        self.symbole = symbole
        self.couleur = couleur
    }

    var body: some View {
        Label(titre, systemImage: symbole)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(couleur)
            .textCase(nil)
    }
}

extension View {
    /// Fond teinté des lignes d'une section de formulaire (nil : fond ordinaire).
    func teinte(_ couleur: Color?) -> some View {
        listRowBackground(couleur.map { c in
            ZStack {
                FondDePage.carte
                c.opacity(0.16)
            }
        })
    }
}

/// Une cible proposée dans le choix « Lier à » d'une réservation.
struct CibleReservation: Identifiable, Hashable {
    enum Groupe: String, CaseIterable { case hebergements = "Hébergements", transports = "Vols et transports", etapes = "Étapes" }
    let cle: String
    let libelle: String
    let symbole: String
    let groupe: Groupe
    var id: String { cle }
}

extension Voyage {
    /// Les réservations que le voyageur de cet appareil peut voir.
    var reservationsVisibles: [Reservation] {
        let moi = MoiVoyage.lire(self)
        return reservations.filter { $0.visible(pour: moi) }
    }

    /// Les réservations liées à une étape, un hébergement ou un transport (parmi celles que je peux voir).
    /// Pour un hébergement, ce sont aussi celles d'un séjour de plusieurs nuits dont il fait partie : elles sont liées à chacune de ses nuits.
    func reservations(lieesA cle: String) -> [Reservation] {
        let etape = cle.hasPrefix("etape:") ? etapes.first { LienReservation.etape($0) == cle } : nil
        return reservationsVisibles.filter { r in
            r.lien == cle || (etape != nil && sejour(de: etape!)?.reservation === r)
        }.sorted { $0.debut < $1.debut }
    }

    /// Une nuit d'un séjour réservé : le jour qu'elle suit, et l'hébergement qui l'occupe (nil : pas encore reporté sur cette nuit).
    struct NuitDeSejour: Identifiable {
        let nuit: Date
        let numeroDeJour: Int?
        let etape: Etape?
        var id: Date { nuit }
    }

    /// Chaque nuit d'une réservation d'hébergement de plusieurs nuits, avec l'hébergement qui l'occupe : le même hôtel,
    /// listé nuit par nuit (jour 1, jour 2, jour 3…). Vide pour une seule nuit ou une réservation qui n'est pas liée à un hébergement.
    func nuitsDeSejour(de r: Reservation) -> [NuitDeSejour] {
        let cal = Calendar.current
        let nuits = self.nuits(de: r)
        guard nuits.count > 1, let cle = r.lien, let h = etapes.first(where: { LienReservation.etape($0) == cle }),
              h.categorie == .hebergement else { return [] }
        func meme(_ e: Etape) -> Bool {
            e === h || (e.titre.caseInsensitiveCompare(h.titre) == .orderedSame && e.lieu.caseInsensitiveCompare(h.lieu) == .orderedSame)
        }
        return nuits.map { nuit in
            NuitDeSejour(nuit: nuit,
                         numeroDeJour: jours.firstIndex { cal.isDate($0, inSameDayAs: nuit) }.map { $0 + 1 },
                         etape: hebergements(apres: nuit).first(where: meme))
        }
    }

    private func prefixeJour(_ e: Etape) -> String {
        guard let jour = e.jour, let i = jours.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: jour) }) else { return "" }
        return "Jour \(i + 1) · "
    }

    private func nom(_ e: Etape) -> String { e.titre.isEmpty ? e.categorie.libelle : e.titre }

    /// Tout ce à quoi une réservation peut être liée, dans l'ordre du voyage.
    var ciblesReservation: [CibleReservation] {
        var cibles: [CibleReservation] = []
        if let t = transportAller {
            cibles.append(CibleReservation(cle: LienReservation.aller, libelle: "Aller · \(t.descriptif(avecHoraires: false))", symbole: t.mode.symbole, groupe: .transports))
        }
        for e in elementsDuVoyage {
            if e.categorie == .hebergement {
                cibles.append(CibleReservation(cle: LienReservation.etape(e), libelle: prefixeJour(e) + nom(e), symbole: "bed.double.fill", groupe: .hebergements))
            } else {
                cibles.append(CibleReservation(cle: LienReservation.etape(e), libelle: prefixeJour(e) + nom(e), symbole: e.categorie.symbole, groupe: .etapes))
            }
            if let t = e.transport {
                let vers = suivante(de: e).map { " → \(nom($0))" } ?? ""
                cibles.append(CibleReservation(cle: LienReservation.transport(depart: e), libelle: prefixeJour(e) + "\(t.descriptif(avecHoraires: false)) · \(nom(e))\(vers)",
                                               symbole: t.mode.symbole, groupe: .transports))
            }
        }
        if let t = transportRetour {
            cibles.append(CibleReservation(cle: LienReservation.retour, libelle: "Retour · \(t.descriptif(avecHoraires: false))", symbole: t.mode.symbole, groupe: .transports))
        }
        return cibles
    }
}

extension Reservation {
    /// L'adresse Internet saisie, complétée par « https:// » si besoin.
    var urlSite: URL? {
        guard var texte = siteWeb?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty else { return nil }
        if !texte.contains("://") { texte = "https://" + texte }
        return URL(string: texte)
    }

    /// Réservée à certains voyageurs (les autres ne la voient pas dans l'app).
    var estRestreinte: Bool { !(visiblePour ?? []).isEmpty }

    /// Visible pour ce voyageur. Tant que l'appareil ne sait pas qui l'utilise, tout reste visible.
    func visible(pour moi: String) -> Bool {
        guard let liste = visiblePour, !liste.isEmpty, !moi.isEmpty else { return true }
        return liste.contains(moi)
    }

    /// Vrai si le lien mène à Booking.com.
    var estBooking: Bool {
        guard let hote = urlSite?.host?.lowercased() else { return false }
        return hote == "booking.com" || hote.hasSuffix(".booking.com")
    }
}

/// Le logo de Booking.com : un « B » blanc suivi d'un point bleu clair, sur un carré bleu foncé.
struct LogoBooking: View {
    var taille: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: taille * 0.22, style: .continuous)
                .fill(Color(rouge: 0x00, vert: 0x35, bleu: 0x80))
            HStack(alignment: .lastTextBaseline, spacing: taille * 0.02) {
                Text("B").font(.system(size: taille * 0.62, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Circle().fill(Color(rouge: 0x00, vert: 0x9F, bleu: 0xE3)).frame(width: taille * 0.17, height: taille * 0.17)
                    .offset(y: -taille * 0.04)
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityLabel("Booking.com")
    }
}

extension Voyage {
    /// Ce que l'élément lié apprend à la réservation : son nom, le type de réservation qui lui correspond, ses dates et son lieu.
    struct InfosCible {
        var titre: String
        var type: TypeReservation
        var debut: Date
        var fin: Date?
        var lieu: String
        var fournisseur: String = ""
    }

    /// Le jour et l'heure réunis (l'heure par défaut si aucune n'est saisie).
    private func moment(_ jour: Date, _ heure: Date?, defaut: Int) -> Date {
        let cal = Calendar.current
        let h = heure.map { cal.dateComponents([.hour, .minute], from: $0) } ?? DateComponents(hour: defaut, minute: 0)
        return cal.date(bySettingHour: h.hour ?? defaut, minute: h.minute ?? 0, second: 0, of: cal.startOfDay(for: jour)) ?? jour
    }

    func infos(deLaCible cle: String) -> InfosCible? {
        let cal = Calendar.current
        func transport(_ t: Transport, jour: Date, de: String, vers: String) -> InfosCible {
            let type: TypeReservation = switch t.mode {
            case .avion: .vol
            case .voiture: .voiture
            case .commun: .train
            case .pied, .velo: .autre
            }
            let debut = moment(jour, t.depart, defaut: 9)
            var fin = t.arrivee.map { moment(jour, $0, defaut: 9) }
            if let f = fin, f < debut { fin = cal.date(byAdding: .day, value: 1, to: f) }
            let depart = t.de.isEmpty ? (t.departLieu ?? de) : t.de
            let arrivee = t.vers.isEmpty ? (t.arriveeLieu ?? vers) : t.vers
            let trajet = [depart, arrivee].filter { !$0.isEmpty }.joined(separator: " → ")
            let titre = type == .vol ? "Vol \(trajet)" : (trajet.isEmpty ? t.mode.libelle : "\(t.mode == .commun && !t.sousType.isEmpty ? t.sousType : t.mode.libelle) \(trajet)")
            return InfosCible(titre: titre, type: type, debut: debut, fin: fin, lieu: depart, fournisseur: [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " "))
        }
        func nom(_ e: Etape) -> String { e.titre.isEmpty ? e.categorie.libelle : e.titre }

        if cle == LienReservation.aller, let t = transportAller, let jour = jours.first {
            return transport(t, jour: jour, de: "", vers: elementsDuVoyage.first.map(nom) ?? "")
        }
        if cle == LienReservation.retour, let t = transportRetour, let jour = jours.last {
            return transport(t, jour: jour, de: elementsDuVoyage.last.map(nom) ?? "", vers: "")
        }
        if cle.hasPrefix("transport:"), let e = etapes.first(where: { LienReservation.transport(depart: $0) == cle }),
           let t = e.transport, let jour = e.jour {
            // Un transport qui part d'un hébergement a lieu le lendemain matin.
            let jourTransport = e.apresJour ? (cal.date(byAdding: .day, value: 1, to: jour) ?? jour) : jour
            return transport(t, jour: jourTransport, de: nom(e), vers: suivante(de: e).map(nom) ?? "")
        }
        if cle.hasPrefix("etape:"), let e = etapes.first(where: { LienReservation.etape($0) == cle }) {
            let jour = e.jour ?? debut
            if e.categorie == .hebergement {
                // Une nuit : arrivée le soir (15 h par défaut), départ le lendemain matin (11 h par défaut).
                let lendemain = cal.date(byAdding: .day, value: 1, to: jour) ?? jour
                return InfosCible(titre: nom(e), type: .hebergement, debut: moment(jour, e.heure, defaut: 15),
                                  fin: moment(lendemain, e.heureFin, defaut: 11), lieu: e.lieu)
            }
            let type: TypeReservation = switch e.categorie {
            case .repas: .restaurant
            case .visite, .musee, .nature, .activite: .activite
            case .transport: .train
            case .hebergement: .hebergement
            case .autre: .autre
            }
            return InfosCible(titre: nom(e), type: type, debut: moment(jour, e.heure, defaut: 10),
                              fin: e.heureFin.map { moment(jour, $0, defaut: 10) }, lieu: e.lieu)
        }
        return nil
    }
}

extension Voyage {
    /// Les réservations liées à cet élément qui ont un prix : dans le Budget, elles remplacent le prix prévu.
    func reservationsChiffrees(lieesA cle: String) -> [Reservation] {
        reservations.filter { $0.lien == cle && ($0.prix != nil || $0.aDesPrixParPersonne) }.sorted { $0.debut < $1.debut }
    }

    /// Ce que le report d'un hébergement réservé ferait : les nuits où le copier, et les hébergements qu'il y remplacerait.
    struct ReportHebergement {
        let hebergement: Etape
        let nuits: [Date]
        let remplaces: [(nuit: Date, etape: Etape)]
    }

    /// Les nuits d'une réservation d'hébergement qui tombent dans le voyage (chaque nuit est désignée par le jour qui la précède).
    /// Vide si ce n'est pas un hébergement ou s'il n'y a pas de date de départ.
    func nuits(de r: Reservation) -> [Date] {
        guard r.type == .hebergement, let fin = r.fin else { return [] }
        let cal = Calendar.current
        let arrivee = cal.startOfDay(for: r.debut), depart = cal.startOfDay(for: fin)
        return jours.filter { arrivee <= $0 && $0 < depart }
    }

    /// Le séjour (réservation de plusieurs nuits) dont fait partie cet hébergement : la réservation liée à l'une de ses nuits,
    /// pour le même hébergement (même nom et même adresse), et dont les nuits comprennent celle-ci.
    func sejour(de etape: Etape) -> (reservation: Reservation, nuits: [Date])? {
        guard etape.categorie == .hebergement, etape.apresJour, let nuit = etape.jour else { return nil }
        let cal = Calendar.current
        func meme(_ e: Etape) -> Bool {
            e === etape || (e.titre.caseInsensitiveCompare(etape.titre) == .orderedSame && e.lieu.caseInsensitiveCompare(etape.lieu) == .orderedSame)
        }
        for r in reservations.sorted(by: { $0.debut < $1.debut }) {
            let n = nuits(de: r)
            guard n.count > 1, n.contains(where: { cal.isDate($0, inSameDayAs: nuit) }),
                  let cle = r.lien, let liee = etapes.first(where: { LienReservation.etape($0) == cle }), meme(liee) else { continue }
            return (r, n)
        }
        return nil
    }

    /// Une réservation d'hébergement de plusieurs nuits, liée à l'une d'elles : les autres nuits de la réservation (dans le voyage)
    /// où cet hébergement n'est pas déjà. Celles qu'occupe un autre hébergement sont comptées dans `remplaces`.
    func reportHebergement(de r: Reservation) -> ReportHebergement? {
        let cal = Calendar.current
        guard let cle = r.lien, let fin = r.fin,
              let h = etapes.first(where: { LienReservation.etape($0) == cle }),
              h.categorie == .hebergement, h.apresJour, let nuitLiee = h.jour else { return nil }
        let arrivee = cal.startOfDay(for: r.debut), depart = cal.startOfDay(for: fin)
        // La nuit liée doit faire partie de la réservation.
        guard arrivee <= nuitLiee, nuitLiee < depart else { return nil }
        func meme(_ e: Etape) -> Bool {
            e.titre.caseInsensitiveCompare(h.titre) == .orderedSame && e.lieu.caseInsensitiveCompare(h.lieu) == .orderedSame
        }
        var nuits: [Date] = []
        var remplaces: [(nuit: Date, etape: Etape)] = []
        for jour in jours where arrivee <= jour && jour < depart && !cal.isDate(jour, inSameDayAs: nuitLiee) {
            let occupants = hebergements(apres: jour)
            if occupants.contains(where: meme) { continue }
            nuits.append(jour)
            remplaces += occupants.map { (jour, $0) }
        }
        return nuits.isEmpty ? nil : ReportHebergement(hebergement: h, nuits: nuits, remplaces: remplaces)
    }

    /// Reporte l'hébergement réservé sur ses autres nuits ; l'hébergement qui occupait l'une d'elles passe dans « Étapes à placer ».
    /// Le prix de la réservation couvre tout le séjour : les copies ne reprennent alors pas le prix prévu, pour ne pas le compter deux fois.
    @discardableResult
    func reporterHebergement(de r: Reservation, dans contexte: ModelContext) -> ReportHebergement? {
        guard let report = reportHebergement(de: r) else { return nil }
        let paye = r.prix != nil || r.aDesPrixParPersonne
        for jour in report.nuits {
            let copie = report.hebergement.copieHebergement(nuit: jour, dans: contexte)
            if paye {
                copie.prixAdulte = nil; copie.prixEtudiant = nil; copie.prixAdolescent = nil; copie.prixEnfant = nil
            }
        }
        return report
    }

    /// Ce que coûte une réservation : avec des prix par personne, la somme (en euros) du prix de chaque voyageur concerné
    /// selon son tarif (sans prix étudiant, le prix adulte ; sans prix adolescent, le prix enfant) ; sinon son prix total, dans sa monnaie.
    func montant(de r: Reservation) -> (montant: Double, devise: String)? {
        guard r.aDesPrixParPersonne else { return r.prix.map { ($0, r.devise) } }
        func euros(_ prix: Double?, _ monnaie: MonnaiePrix) -> Double? { prix.flatMap { versEuros($0, depuis: monnaie) } }
        let adulte = euros(r.prixAdulte, r.monnaieAdulte)
        let parTarif: [Tarif: Double?] = [.adulte: adulte, .etudiant: euros(r.prixEtudiant, r.monnaieEtudiant) ?? adulte,
                                          .adolescent: euros(r.prixAdolescent, r.monnaieAdolescent) ?? euros(r.prixEnfant, r.monnaieEnfant),
                                          .enfant: euros(r.prixEnfant, r.monnaieEnfant)]
        let concernes = concernes(par: r)
        let total = membres.filter { concernes.contains($0.uid) }.reduce(0.0) { $0 + ((parTarif[$1.tarif] ?? nil) ?? 0) }
        return (total, "EUR")
    }

    /// Les voyageurs concernés par une réservation : ceux qui la voient, ou tout le monde.
    func concernes(par r: Reservation) -> Set<String> {
        r.estRestreinte ? Set(r.visiblePour ?? []) : Set(membres.map(\.uid))
    }

    /// Les voyageurs dont le coût vient d'une réservation (et non plus du prix prévu), et si c'est le cas de tous.
    func couvertsParReservations(_ cle: String) -> (couverts: Set<String>, tous: Bool) {
        let couverts = reservationsChiffrees(lieesA: cle).reduce(into: Set<String>()) { $0.formUnion(concernes(par: $1)) }
        return (couverts, !membres.isEmpty && Set(membres.map(\.uid)).isSubset(of: couverts))
    }
}

/// Le prix prévu, grisé quand des réservations liées donnent le prix réel, avec un rappel de ces réservations.
struct PrixPrevuOuReserve<Contenu: View>: View {
    var voyage: Voyage?
    var cle: String?
    @ViewBuilder var contenu: () -> Contenu

    var body: some View {
        if let voyage, let cle, !voyage.reservationsChiffrees(lieesA: cle).isEmpty {
            let couverture = voyage.couvertsParReservations(cle)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(voyage.reservationsChiffrees(lieesA: cle)) { r in
                    let pour = couverture.tous && !r.estRestreinte ? "" :
                        " pour " + voyage.membresTries.filter { voyage.concernes(par: r).contains($0.uid) }.map(\.nom).joined(separator: ", ")
                    Label("Réservation « \(r.titre.isEmpty ? r.type.libelle : r.titre) » : \(voyage.montant(de: r).map { Monnaies.formater($0.montant, $0.devise) } ?? "—")\(pour)",
                          systemImage: "ticket.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.indigo)
                }
                Text(couverture.tous
                     ? "Le Budget compte le prix de la réservation : le prix prévu ci-dessous n'est plus utilisé."
                     : "Le Budget compte le prix de la réservation pour ces voyageurs ; le prix prévu ci-dessous reste utilisé pour les autres.")
                    .font(.footnote).foregroundStyle(.secondary)
                contenu()
                    .disabled(couverture.tous)
                    .opacity(couverture.tous ? 0.4 : 1)
            }
        } else {
            contenu()
        }
    }
}

/// Dans la fiche d'une étape, d'un hébergement ou d'un transport : un bouton par réservation liée, qui en ouvre le détail.
struct BoutonsReservations: View {
    var voyage: Voyage
    var cle: String
    @Environment(\.modelContext) private var contexte
    @State private var ouverte: Reservation?

    var body: some View {
        ForEach(voyage.reservations(lieesA: cle)) { r in
            HStack(spacing: 10) {
                Button { ouverte = r } label: {
                    HStack(spacing: 10) {
                        Image(systemName: r.type.symbole).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.titre.isEmpty ? r.type.libelle : r.titre).font(.subheadline.weight(.semibold))
                            Text([r.fournisseur, r.numeroConfirmation.isEmpty ? "" : "N° \(r.numeroConfirmation)"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            // Plusieurs réservations pour un même élément : on voit pour qui est chacune.
                            if r.estRestreinte {
                                Label(voyage.membresTries.filter { r.visiblePour?.contains($0.uid) ?? false }.map(\.nom).joined(separator: ", "),
                                      systemImage: "person.2.fill")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if !r.documents.isEmpty { Label("\(r.documents.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                // Le lien Internet de la réservation (Booking.com, la compagnie…), ouvert dans le navigateur ou l'app du site.
                if let url = r.urlSite {
                    Link(destination: url) {
                        Group {
                            if r.estBooking {
                                HStack(spacing: 6) {
                                    LogoBooking(taille: 18)
                                    Text("Booking.com")
                                }
                            } else {
                                Label("Ouvrir", systemImage: "safari")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help(url.absoluteString)
                }
            }
        }
        .sheet(item: $ouverte) { r in
            ReservationEditView(reservation: r, voyage: voyage) { contexte.delete(r) }
        }
    }
}
