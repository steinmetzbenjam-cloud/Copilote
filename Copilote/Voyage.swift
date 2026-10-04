import Foundation
import SwiftData

@Model
final class Voyage {
    var titre: String
    var destination: String
    var debut: Date
    var fin: Date
    var notes: String
    var creeLe: Date
    @Relationship(deleteRule: .cascade, inverse: \Membre.voyage)
    var membres: [Membre] = []

    init(titre: String, destination: String = "", debut: Date = .now, fin: Date = .now.addingTimeInterval(7 * 86_400)) {
        self.titre = titre
        self.destination = destination
        self.debut = debut
        self.fin = fin
        self.notes = ""
        self.creeLe = .now
    }

    var nombreDeJours: Int {
        let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: debut), to: Calendar.current.startOfDay(for: fin)).day ?? 0
        return max(jours + 1, 1)
    }
}
