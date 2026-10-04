import Foundation
import SwiftData

@Model
final class Voyage {
    var titre: String
    var destination: String
    var debut: Date
    var fin: Date
    var notes: String = ""
    /// Codes ISO des pays visités (FR, IT…), dans l'ordre choisi.
    var pays: [String] = []
    var creeLe: Date
    /// Identifiant stable, commun à tous les appareils (synchronisation iCloud).
    var uid: String = ""
    /// Vide si le voyage est le mien ; sinon, propriétaire iCloud du voyage reçu.
    var zoneProprietaire: String = ""
    var partage: Bool = false
    var participantsCloud: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \Membre.voyage)
    var membres: [Membre] = []
    @Relationship(deleteRule: .cascade, inverse: \Etape.voyage)
    var etapes: [Etape] = []
    @Relationship(deleteRule: .cascade, inverse: \JourVoyage.voyage)
    var infosJours: [JourVoyage] = []
    @Relationship(deleteRule: .cascade, inverse: \Depense.voyage)
    var depenses: [Depense] = []
    @Relationship(deleteRule: .cascade, inverse: \Reservation.voyage)
    var reservations: [Reservation] = []
    @Relationship(deleteRule: .cascade, inverse: \Document.voyage)
    var documents: [Document] = []

    init(titre: String, destination: String = "", debut: Date = .now, fin: Date = .now.addingTimeInterval(7 * 86_400)) {
        self.titre = titre
        self.destination = destination
        self.debut = debut
        self.fin = fin
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var estRecu: Bool { !zoneProprietaire.isEmpty }

    /// Chaque jour du voyage, du départ au retour.
    var jours: [Date] {
        let cal = Calendar.current
        let premier = cal.startOfDay(for: debut)
        return (0..<nombreDeJours).compactMap { cal.date(byAdding: .day, value: $0, to: premier) }
    }

    var nombreDeJours: Int {
        let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: debut), to: Calendar.current.startOfDay(for: fin)).day ?? 0
        return max(jours + 1, 1)
    }
}

extension Voyage {
    /// Étapes d'un jour dans l'ordre choisi en les glissant ; à défaut, par heure puis par ordre de création.
    func etapes(du jour: Date) -> [Etape] {
        etapes
            .filter { Calendar.current.isDate($0.jour, inSameDayAs: jour) }
            .sorted { ($0.ordre, $0.heure ?? .distantFuture, $0.creeLe) < ($1.ordre, $1.heure ?? .distantFuture, $1.creeLe) }
    }

    /// Place l'étape à son nouvel endroit (dans le même jour ou un autre), juste avant `cible` ou en fin de journée,
    /// puis renumérote les journées touchées. Renvoie false si rien ne change.
    @discardableResult
    func deplacer(_ etape: Etape, vers jour: Date, avant cible: Etape?) -> Bool {
        guard cible !== etape, etapes.contains(where: { $0 === etape }) else { return false }
        let cal = Calendar.current
        let ancienJour = etape.jour
        var liste = etapes(du: jour).filter { $0 !== etape }
        let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
        liste.insert(etape, at: index)
        etape.jour = cal.startOfDay(for: jour)
        for (i, e) in liste.enumerated() { e.ordre = Double(i) }
        if !cal.isDate(ancienJour, inSameDayAs: jour) {
            for (i, e) in etapes(du: ancienJour).enumerated() { e.ordre = Double(i) }
        }
        return true
    }

    /// Remet les étapes d'un jour dans l'ordre des heures (celles sans heure à la fin).
    func trierParHeure(_ jour: Date) {
        let triees = etapes(du: jour).sorted { ($0.heure ?? .distantFuture, $0.creeLe) < ($1.heure ?? .distantFuture, $1.creeLe) }
        for (i, e) in triees.enumerated() { e.ordre = Double(i) }
    }

    /// Position à donner à une nouvelle étape pour qu'elle arrive en fin de journée.
    func prochainOrdre(du jour: Date) -> Double {
        (etapes(du: jour).map(\.ordre).max() ?? 0) + 1
    }
}
