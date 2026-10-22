import Foundation

/// Tarif appliqué à un voyageur : celui des prix « adulte », « étudiant », « adolescent » ou « enfant » saisis sur les étapes et les transports.
enum Tarif: String, CaseIterable, Identifiable {
    case adulte, etudiant, adolescent, enfant

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .adulte: "Adulte"
        case .etudiant: "Étudiant"
        case .adolescent: "Adolescent"
        case .enfant: "Enfant"
        }
    }

    /// Jusqu'à ces âges (compris), le tarif enfant puis le tarif adolescent s'appliquent par défaut. Un âge inconnu donne le tarif adulte.
    static let ageEnfantMax = 11
    static let ageAdolescentMax = 17

    /// L'autre tarif des jeunes : enfant ↔ adolescent (le même pour les autres).
    var autreJeune: Tarif {
        switch self {
        case .enfant: .adolescent
        case .adolescent: .enfant
        default: self
        }
    }

    static func pour(age: Int?) -> Tarif {
        guard let age, age <= ageAdolescentMax else { return .adulte }
        return age <= ageEnfantMax ? .enfant : .adolescent
    }
}

extension Membre {
    /// Le tarif choisi à la main, sinon celui qui découle de l'âge.
    var tarif: Tarif { tarifBrut.flatMap(Tarif.init(rawValue:)) ?? Tarif.pour(age: ageAuVoyage) }

    /// Nom de la famille, sans espaces autour (vide : le voyageur n'est dans aucune famille).
    var famille: String { (familleNom ?? "").trimmingCharacters(in: .whitespaces) }
}

struct GroupeFamille: Identifiable {
    let nom: String
    let membres: [Membre]
    var id: String { nom.lowercased() }
}

extension Voyage {
    var membresTries: [Membre] { membres.sorted { $0.creeLe < $1.creeLe } }

    /// Les familles, dans l'ordre où leur premier membre a été ajouté.
    var familles: [GroupeFamille] {
        let tries = membresTries
        var noms: [String] = []
        for m in tries where !m.famille.isEmpty && !noms.contains(where: { $0.caseInsensitiveCompare(m.famille) == .orderedSame }) {
            noms.append(m.famille)
        }
        return noms.map { nom in
            GroupeFamille(nom: nom, membres: tries.filter { $0.famille.caseInsensitiveCompare(nom) == .orderedSame })
        }
    }

    var membresSansFamille: [Membre] { membresTries.filter { $0.famille.isEmpty } }

    /// La famille d'un voyageur, par exemple pour savoir à qui rattacher un règlement.
    func famille(de uid: String) -> String? {
        membre(uid: uid).flatMap { $0.famille.isEmpty ? nil : $0.famille }
    }
}

/// Un montant prévu au budget : une étape, un hébergement ou un transport, avec son prix pour chaque tarif (en euros).
struct ElementBudget: Identifiable {
    let id = UUID()
    var titre: String
    /// Jour auquel le coût est rattaché : un hébergement compte pour le jour qui précède la nuit.
    var jour: Date
    var poste: CategorieEtape
    var prix: [Tarif: Double]
    /// Voyageurs dont le coût vient d'une réservation liée : le prix prévu ne compte plus pour eux.
    var exclus: Set<String> = []
    /// Enfants et adolescents qui paient ici le prix de l'autre tarif (voir `Tarif.autreJeune`).
    var bascules: Set<String> = []
    /// Prix réel d'une réservation (en euros), partagé à parts égales entre les voyageurs concernés.
    var forfait: Double?
    var concernes: Set<String> = []

    func montant(pour membre: Membre) -> Double {
        if let forfait { return concernes.contains(membre.uid) && !concernes.isEmpty ? forfait / Double(concernes.count) : 0 }
        return exclus.contains(membre.uid) ? 0 : prix[tarif(de: membre)] ?? 0
    }

    func tarif(de membre: Membre) -> Tarif {
        bascules.contains(membre.uid) ? membre.tarif.autreJeune : membre.tarif
    }
}

struct BudgetCalcule {
    var elements: [ElementBudget] = []
    /// Prix saisis dans une autre monnaie que l'euro sans taux de change : ils ne sont pas comptés.
    var tauxManquants = 0
    /// Étapes avec un prix mais sans jour : elles ne sont pas comptées.
    var etapesSansJour = 0
    /// Étapes placées dans un jour mais sans aucun prix.
    var etapesSansPrix = 0
}

extension Voyage {
    /// Tout ce qui est prévu au budget, jour par jour. Le coût d'un hébergement va au jour qui le précède ;
    /// celui du transport qui suit un hébergement va au lendemain ; l'aller et le retour au premier et au dernier jour.
    /// Seules comptent les étapes et les transports de l'itinéraire choisi (`varianteBudget`), et les réservations qui leur sont liées.
    func calculerBudget() -> BudgetCalcule {
        var resultat = BudgetCalcule()
        let jours = self.jours
        guard let premier = jours.first, let dernier = jours.last else { return resultat }
        let cal = Calendar.current

        func euros(_ prix: Double?, _ monnaie: MonnaiePrix) -> Double? {
            guard let prix else { return nil }
            if let converti = versEuros(prix, depuis: monnaie) { return converti }
            resultat.tauxManquants += 1
            return nil
        }
        func prix(_ a: (Double?, MonnaiePrix), _ e: (Double?, MonnaiePrix), _ o: (Double?, MonnaiePrix), _ n: (Double?, MonnaiePrix)) -> [Tarif: Double] {
            var r: [Tarif: Double] = [:]
            if let v = euros(a.0, a.1) { r[.adulte] = v }
            if let v = euros(e.0, e.1) { r[.etudiant] = v }
            if let v = euros(o.0, o.1) { r[.adolescent] = v }
            if let v = euros(n.0, n.1) { r[.enfant] = v }
            // Sans prix étudiant, un étudiant paie le prix adulte ; sans prix adolescent, un adolescent paie le prix enfant.
            if r[.etudiant] == nil, let adulte = r[.adulte] { r[.etudiant] = adulte }
            if r[.adolescent] == nil, let enfant = r[.enfant] { r[.adolescent] = enfant }
            return r
        }
        /// Le prix prévu d'un élément, sauf pour les voyageurs couverts par une réservation liée qui a un prix :
        /// pour eux, c'est le prix réel de la réservation qui compte. Renvoie vrai si un montant a été retenu.
        @discardableResult
        func retenir(_ cle: String, titre: String, jour: Date, poste: CategorieEtape, prevu: [Tarif: Double],
                     nonConcernes: [String]? = nil, bascules: [String]? = nil) -> Bool {
            var couverts = Set<String>()
            var retenu = false
            for r in reservationsChiffrees(lieesA: cle) {
                // Un hébergement de plusieurs nuits : le prix du séjour est réparti à parts égales sur chaque nuit.
                let sejour = nuits(de: r)
                let parts: [(jour: Date, titre: String)] = sejour.count > 1
                    ? sejour.enumerated().map { ($0.element, "\(titre) · réservation, nuit \($0.offset + 1)/\(sejour.count)") }
                    : [(jour, "\(titre) · réservation")]
                let diviseur = Double(parts.count)
                let concernes = self.concernes(par: r)
                // Prix par personne : chaque voyageur concerné paie celui de son tarif.
                if r.aDesPrixParPersonne {
                    let p = prix((r.prixAdulte, r.monnaieAdulte), (r.prixEtudiant, r.monnaieEtudiant), (r.prixAdolescent, r.monnaieAdolescent), (r.prixEnfant, r.monnaieEnfant))
                    for part in parts {
                        resultat.elements.append(ElementBudget(titre: part.titre, jour: part.jour, poste: poste, prix: p.mapValues { $0 / diviseur },
                                                               exclus: Set(membres.map(\.uid)).subtracting(concernes)))
                    }
                    couverts.formUnion(concernes)
                    retenu = true
                    continue
                }
                guard let montant = r.prix else { continue }
                guard let enEuros = versEuros(montant, code: r.devise) else { resultat.tauxManquants += 1; continue }
                for part in parts {
                    resultat.elements.append(ElementBudget(titre: part.titre, jour: part.jour, poste: poste, prix: [:],
                                                           forfait: enEuros / diviseur, concernes: concernes))
                }
                couverts.formUnion(concernes)
                retenu = true
            }
            let tous = Set(membres.map(\.uid))
            if !prevu.isEmpty, !(tous.isSubset(of: couverts) && !tous.isEmpty) {
                resultat.elements.append(ElementBudget(titre: titre, jour: jour, poste: poste, prix: prevu,
                                                       exclus: couverts.union(nonConcernes ?? []), bascules: Set(bascules ?? [])))
                retenu = true
            }
            return retenu
        }

        func ajouter(_ transport: Transport?, cle: String, titre: String, jour: Date) {
            guard let t = transport else { return }
            let p = prix((t.prixAdulte, t.monnaieAdulte), (t.prixEtudiant, t.monnaieEtudiant), (t.prixAdolescent, t.monnaieAdolescent), (t.prixEnfant, t.monnaieEnfant))
            retenir(cle, titre: "\(t.mode.libelleCourt) · \(titre)", jour: jour, poste: .transport, prevu: p, nonConcernes: t.exclusBudget, bascules: t.basculesTarif)
        }

        ajouter(transportAller, cle: LienReservation.aller, titre: "Aller", jour: premier)
        ajouter(transportRetour, cle: LienReservation.retour, titre: "Retour", jour: dernier)

        let parcours = parcoursDuBudget
        // Le transport du départ d'un itinéraire bis vers sa première étape : il remplace celui de l'étape de départ.
        if let v = parcours.variante, parcours.avecTransportDepart, let depart = self.depart(de: v), let jour = depart.jour {
            let lendemain = depart.apresJour ? cal.date(byAdding: .day, value: 1, to: jour).map { min($0, dernier) } : nil
            ajouter(v.transportDepart, cle: LienReservation.variante(v), titre: "\(v.nom) · \(depart.titre.isEmpty ? depart.categorie.libelle : depart.titre)",
                    jour: lendemain ?? jour)
        }

        for etape in etapes where parcours.compte(etape) {
            let titre = etape.titre.isEmpty ? etape.categorie.libelle : etape.titre
            guard let jour = etape.jour else {
                if etape.aUnBudget || (etape.transport.map { $0.prixAdulte != nil || $0.prixEtudiant != nil || $0.prixAdolescent != nil || $0.prixEnfant != nil } ?? false) {
                    resultat.etapesSansJour += 1
                }
                continue
            }
            let p = etape.aUnBudget
                ? prix((etape.prixAdulte, etape.monnaieAdulte), (etape.prixEtudiant, etape.monnaieEtudiant),
                   (etape.prixAdolescent, etape.monnaieAdolescent), (etape.prixEnfant, etape.monnaieEnfant))
                : [:]
            if !retenir(LienReservation.etape(etape), titre: titre, jour: jour, poste: etape.categorie, prevu: p,
                        nonConcernes: etape.exclusBudget, bascules: etape.basculesTarif), !etape.aUnBudget {
                resultat.etapesSansPrix += 1
            }
            var jourDuTransport = jour
            if etape.apresJour, let lendemain = cal.date(byAdding: .day, value: 1, to: jour) {
                jourDuTransport = min(lendemain, dernier)
            }
            ajouter(parcours.transport(de: etape), cle: LienReservation.transport(depart: etape), titre: titre, jour: jourDuTransport)
        }
        return resultat
    }

    /// Montant d'une dépense déclarée, en euros. Les monnaies autres que l'euro, la locale et la troisième du voyage ne sont pas converties.
    func eurosDeDepense(_ depense: Depense) -> Double? {
        versEuros(depense.montant, code: depense.devise)
    }

    /// Ce que des voyageurs ont déjà réglé : ce qu'ils ont payé, plus les remboursements qu'ils ont faits,
    /// moins ceux qu'ils ont reçus. `ignorees` compte les dépenses dont la monnaie n'a pas pu être convertie.
    func regle(par uids: Set<String>) -> (euros: Double, ignorees: Int) {
        var total = 0.0, ignorees = 0
        for depense in depenses {
            guard let euros = eurosDeDepense(depense) else { ignorees += 1; continue }
            if uids.contains(depense.payeurUID) { total += euros }
            if depense.estRemboursement, let beneficiaire = depense.parts.first?.membreUID, uids.contains(beneficiaire) { total -= euros }
        }
        return (total, ignorees)
    }
}

extension Array where Element == ElementBudget {
    /// Ce que ces éléments coûtent à ces voyageurs, chacun avec son tarif.
    func total(pour membres: [Membre]) -> Double {
        reduce(0) { somme, element in somme + membres.reduce(0) { $0 + element.montant(pour: $1) } }
    }
}
