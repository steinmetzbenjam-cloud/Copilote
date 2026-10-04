import Foundation
import SwiftData

enum CategorieEtape: String, Codable, CaseIterable, Identifiable {
    case visite, repas, transport, hebergement, activite, autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .visite: "Visite"
        case .repas: "Repas"
        case .transport: "Transport"
        case .hebergement: "Hébergement"
        case .activite: "Activité"
        case .autre: "Autre"
        }
    }

    var symbole: String {
        switch self {
        case .visite: "mappin.and.ellipse"
        case .repas: "fork.knife"
        case .transport: "car.fill"
        case .hebergement: "bed.double.fill"
        case .activite: "figure.hiking"
        case .autre: "star.fill"
        }
    }
}

@Model
final class Etape {
    var titre: String
    var lieu: String
    var jour: Date
    var heure: Date?
    var categorie: CategorieEtape
    var notes: String
    var creeLe: Date
    var voyage: Voyage?

    init(titre: String, jour: Date, categorie: CategorieEtape = .visite) {
        self.titre = titre
        self.lieu = ""
        self.jour = Calendar.current.startOfDay(for: jour)
        self.heure = nil
        self.categorie = categorie
        self.notes = ""
        self.creeLe = .now
    }
}
