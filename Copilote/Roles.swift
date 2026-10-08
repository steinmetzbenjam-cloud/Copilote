import SwiftUI

/// Ce que chacun peut faire dans un voyage. Les rôles règlent ce que l'app propose ; ils ne remplacent pas
/// les droits du partage iCloud (toute personne invitée avec droit d'écriture reste techniquement capable de modifier les données).
enum RoleVoyage: String, CaseIterable, Identifiable {
    case organisateur, voyageur, lecteur

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .organisateur: "Organisateur"
        case .voyageur: "Voyageur"
        case .lecteur: "Lecteur"
        }
    }

    var symbole: String {
        switch self {
        case .organisateur: "crown.fill"
        case .voyageur: "person.fill"
        case .lecteur: "eye.fill"
        }
    }

    var couleur: Color {
        switch self {
        case .organisateur: .orange
        case .voyageur: .blue
        case .lecteur: .gray
        }
    }

    var description: String {
        switch self {
        case .organisateur: "Peut tout faire : voyage, familles, rôles, partage, votes, documents de tous."
        case .voyageur: "Modifie l'itinéraire, les réservations et les dépenses, propose et vote, gère ses propres documents."
        case .lecteur: "Consulte tout, sans rien modifier ni voter."
        }
    }
}

extension Membre {
    var roleExplicite: RoleVoyage? { roleBrut.flatMap(RoleVoyage.init(rawValue:)) }
}

extension Voyage {
    /// Tant que personne n'a été nommé organisateur, tout le monde l'est (voyages créés avant les rôles) ;
    /// ensuite, un voyageur sans rôle précis est « voyageur ».
    func role(de uid: String) -> RoleVoyage {
        guard let membre = membre(uid: uid) else { return .organisateur }
        if let r = membre.roleExplicite { return r }
        return membres.contains { $0.roleExplicite == .organisateur } ? .voyageur : .organisateur
    }

    /// Mon rôle. Si l'app ne sait pas encore qui je suis, aucune restriction n'est appliquée.
    var monRole: RoleVoyage {
        let moi = MoiVoyage.lire(self)
        return moi.isEmpty ? .organisateur : role(de: moi)
    }

    var estOrganisateur: Bool { monRole == .organisateur }
    var lectureSeule: Bool { monRole == .lecteur }

    /// Seul un organisateur change les rôles. Pour ne jamais perdre le dernier organisateur, on peut seulement le laisser tel quel.
    func peutChangerRole(de membre: Membre) -> Bool {
        guard estOrganisateur else { return false }
        if role(de: membre.uid) == .organisateur {
            return membres.filter { role(de: $0.uid) == .organisateur }.count > 1
        }
        return true
    }

    /// Donne un rôle. La première fois qu'on en distribue un, je deviens organisateur explicite : sinon tout le monde le serait encore.
    func attribuer(_ role: RoleVoyage, a membre: Membre) {
        let moi = MoiVoyage.lire(self)
        if let moiMembre = self.membre(uid: moi), moiMembre.roleExplicite == nil, role != .organisateur || moiMembre !== membre {
            if !membres.contains(where: { $0.roleExplicite == .organisateur }) { moiMembre.roleBrut = RoleVoyage.organisateur.rawValue }
        }
        membre.roleBrut = role.rawValue
    }

    /// Peut gérer les documents de cette personne : l'organisateur ceux de tous, un voyageur les siens.
    func peutGererDocuments(de membre: Membre) -> Bool {
        switch monRole {
        case .organisateur: true
        case .voyageur: membre.uid == MoiVoyage.lire(self)
        case .lecteur: false
        }
    }
}

/// Une pastille de rôle.
struct PastilleRole: View {
    var role: RoleVoyage

    var body: some View {
        Label(role.libelle, systemImage: role.symbole)
            .font(.caption2.weight(.semibold)).foregroundStyle(role.couleur)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(role.couleur.opacity(0.14), in: Capsule())
    }
}
