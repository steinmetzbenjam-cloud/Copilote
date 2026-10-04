import Foundation
import SwiftData

@Model
final class Membre {
    var nom: String
    var voyage: Voyage?
    var creeLe: Date
    var uid: String = ""

    init(nom: String) {
        self.nom = nom
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}
