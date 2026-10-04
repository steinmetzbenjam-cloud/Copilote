import Foundation
import CoreLocation

enum TypeLieu: String, CaseIterable, Identifiable {
    case activite, restaurant
    var id: String { rawValue }
    var libelle: String { self == .activite ? "À voir, à faire" : "Restaurants" }
    var symbole: String { self == .activite ? "binoculars.fill" : "fork.knife" }
}

enum SourceAvis: String {
    case google = "Google"
    case tripadvisor = "Tripadvisor"
}

struct AvisSource: Hashable {
    var source: SourceAvis
    var note: Double
    var nombre: Int
    var lien: URL?
}

/// Un lieu proposé, fusionnant ce que savent Google, Tripadvisor et Plans à son sujet.
struct LieuPropose: Identifiable, Hashable {
    static func == (a: LieuPropose, b: LieuPropose) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id = UUID()
    var nom: String
    var adresse: String
    var coordonnee: CLLocationCoordinate2D
    var type: TypeLieu
    var genre: String?
    var avis: [AvisSource] = []
    var resume: String?
    var horaires: [String] = []
    var photos: [URL] = []
    var siteWeb: URL?
    var prix: String?
    var classementTripadvisor: String?
    var idGoogle: String?
    var idTripadvisor: String?

    var nombreAvisTotal: Int { avis.reduce(0) { $0 + $1.nombre } }

    func avis(de source: SourceAvis) -> AvisSource? { avis.first { $0.source == source } }

    /// Note moyenne « prudente » : les lieux peu commentés sont ramenés vers la moyenne,
    /// puis les sources sont mêlées en pesant davantage celle qui a le plus d'avis.
    var score: Double? {
        guard !avis.isEmpty else { return nil }
        let moyenneGenerale = 4.2, prudence = 30.0
        var somme = 0.0, poids = 0.0
        for a in avis where a.nombre > 0 {
            let n = Double(a.nombre)
            let prudente = (n / (n + prudence)) * a.note + (prudence / (n + prudence)) * moyenneGenerale
            let p = log10(2 + n)
            somme += prudente * p
            poids += p
        }
        guard poids > 0 else { return nil }
        return somme / poids + 0.1 * log10(1 + Double(nombreAvisTotal))
    }
}
