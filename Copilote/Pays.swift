import Foundation
import MapKit

struct Pays: Identifiable, Hashable {
    let code: String
    let nom: String

    var id: String { code }

    /// Drapeau emoji construit à partir du code ISO (FR → 🇫🇷).
    var drapeau: String {
        code.unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }

    /// Codes ISO qui ne sont pas des pays (zones, réservés, territoires techniques).
    private static let exclus: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "XA", "XB", "AC", "CP", "CQ", "DG", "EA", "IC", "TA"]

    /// Tous les pays, noms en français, triés alphabétiquement.
    static let tous: [Pays] = {
        let fr = Locale(identifier: "fr_FR")
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) && !exclus.contains($0) }
            .compactMap { code in fr.localizedString(forRegionCode: code).map { Pays(code: code, nom: $0) } }
            .sorted { $0.nom.compare($1.nom, locale: fr) == .orderedAscending }
    }()

    static func avec(code: String) -> Pays? {
        tous.first { $0.code == code }
    }

    /// Zone de carte d'un seul pays, mise en cache après la première recherche.
    static func region(de code: String) async -> MKCoordinateRegion? {
        if let connue = await CacheRegions.shared.valeur(pour: code) { return connue }
        guard let pays = avec(code: code) else { return nil }
        let requete = MKLocalSearch.Request()
        requete.naturalLanguageQuery = pays.nom
        requete.resultTypes = .address
        guard let region = try? await MKLocalSearch(request: requete).start().boundingRegion else { return nil }
        await CacheRegions.shared.enregistrer(region, pour: code)
        return region
    }

    /// Zone de carte qui englobe tous les pays donnés, via la recherche Plans.
    static func regionCarte(pour codes: [String]) async -> MKCoordinateRegion? {
        var regions: [MKCoordinateRegion] = []
        for code in codes {
            if let region = await region(de: code) { regions.append(region) }
        }
        guard !regions.isEmpty else { return nil }
        let nord = regions.map { $0.center.latitude + $0.span.latitudeDelta / 2 }.max()!
        let sud = regions.map { $0.center.latitude - $0.span.latitudeDelta / 2 }.min()!
        let est = regions.map { $0.center.longitude + $0.span.longitudeDelta / 2 }.max()!
        let ouest = regions.map { $0.center.longitude - $0.span.longitudeDelta / 2 }.min()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (nord + sud) / 2, longitude: (est + ouest) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(nord - sud, 170), longitudeDelta: min(est - ouest, 350)))
    }
}

private actor CacheRegions {
    static let shared = CacheRegions()
    private var regions: [String: MKCoordinateRegion] = [:]

    func valeur(pour code: String) -> MKCoordinateRegion? { regions[code] }
    func enregistrer(_ region: MKCoordinateRegion, pour code: String) { regions[code] = region }
}
