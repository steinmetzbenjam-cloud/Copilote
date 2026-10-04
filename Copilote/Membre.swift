import Foundation
import SwiftData

@Model
final class Membre {
    var nom: String
    var voyage: Voyage?
    var creeLe: Date

    init(nom: String) {
        self.nom = nom
        self.creeLe = .now
    }
}
