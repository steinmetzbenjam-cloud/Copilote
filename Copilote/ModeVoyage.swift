import Foundation

/// Les trois temps d'un voyage. Le comportement de chaque mode viendra plus tard ;
/// pour l'instant il s'agit seulement de le choisir et de s'en souvenir.
enum ModeVoyage: String, CaseIterable, Identifiable {
    case preparation, voyage, souvenir
    var id: String { rawValue }

    var nom: String {
        switch self {
        case .preparation: "Préparation"
        case .voyage: "Voyage"
        case .souvenir: "Souvenir"
        }
    }

    var symbole: String {
        switch self {
        case .preparation: "pencil.and.list.clipboard"
        case .voyage: "airplane"
        case .souvenir: "photo.on.rectangle.angled"
        }
    }
}
