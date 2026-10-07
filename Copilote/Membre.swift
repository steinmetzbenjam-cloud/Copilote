import Foundation
import SwiftData

@Model
final class Membre {
    var nom: String
    var voyage: Voyage?
    var creeLe: Date
    var uid: String = ""
    /// Informations du profil, partagées avec les autres voyageurs du voyage.
    var nomFamille: String?
    var email: String?
    @Attribute(.externalStorage) var avatar: Data?

    init(nom: String) {
        self.nom = nom
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}
