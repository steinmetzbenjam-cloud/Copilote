import SwiftUI

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

    /// Une couleur par mode : bleu pour préparer, vert pour voyager, orange pour se souvenir.
    var couleur: Color {
        switch self {
        case .preparation: Color(rouge: 0x5B, vert: 0x6C, bleu: 0xFF)
        case .voyage: Color(rouge: 0x10, vert: 0xB9, bleu: 0x81)
        case .souvenir: Color(rouge: 0xFF, vert: 0x7A, bleu: 0x59)
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

/// La police du nom du voyage, inspirée de son premier pays (polices fournies avec iOS et macOS).
enum PoliceVoyage {
    private static let familles: [(pays: [String], nom: String)] = [
        (["JP"], "HiraMinProN-W6"),
        (["CN", "TW", "HK", "MO", "SG"], "STSongti-SC-Bold"),
        (["KR"], "AppleMyungjo"),
        (["TH", "VN", "KH", "LA", "MM", "ID", "MY", "PH"], "Thonburi-Bold"),
        (["IN", "NP", "LK", "BT", "BD"], "DevanagariSangamMN-Bold"),
        (["EG", "MA", "TN", "DZ", "TR", "JO", "AE", "OM", "SA", "IL", "LB"], "Papyrus"),
        (["IT", "SM", "VA", "MT"], "Copperplate-Bold"),
        (["FR", "MC", "LU"], "Didot-Bold"),
        (["GR", "CY"], "Optima-ExtraBlack"),
        (["ES", "PT", "AD"], "Baskerville-BoldItalic"),
        (["CR", "MX", "PE", "CO", "BR", "AR", "CL", "EC", "BO", "PA", "CU", "DO", "GT", "HN", "NI", "SV", "UY", "PY", "VE", "JM"], "MarkerFelt-Wide"),
        (["US", "CA"], "AmericanTypewriter-Bold"),
        (["GB", "IE"], "Baskerville-Bold"),
        (["DE", "AT", "CH", "NL", "BE", "PL", "CZ", "HU"], "Futura-Bold"),
        (["NO", "SE", "FI", "DK", "IS"], "AvenirNextCondensed-Heavy"),
        (["AU", "NZ", "FJ", "PF", "NC"], "Noteworthy-Bold"),
        (["ZA", "KE", "TZ", "NA", "BW", "MG", "SN", "ET", "UG"], "Chalkduster"),
    ]

    static func police(pour pays: [String], taille: CGFloat) -> Font {
        if let code = pays.first, let famille = familles.first(where: { $0.pays.contains(code) }) {
            return .custom(famille.nom, size: taille)
        }
        return .system(size: taille, weight: .heavy, design: .rounded)
    }
}
