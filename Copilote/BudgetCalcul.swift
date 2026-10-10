import Foundation

/// Tarif appliqué à un voyageur : celui des prix « adulte », « étudiant » ou « enfant » saisis sur les étapes et les transports.
enum Tarif: String, CaseIterable, Identifiable {
    case adulte, etudiant, enfant

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .adulte: "Adulte"
        case .etudiant: "Étudiant"
        case .enfant: "Enfant"
        }
    }

    /// Jusqu'à cet âge (compris), le tarif enfant s'applique par défaut. Un âge inconnu donne le tarif adulte.
    static let ageEnfantMax = 17

    static func pour(age: Int?) -> Tarif {
        guard let age, age <= ageEnfantMax else { return .adulte }
        return .enfant
    }
}

extension Membre {
    /// Le tarif choisi à la main, sinon celui qui découle de l'âge.
    var tarif: Tarif { tarifBrut.flatMap(Tarif.init(rawValue:)) ?? Tarif.pour(age: age) }

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

    func montant(_ tarif: Tarif) -> Double { prix[tarif] ?? 0 }
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
        func prix(_ a: (Double?, MonnaiePrix), _ e: (Double?, MonnaiePrix), _ n: (Double?, MonnaiePrix)) -> [Tarif: Double] {
            var r: [Tarif: Double] = [:]
            if let v = euros(a.0, a.1) { r[.adulte] = v }
            if let v = euros(e.0, e.1) { r[.etudiant] = v }
            if let v = euros(n.0, n.1) { r[.enfant] = v }
            return r
        }
        func ajouter(_ transport: Transport?, titre: String, jour: Date) {
            guard let t = transport else { return }
            let p = prix((t.prixAdulte, t.monnaieAdulte), (t.prixEtudiant, t.monnaieEtudiant), (t.prixEnfant, t.monnaieEnfant))
            if !p.isEmpty {
                resultat.elements.append(ElementBudget(titre: "\(t.mode.libelleCourt) · \(titre)", jour: jour, poste: .transport, prix: p))
            }
        }

        ajouter(transportAller, titre: "Aller", jour: premier)
        ajouter(transportRetour, titre: "Retour", jour: dernier)

        for etape in etapes {
            let titre = etape.titre.isEmpty ? etape.categorie.libelle : etape.titre
            guard let jour = etape.jour else {
                if etape.aUnBudget || (etape.transport.map { $0.prixAdulte != nil || $0.prixEtudiant != nil || $0.prixEnfant != nil } ?? false) {
                    resultat.etapesSansJour += 1
                }
                continue
            }
            if etape.aUnBudget {
                let p = prix((etape.prixAdulte, etape.monnaieAdulte), (etape.prixEtudiant, etape.monnaieEtudiant),
                             (etape.prixEnfant, etape.monnaieEnfant))
                if !p.isEmpty { resultat.elements.append(ElementBudget(titre: titre, jour: jour, poste: etape.categorie, prix: p)) }
            } else {
                resultat.etapesSansPrix += 1
            }
            var jourDuTransport = jour
            if etape.apresJour, let lendemain = cal.date(byAdding: .day, value: 1, to: jour) {
                jourDuTransport = min(lendemain, dernier)
            }
            ajouter(etape.transport, titre: titre, jour: jourDuTransport)
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
        reduce(0) { somme, element in somme + membres.reduce(0) { $0 + element.montant($1.tarif) } }
    }
}
