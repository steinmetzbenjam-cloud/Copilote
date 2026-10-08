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
    /// Famille à laquelle le voyageur appartient pour le budget (nom libre, commun aux membres d'une même famille).
    var familleNom: String?
    var age: Int?
    /// Tarif choisi à la main (`Tarif`) ; sinon il découle de l'âge.
    var tarifBrut: String?
    /// E-mail utilisé pour inviter cette personne dans l'app : sert à la reconnaître quand elle ouvre le voyage.
    var emailInvitation: String?
    /// Rôle dans le voyage (`RoleVoyage`) ; vide tant qu'aucun rôle n'a été distribué.
    var roleBrut: String?

    init(nom: String) {
        self.nom = nom
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}
