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
    @Relationship(deleteRule: .cascade, inverse: \Membre.voyage)
    var membres: [Membre] = []
    @Relationship(deleteRule: .cascade, inverse: \Etape.voyage)
    var etapes: [Etape] = []

    init(titre: String, destination: String = "", debut: Date = .now, fin: Date = .now.addingTimeInterval(7 * 86_400)) {
        self.titre = titre
        self.destination = destination
        self.debut = debut
        self.fin = fin
        self.notes = ""
        self.creeLe = .now
    }

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
    /// Étapes d'un jour, triées par heure puis par ordre de création.
    func etapes(du jour: Date) -> [Etape] {
        etapes
            .filter { Calendar.current.isDate($0.jour, inSameDayAs: jour) }
            .sorted { ($0.heure ?? .distantFuture, $0.creeLe) < ($1.heure ?? .distantFuture, $1.creeLe) }
    }
}
