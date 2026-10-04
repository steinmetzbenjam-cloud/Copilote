import Foundation
import SwiftData

enum CategorieDepense: String, Codable, CaseIterable, Identifiable {
    case restauration, transport, hebergement, activites, courses, autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .restauration: "Restauration"
        case .transport: "Transport"
        case .hebergement: "Hébergement"
        case .activites: "Activités"
        case .courses: "Courses"
        case .autre: "Autre"
        }
    }

    var symbole: String {
        switch self {
        case .restauration: "fork.knife"
        case .transport: "car.fill"
        case .hebergement: "bed.double.fill"
        case .activites: "ticket.fill"
        case .courses: "cart.fill"
        case .autre: "eurosign.circle.fill"
        }
    }
}

/// La part d'une dépense qui revient à un voyageur.
struct PartDepense: Codable, Hashable {
    var membreUID: String
    var montant: Double
}

/// Une dépense du groupe : payée par une personne, répartie entre plusieurs.
/// Un remboursement est une dépense particulière : le payeur donne de l'argent à une seule personne.
@Model
final class Depense {
    var titre: String
    var montant: Double
    var devise: String
    var date: Date
    var categorie: CategorieDepense
    var payeurUID: String
    var parts: [PartDepense] = []
    /// Vrai si les parts ont été saisies à la main, faux si elles sont égales.
    var repartitionPrecise: Bool
    var estRemboursement: Bool
    var notes: String
    var uid: String = ""
    var creeLe: Date
    var voyage: Voyage?

    init(devise: String, payeurUID: String = "", date: Date = .now) {
        self.titre = ""
        self.montant = 0
        self.devise = devise
        self.date = date
        self.categorie = .autre
        self.payeurUID = payeurUID
        self.repartitionPrecise = false
        self.estRemboursement = false
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var estVide: Bool { titre.trimmingCharacters(in: .whitespaces).isEmpty && montant == 0 }
}

/// Calcul des soldes et des remboursements qui équilibrent les comptes.
enum Comptes {
    struct Virement: Hashable {
        var de: String
        var vers: String
        var montant: Double
    }

    private static func arrondi(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    /// Répartit un montant en parts égales, au centime près (les centimes en trop vont aux premiers).
    static func repartir(_ montant: Double, entre membres: [String]) -> [PartDepense] {
        guard !membres.isEmpty else { return [] }
        let centimes = Int((montant * 100).rounded())
        let base = centimes / membres.count, reste = centimes % membres.count
        return membres.enumerated().map { i, uid in
            PartDepense(membreUID: uid, montant: Double(base + (i < reste ? 1 : 0)) / 100)
        }
    }

    /// Solde de chacun, devise par devise : positif = le groupe lui doit de l'argent, négatif = il en doit.
    static func soldes(_ depenses: [Depense]) -> [String: [String: Double]] {
        var resultat: [String: [String: Double]] = [:]
        for d in depenses {
            resultat[d.devise, default: [:]][d.payeurUID, default: 0] += d.montant
            for part in d.parts { resultat[d.devise, default: [:]][part.membreUID, default: 0] -= part.montant }
        }
        return resultat.mapValues { $0.mapValues(arrondi) }
    }

    /// Remboursements qui remettent tout le monde à zéro, en un minimum de virements.
    static func virements(_ soldes: [String: Double]) -> [Virement] {
        var crediteurs = soldes.filter { $0.value > 0.004 }.sorted { $0.value > $1.value }.map { (uid: $0.key, reste: $0.value) }
        var debiteurs = soldes.filter { $0.value < -0.004 }.sorted { $0.value < $1.value }.map { (uid: $0.key, reste: -$0.value) }
        var virements: [Virement] = []
        var i = 0, j = 0
        while i < debiteurs.count, j < crediteurs.count {
            let montant = arrondi(min(debiteurs[i].reste, crediteurs[j].reste))
            if montant > 0 { virements.append(Virement(de: debiteurs[i].uid, vers: crediteurs[j].uid, montant: montant)) }
            debiteurs[i].reste -= montant
            crediteurs[j].reste -= montant
            if debiteurs[i].reste < 0.005 { i += 1 }
            if crediteurs[j].reste < 0.005 { j += 1 }
        }
        return virements
    }

    /// Total dépensé par devise, remboursements exclus.
    static func totaux(_ depenses: [Depense]) -> [(devise: String, montant: Double)] {
        Dictionary(grouping: depenses.filter { !$0.estRemboursement }, by: \.devise)
            .map { ($0.key, arrondi($0.value.reduce(0) { $0 + $1.montant })) }
            .sorted { $0.0 < $1.0 }
    }
}
