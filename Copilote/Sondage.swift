import Foundation
import SwiftData
import CryptoKit

/// Une option d'un vote : « Restaurant La Luna », « Excursion en bateau »…
struct OptionSondage: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var titre: String = ""
    var detail: String = ""
}

/// Une proposition soumise au vote du groupe : plusieurs options, une voix par famille.
@Model
final class Sondage {
    var titre: String = ""
    var notes: String = ""
    var optionsJSON: String = "[]"
    var clos: Bool = false
    /// L'option retenue une fois le vote clos.
    var optionRetenue: String?
    /// `Membre.uid` de celui qui a lancé le vote.
    var auteurUID: String = ""
    var creeLe: Date = Date.now
    var uid: String = ""
    var voyage: Voyage?

    init(titre: String, auteurUID: String) {
        self.titre = titre
        self.auteurUID = auteurUID
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var options: [OptionSondage] {
        get { optionsJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode([OptionSondage].self, from: $0) } ?? [] }
        set { optionsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    }
}

/// La voix d'une famille (ou d'un voyageur seul) sur un vote. Un seul enregistrement par famille et par vote.
@Model
final class VoteSondage {
    var sondageUID: String = ""
    var optionID: String = ""
    /// Clé stable du compte qui vote (`Voyage.cleCompte`).
    var compteCle: String = ""
    /// Qui a voté, au nom de sa famille.
    var auteurUID: String = ""
    var modifieLe: Date = Date.now
    var uid: String = ""
    var voyage: Voyage?

    init(sondageUID: String, optionID: String, compteCle: String, auteurUID: String) {
        self.sondageUID = sondageUID
        self.optionID = optionID
        self.compteCle = compteCle
        self.auteurUID = auteurUID
        self.modifieLe = .now
        self.uid = Self.identifiant(sondageUID: sondageUID, compteCle: compteCle)
    }

    /// Identifiant déterministe : deux appareils qui votent pour la même famille écrivent le même enregistrement.
    static func identifiant(sondageUID: String, compteCle: String) -> String {
        let hash = SHA256.hash(data: Data(compteCle.lowercased().utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(sondageUID).\(hash)"
    }
}

extension Voyage {
    /// Clé stable d'une famille (ou d'un voyageur seul), identique sur tous les appareils.
    func cleCompte(de uid: String) -> String {
        guard let m = membre(uid: uid) else { return "m:" + uid }
        return m.famille.isEmpty ? "m:" + m.uid : "f:" + m.famille.lowercased()
    }

    func votes(de sondage: Sondage) -> [VoteSondage] { votes.filter { $0.sondageUID == sondage.uid } }

    /// Fait voter ma famille pour l'option ; toucher à nouveau la même option retire la voix.
    func voter(_ option: OptionSondage, dans sondage: Sondage, par uid: String, contexte: ModelContext) {
        guard !sondage.clos else { return }
        let cle = cleCompte(de: uid)
        let id = VoteSondage.identifiant(sondageUID: sondage.uid, compteCle: cle)
        if let existant = votes.first(where: { $0.uid == id }) {
            if existant.optionID == option.id { contexte.delete(existant) } else {
                existant.optionID = option.id
                existant.auteurUID = uid
                existant.modifieLe = .now
            }
        } else {
            let vote = VoteSondage(sondageUID: sondage.uid, optionID: option.id, compteCle: cle, auteurUID: uid)
            vote.voyage = self
            contexte.insert(vote)
        }
    }

    /// Supprime un vote avec ses voix.
    func supprimer(_ sondage: Sondage, contexte: ModelContext) {
        for v in votes(de: sondage) { contexte.delete(v) }
        contexte.delete(sondage)
    }
}
