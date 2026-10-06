import Foundation
import SwiftData
import SwiftUI

/// Un message dans la discussion du groupe sur la préparation du voyage.
@Model
final class Commentaire {
    var texte: String = ""
    /// `Membre.uid` de l'auteur.
    var auteurUID: String = ""
    var date: Date = Date.now
    var uid: String = ""
    var voyage: Voyage?

    init(texte: String, auteurUID: String) {
        self.texte = texte
        self.auteurUID = auteurUID
        self.date = .now
        self.uid = UUID().uuidString
    }
}

/// Ce que quelqu'un pense d'une étape : l'envie qu'il en a.
enum EnvieEtape: String, Codable, CaseIterable, Identifiable {
    case incontournable, neutre, pasEnvie

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .incontournable: "Incontournable"
        case .neutre: "Pourquoi pas"
        case .pasEnvie: "Pas pour moi"
        }
    }

    var symbole: String {
        switch self {
        case .incontournable: "heart.fill"
        case .neutre: "hand.raised.fill"
        case .pasEnvie: "hand.thumbsdown.fill"
        }
    }

    var couleur: Color {
        switch self {
        case .incontournable: .green
        case .neutre: .secondary
        case .pasEnvie: .red
        }
    }
}

/// L'avis d'un voyageur sur une étape : des étoiles, une envie, un mot. Un seul par personne et par étape
/// (l'identifiant est déterministe, pour que deux appareils n'en créent jamais deux).
@Model
final class AvisEtape {
    var etapeUID: String = ""
    var auteurUID: String = ""
    /// 0 = pas de note, sinon de 1 à 5.
    var etoiles: Int = 0
    var envie: EnvieEtape = EnvieEtape.neutre
    var commentaire: String = ""
    var modifieLe: Date = Date.now
    var uid: String = ""
    var voyage: Voyage?

    init(etapeUID: String, auteurUID: String) {
        self.etapeUID = etapeUID
        self.auteurUID = auteurUID
        self.uid = Self.identifiant(etapeUID: etapeUID, auteurUID: auteurUID)
    }

    static func identifiant(etapeUID: String, auteurUID: String) -> String { "\(etapeUID)_\(auteurUID)" }

    var estVide: Bool { etoiles == 0 && envie == .neutre && commentaire.trimmingCharacters(in: .whitespaces).isEmpty }
}

extension Voyage {
    func avis(de etape: Etape) -> [AvisEtape] {
        avisEtapes.filter { $0.etapeUID == etape.uid && !$0.estVide }
    }

    func monAvis(sur etape: Etape, moi: String) -> AvisEtape? {
        avisEtapes.first { $0.etapeUID == etape.uid && $0.auteurUID == moi }
    }

    func nomMembre(_ uid: String) -> String {
        membres.first { $0.uid == uid }?.nom ?? "Quelqu'un"
    }

    /// Synthèse des avis du groupe sur une étape.
    func synthese(de etape: Etape) -> (moyenne: Double?, incontournables: Int, refus: Int, total: Int) {
        let tous = avis(de: etape)
        let notes = tous.map(\.etoiles).filter { $0 > 0 }
        return (notes.isEmpty ? nil : Double(notes.reduce(0, +)) / Double(notes.count),
                tous.filter { $0.envie == .incontournable }.count,
                tous.filter { $0.envie == .pasEnvie }.count,
                tous.count)
    }
}

/// « Qui es-tu ? » : le voyageur de cet appareil, retenu par voyage (comme dans l'onglet Dépenses).
enum MoiVoyage {
    static func cle(_ voyage: Voyage) -> String { "moi-\(voyage.uid)" }
    static func lire(_ voyage: Voyage) -> String { UserDefaults.standard.string(forKey: cle(voyage)) ?? "" }
    static func ecrire(_ uid: String, _ voyage: Voyage) { UserDefaults.standard.set(uid, forKey: cle(voyage)) }
}
