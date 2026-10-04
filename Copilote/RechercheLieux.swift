import Foundation
import MapKit

struct LieuTrouve: Identifiable {
    let id = UUID()
    var nom: String
    var adresse: String
    var coordonnee: CLLocationCoordinate2D
    var categorie: MKPointOfInterestCategory?
    var codePays: String?

    var symbole: String {
        switch categorie {
        case .some(.airport): "airplane"
        case .some(.publicTransport): "tram.fill"
        case .some(.hotel): "bed.double.fill"
        case .some(.restaurant), .some(.cafe), .some(.bakery): "fork.knife"
        case .some(.museum): "building.columns.fill"
        case .some(.beach): "beach.umbrella.fill"
        case .some(.park), .some(.nationalPark): "tree.fill"
        case .some(.carRental), .some(.gasStation), .some(.parking): "car.fill"
        default: "mappin.circle.fill"
        }
    }
}

/// Recherche de lieux précise : interroge Plans pays par pays, avec des filtres de catégorie
/// déduits des mots tapés (« aéroport », « hôtel »…), et ne garde que les pays du voyage.
enum RechercheLieux {
    private static let motsCles: [(mots: [String], categories: [MKPointOfInterestCategory])] = [
        (["aeroport", "airport", "aeropuerto"], [.airport]),
        (["gare", "station", "train", "metro", "bus", "terminal", "estacion"], [.publicTransport]),
        (["hotel", "auberge", "hostel", "hostal", "resort", "lodge"], [.hotel]),
        (["restaurant", "resto", "cafe", "bar", "soda"], [.restaurant, .cafe, .bakery]),
        (["musee", "museum", "museo"], [.museum]),
        (["plage", "beach", "playa"], [.beach]),
        (["parc", "park", "parque", "volcan", "volcano"], [.park, .nationalPark]),
        (["location", "rental", "alquiler", "loueur"], [.carRental]),
        (["essence", "carburant", "gas"], [.gasStation]),
    ]

    /// Minuscules, sans accents ni ponctuation (l'apostrophe droite et la typographique se valent).
    private static func normaliser(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    /// Trois lettres seules (SJO, CDG…) : peut être un code IATA d'aéroport.
    private static func ressembleAUnCodeIATA(_ texte: String) -> Bool {
        texte.count == 3 && texte.allSatisfy { $0.isLetter && $0.isASCII }
    }

    static func categories(pour texte: String) -> [MKPointOfInterestCategory] {
        let mots = Set(normaliser(texte).split(separator: " ").map(String.init))
        for entree in motsCles where !mots.isDisjoint(with: entree.mots) { return entree.categories }
        return []
    }

    static func chercher(_ texte: String, pays codes: [String]) async -> [LieuTrouve] {
        let texte = texte.trimmingCharacters(in: .whitespaces)
        guard texte.count >= 2 else { return [] }
        var categories = categories(pour: texte)
        if ressembleAUnCodeIATA(texte) && !categories.contains(.airport) { categories.append(.airport) }
        let filtre = categories.isEmpty ? nil : MKPointOfInterestFilter(including: categories)

        // Une série de requêtes par pays (ou une seule sans pays), lancées en parallèle.
        let cibles: [(pays: Pays?, region: MKCoordinateRegion?)] = codes.isEmpty
            ? [(nil, nil)]
            : await withTaskGroup(of: (Int, Pays?, MKCoordinateRegion?).self) { groupe in
                for (i, code) in codes.prefix(4).enumerated() {
                    groupe.addTask { (i, Pays.avec(code: code), await Pays.region(de: code)) }
                }
                var sortie: [(Int, Pays?, MKCoordinateRegion?)] = []
                for await r in groupe { sortie.append(r) }
                return sortie.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
            }

        var requetes: [MKLocalSearch.Request] = []
        for cible in cibles {
            var variantes: [(String, MKPointOfInterestFilter?)] = []
            if let nom = cible.pays?.nom { variantes.append(("\(texte) \(nom)", filtre)) }
            variantes.append((texte, filtre))
            if filtre != nil { variantes.append((texte, nil)) }
            if let nom = cible.pays?.nom, filtre != nil { variantes.append(("\(texte) \(nom)", nil)) }
            for (requete, f) in variantes {
                let r = MKLocalSearch.Request()
                r.naturalLanguageQuery = requete
                if let region = cible.region { r.region = region }
                if let f { r.pointOfInterestFilter = f }
                requetes.append(r)
            }
        }

        let groupes: [[MKMapItem]] = await withTaskGroup(of: (Int, [MKMapItem]).self) { groupe in
            for (i, r) in requetes.enumerated() {
                groupe.addTask { (i, (try? await MKLocalSearch(request: r).start().mapItems) ?? []) }
            }
            var sortie: [(Int, [MKMapItem])] = []
            for await r in groupe { sortie.append(r) }
            return sortie.sorted { $0.0 < $1.0 }.map(\.1)
        }

        var vus = Set<String>()
        var lieux: [LieuTrouve] = []
        for item in groupes.flatMap({ $0 }) {
            let c = item.placemark.coordinate
            let cle = "\(normaliser(item.name ?? ""))|\(Int(c.latitude * 200))|\(Int(c.longitude * 200))"
            guard vus.insert(cle).inserted, let nom = item.name else { continue }
            lieux.append(LieuTrouve(nom: nom, adresse: adresse(de: item.placemark), coordonnee: c,
                                    categorie: item.pointOfInterestCategory, codePays: item.placemark.isoCountryCode))
        }

        // Si le voyage a des pays, on ne garde que les lieux qui s'y trouvent.
        if !codes.isEmpty {
            let dansLesPays = lieux.filter { $0.codePays.map(codes.contains) ?? false }
            if !dansLesPays.isEmpty { lieux = dansLesPays }
        }

        // Pertinence : nom identique à la saisie, puis catégorie demandée (aéroport, hôtel…), puis le reste.
        let recherche = normaliser(texte)
        func rang(_ lieu: LieuTrouve) -> Int {
            let nom = normaliser(lieu.nom)
            let nomExact = nom == recherche ? 0 : (nom.hasPrefix(recherche) ? 1 : (nom.contains(recherche) ? 2 : 3))
            let categorieOk = categories.isEmpty || lieu.categorie.map(categories.contains) ?? false
            if nomExact == 0 { return 0 }
            return (categorieOk ? 1 : 11) + nomExact
        }
        let tries = lieux.enumerated().sorted { (rang($0.element), $0.offset) < (rang($1.element), $1.offset) }
        return Array(tries.map(\.element).prefix(20))
    }

    private static func adresse(de p: MKPlacemark) -> String {
        [p.thoroughfare, p.locality, p.administrativeArea, p.country]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
    }
}
