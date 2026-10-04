import Foundation
import MapKit

struct ErreurService: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func charger(_ requete: URLRequest, service: String) async throws -> Data {
    let (donnees, reponse) = try await URLSession.shared.data(for: requete)
    guard let http = reponse as? HTTPURLResponse else { throw ErreurService(message: "\(service) : réponse invalide.") }
    switch http.statusCode {
    case 200..<300: return donnees
    case 400, 401, 403: throw ErreurService(message: "\(service) a refusé la clé (code \(http.statusCode)). Vérifie-la dans Réglages, et que l'API est bien activée.")
    case 429: throw ErreurService(message: "\(service) : trop de requêtes, réessaie dans un instant.")
    default: throw ErreurService(message: "\(service) a répondu avec le code \(http.statusCode).")
    }
}

// MARK: - Google Places (API « New »)

enum SourceGoogle {
    struct Reponse: Decodable { var places: [Lieu]? }
    struct Lieu: Decodable {
        struct Texte: Decodable { var text: String? }
        struct Position: Decodable { var latitude: Double; var longitude: Double }
        struct Horaires: Decodable { var weekdayDescriptions: [String]? }
        struct Photo: Decodable { var name: String? }
        var id: String?
        var displayName: Texte?
        var formattedAddress: String?
        var location: Position?
        var rating: Double?
        var userRatingCount: Int?
        var primaryTypeDisplayName: Texte?
        var editorialSummary: Texte?
        var regularOpeningHours: Horaires?
        var photos: [Photo]?
        var googleMapsUri: String?
        var websiteUri: String?
        var priceLevel: String?
    }

    private static let champs = [
        "places.id", "places.displayName", "places.formattedAddress", "places.location", "places.rating",
        "places.userRatingCount", "places.primaryTypeDisplayName", "places.editorialSummary",
        "places.regularOpeningHours.weekdayDescriptions", "places.photos.name", "places.googleMapsUri",
        "places.websiteUri", "places.priceLevel",
    ].joined(separator: ",")

    /// Avec un mot-clé (titre de l'étape…), on interroge d'abord Google sur ce mot-clé, puis sur les classiques du coin.
    static func chercher(type: TypeLieu, autour lieu: String, centre: CLLocationCoordinate2D, mots: String, cle: String) async throws -> [LieuPropose] {
        let generique = type == .restaurant ? "meilleurs restaurants à \(lieu)" : "choses à voir et à faire à \(lieu)"
        var requetes: [(texte: String, taille: Int)] = [(generique, 20)]
        if !mots.isEmpty { requetes.insert(("\(mots) \(lieu)", 10), at: 0) }

        let groupes = try await withThrowingTaskGroup(of: (Int, [LieuPropose]).self) { groupe in
            for (i, r) in requetes.enumerated() {
                groupe.addTask { (i, try await recherche(texte: r.texte, taille: r.taille, type: type, centre: centre, cle: cle)) }
            }
            var sortie: [(Int, [LieuPropose])] = []
            for try await r in groupe { sortie.append(r) }
            return sortie.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return groupes.reduce(into: [LieuPropose]()) { cumul, liste in
            for l in liste where !cumul.contains(where: { $0.idGoogle == l.idGoogle }) { cumul.append(l) }
        }
    }

    private static func recherche(texte: String, taille: Int, type: TypeLieu, centre: CLLocationCoordinate2D, cle: String) async throws -> [LieuPropose] {
        var requete = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(cle, forHTTPHeaderField: "X-Goog-Api-Key")
        requete.setValue(champs, forHTTPHeaderField: "X-Goog-FieldMask")
        let corps: [String: Any] = [
            "textQuery": texte,
            "languageCode": "fr",
            "pageSize": taille,
            "locationBias": ["circle": ["center": ["latitude": centre.latitude, "longitude": centre.longitude], "radius": 20_000.0]],
        ]
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        let donnees = try await charger(requete, service: "Google Places")
        return try convertir(donnees, type: type, cle: cle)
    }

    static func convertir(_ donnees: Data, type: TypeLieu, cle: String) throws -> [LieuPropose] {
        let reponse = try JSONDecoder().decode(Reponse.self, from: donnees)
        return (reponse.places ?? []).compactMap { p in
            guard let nom = p.displayName?.text, let pos = p.location else { return nil }
            var lieu = LieuPropose(nom: nom, adresse: p.formattedAddress ?? "",
                                   coordonnee: CLLocationCoordinate2D(latitude: pos.latitude, longitude: pos.longitude), type: type)
            lieu.genre = p.primaryTypeDisplayName?.text
            lieu.idGoogle = p.id
            lieu.resume = p.editorialSummary?.text
            lieu.horaires = p.regularOpeningHours?.weekdayDescriptions ?? []
            lieu.siteWeb = p.websiteUri.flatMap(URL.init)
            lieu.prix = p.priceLevel.flatMap(prix)
            if let note = p.rating, let n = p.userRatingCount {
                lieu.avis.append(AvisSource(source: .google, note: note, nombre: n, lien: p.googleMapsUri.flatMap(URL.init)))
            }
            lieu.photos = (p.photos ?? []).prefix(5).compactMap { photo in
                guard let nom = photo.name else { return nil }
                return URL(string: "https://places.googleapis.com/v1/\(nom)/media?maxHeightPx=600&key=\(cle)")
            }
            return lieu
        }
    }

    private static func prix(_ niveau: String) -> String? {
        switch niveau {
        case "PRICE_LEVEL_FREE": "Gratuit"
        case "PRICE_LEVEL_INEXPENSIVE": "€"
        case "PRICE_LEVEL_MODERATE": "€€"
        case "PRICE_LEVEL_EXPENSIVE": "€€€"
        case "PRICE_LEVEL_VERY_EXPENSIVE": "€€€€"
        default: nil
        }
    }
}

// MARK: - Tripadvisor Content API

enum SourceTripadvisor {
    private static let base = "https://api.content.tripadvisor.com/api/v1/location"

    /// Les champs numériques arrivent tantôt en texte, tantôt en nombre.
    struct Souple: Decodable {
        var texte: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { texte = s }
            else if let d = try? c.decode(Double.self) { texte = String(d) }
            else { texte = "" }
        }
        var double: Double? { Double(texte) }
        var entier: Int? { Int(texte) ?? double.map(Int.init) }
    }

    struct Proches: Decodable {
        struct Entree: Decodable { var location_id: String?; var name: String? }
        var data: [Entree]?
    }

    struct Details: Decodable {
        struct Adresse: Decodable { var address_string: String? }
        struct Horaires: Decodable { var weekday_text: [String]? }
        struct Nom: Decodable { var name: String? }
        struct Classement: Decodable { var ranking_string: String? }
        var location_id: String?
        var name: String?
        var description: String?
        var web_url: String?
        var website: String?
        var address_obj: Adresse?
        var latitude: Souple?
        var longitude: Souple?
        var rating: Souple?
        var num_reviews: Souple?
        var hours: Horaires?
        var price_level: String?
        var subcategory: [Nom]?
        var ranking_data: Classement?
    }

    struct Photos: Decodable {
        struct Entree: Decodable {
            struct Tailles: Decodable {
                struct Image: Decodable { var url: String? }
                var large: Image?
                var medium: Image?
            }
            var images: Tailles?
        }
        var data: [Entree]?
    }

    private static func identifiants(_ chemin: String, _ parametres: [URLQueryItem], cle: String) async throws -> [String] {
        var composants = URLComponents(string: "\(base)/\(chemin)")!
        composants.queryItems = [.init(name: "key", value: cle), .init(name: "radius", value: "15"),
                                 .init(name: "radiusUnit", value: "km"), .init(name: "language", value: "fr")] + parametres
        var requete = URLRequest(url: composants.url!)
        requete.setValue("application/json", forHTTPHeaderField: "accept")
        let proches = try JSONDecoder().decode(Proches.self, from: try await charger(requete, service: "Tripadvisor"))
        return (proches.data ?? []).compactMap(\.location_id)
    }

    static func chercher(type: TypeLieu, centre: CLLocationCoordinate2D, mots: String, cle: String) async throws -> [LieuPropose] {
        let categorie = URLQueryItem(name: "category", value: type == .restaurant ? "restaurants" : "attractions")
        let position = URLQueryItem(name: "latLong", value: "\(centre.latitude),\(centre.longitude)")

        // Recherche par mot-clé d'abord (si on en a un), puis les lieux proches.
        var ids: [String] = []
        if !mots.isEmpty {
            ids += (try? await identifiants("search", [.init(name: "searchQuery", value: mots), categorie, position], cle: cle).prefix(5)) ?? []
        }
        for id in try await identifiants("nearby_search", [categorie, position], cle: cle) where !ids.contains(id) { ids.append(id) }

        // Ni note ni avis dans ces listes : une fiche détaillée par lieu, en parallèle.
        return await withTaskGroup(of: (Int, LieuPropose?).self) { groupe in
            for (i, id) in ids.prefix(12).enumerated() {
                groupe.addTask { (i, try? await details(id: id, type: type, cle: cle)) }
            }
            var sortie: [(Int, LieuPropose)] = []
            for await (i, lieu) in groupe { if let lieu { sortie.append((i, lieu)) } }
            return sortie.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func details(id: String, type: TypeLieu, cle: String) async throws -> LieuPropose? {
        var composants = URLComponents(string: "\(base)/\(id)/details")!
        composants.queryItems = [.init(name: "key", value: cle), .init(name: "language", value: "fr"), .init(name: "currency", value: "EUR")]
        var requete = URLRequest(url: composants.url!)
        requete.setValue("application/json", forHTTPHeaderField: "accept")
        return convertir(try await charger(requete, service: "Tripadvisor"), type: type)
    }

    static func convertir(_ donnees: Data, type: TypeLieu) -> LieuPropose? {
        guard let d = try? JSONDecoder().decode(Details.self, from: donnees),
              let nom = d.name, let lat = d.latitude?.double, let lon = d.longitude?.double else { return nil }
        var lieu = LieuPropose(nom: nom, adresse: d.address_obj?.address_string ?? "",
                               coordonnee: CLLocationCoordinate2D(latitude: lat, longitude: lon), type: type)
        lieu.idTripadvisor = d.location_id
        lieu.genre = d.subcategory?.first?.name
        lieu.resume = d.description.flatMap { $0.isEmpty ? nil : $0 }
        lieu.horaires = d.hours?.weekday_text ?? []
        lieu.siteWeb = d.website.flatMap(URL.init)
        lieu.prix = d.price_level
        lieu.classementTripadvisor = d.ranking_data?.ranking_string
        if let note = d.rating?.double, let n = d.num_reviews?.entier {
            lieu.avis.append(AvisSource(source: .tripadvisor, note: note, nombre: n, lien: d.web_url.flatMap(URL.init)))
        }
        return lieu
    }

    static func photos(id: String, cle: String) async -> [URL] {
        var composants = URLComponents(string: "\(base)/\(id)/photos")!
        composants.queryItems = [.init(name: "key", value: cle), .init(name: "language", value: "fr"), .init(name: "limit", value: "5")]
        var requete = URLRequest(url: composants.url!)
        requete.setValue("application/json", forHTTPHeaderField: "accept")
        guard let donnees = try? await charger(requete, service: "Tripadvisor"),
              let photos = try? JSONDecoder().decode(Photos.self, from: donnees) else { return [] }
        return (photos.data ?? []).compactMap { ($0.images?.large?.url ?? $0.images?.medium?.url).flatMap(URL.init) }
    }
}

// MARK: - Plans (sans notes, quand aucune clé n'est renseignée)

enum SourceApple {
    static func chercher(type: TypeLieu, centre: CLLocationCoordinate2D, mots: String) async -> [LieuPropose] {
        let filtre = MKPointOfInterestFilter(including: type == .restaurant
            ? [.restaurant, .cafe, .bakery]
            : [.museum, .park, .nationalPark, .beach, .amusementPark, .zoo, .aquarium, .theater])
        var items: [MKMapItem] = []
        if !mots.isEmpty {
            let r = MKLocalSearch.Request()
            r.naturalLanguageQuery = mots
            r.region = MKCoordinateRegion(center: centre, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
            items += (try? await MKLocalSearch(request: r).start().mapItems) ?? []
        }
        let proches = MKLocalPointsOfInterestRequest(center: centre, radius: 15_000)
        proches.pointOfInterestFilter = filtre
        items += (try? await MKLocalSearch(request: proches).start().mapItems) ?? []
        return items.compactMap { item in
            guard let nom = item.name else { return nil }
            var lieu = LieuPropose(nom: nom, adresse: item.placemark.title ?? "", coordonnee: item.placemark.coordinate, type: type)
            lieu.siteWeb = item.url
            return lieu
        }
    }
}

// MARK: - Fusion et classement

enum Suggestions {
    struct Resultat {
        var lieux: [LieuPropose]
        var avertissements: [String]
        var sansNotes: Bool
    }

    static func chercher(type: TypeLieu, autour lieu: String, centre: CLLocationCoordinate2D, mots: String) async -> Resultat {
        let cleGoogle = Cles.lire(.google), cleTripadvisor = Cles.lire(.tripadvisor)
        async let google: ([LieuPropose], String?) = {
            guard let cle = cleGoogle else { return ([], nil) }
            do { return (try await SourceGoogle.chercher(type: type, autour: lieu, centre: centre, mots: mots, cle: cle), nil) }
            catch { return ([], error.localizedDescription) }
        }()
        async let tripadvisor: ([LieuPropose], String?) = {
            guard let cle = cleTripadvisor else { return ([], nil) }
            do { return (try await SourceTripadvisor.chercher(type: type, centre: centre, mots: mots, cle: cle), nil) }
            catch { return ([], error.localizedDescription) }
        }()
        let ((g, erreurGoogle), (t, erreurTripadvisor)) = await (google, tripadvisor)
        let avertissements = [erreurGoogle, erreurTripadvisor].compactMap { $0 }

        var lieux = fusionner(g, t)
        let sansNotes = lieux.isEmpty
        if sansNotes { lieux = await SourceApple.chercher(type: type, centre: centre, mots: mots) }
        return Resultat(lieux: classer(lieux, mots: mots), avertissements: avertissements, sansNotes: sansNotes)
    }

    private static func simplifier(_ nom: String) -> String {
        nom.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Mots trop courants pour prouver que deux noms désignent le même lieu (dans quelques langues).
    private static let motsBanals: Set<String> = [
        "parc", "park", "parque", "national", "nacional", "musee", "museum", "museo", "restaurant", "restaurante",
        "cafe", "bar", "hotel", "plage", "beach", "playa", "centre", "center", "centro", "de", "du", "des", "la", "le",
        "les", "el", "los", "las", "the", "of", "and", "et", "y", "del", "international", "internacional",
    ]

    private static func motsSignificatifs(_ nom: String) -> Set<String> {
        Set(simplifier(nom).split(separator: " ").map(String.init).filter { $0.count >= 3 && !motsBanals.contains($0) })
    }

    /// Même lieu si les fiches sont proches et que leurs noms se recoupent, même traduits
    /// (« Parc national Manuel Antonio » / « Manuel Antonio National Park »).
    static func memeLieu(_ a: LieuPropose, _ b: LieuPropose) -> Bool {
        let ecart = distance(a.coordonnee, b.coordonnee)
        guard ecart < 250 else { return false }
        let x = simplifier(a.nom), y = simplifier(b.nom)
        if x == y || x.contains(y) || y.contains(x) { return true }
        let communs = motsSignificatifs(a.nom).intersection(motsSignificatifs(b.nom))
        let plusCourt = min(motsSignificatifs(a.nom).count, motsSignificatifs(b.nom).count)
        return !communs.isEmpty && (plusCourt <= 1 || communs.count >= 2 || ecart < 60)
    }

    static func fusionner(_ google: [LieuPropose], _ tripadvisor: [LieuPropose]) -> [LieuPropose] {
        var resultat = google
        for t in tripadvisor {
            if let i = resultat.firstIndex(where: { memeLieu($0, t) }) {
                resultat[i].avis.append(contentsOf: t.avis.filter { a in !resultat[i].avis.contains { $0.source == a.source } })
                resultat[i].idTripadvisor = t.idTripadvisor
                resultat[i].classementTripadvisor = t.classementTripadvisor
                if resultat[i].resume == nil { resultat[i].resume = t.resume }
                if resultat[i].horaires.isEmpty { resultat[i].horaires = t.horaires }
                if resultat[i].siteWeb == nil { resultat[i].siteWeb = t.siteWeb }
                if resultat[i].prix == nil { resultat[i].prix = t.prix }
            } else {
                resultat.append(t)
            }
        }
        return resultat
    }

    private static let motsVides: Set<String> = ["de", "du", "des", "la", "le", "les", "l", "d", "un", "une", "au", "aux", "en", "et", "a", "el", "los", "las", "del", "y", "the", "of", "and", "in", "at", "to"]

    /// Mots d'une recherche qui portent du sens (on garde « musée », « plage »… contrairement à la fusion des doublons).
    private static func motsDeRecherche(_ texte: String) -> Set<String> {
        Set(simplifier(texte).split(separator: " ").map(String.init).filter { !motsVides.contains($0) && !$0.isEmpty })
    }

    /// Part des mots recherchés que l'on retrouve dans le nom, le genre ou l'adresse du lieu (0 à 1).
    static func correspondance(_ lieu: LieuPropose, mots: String) -> Double {
        let voulus = motsDeRecherche(mots)
        guard !voulus.isEmpty else { return 0 }
        let nom = motsDeRecherche(lieu.nom)
        let autour = motsDeRecherche([lieu.genre, lieu.adresse].compactMap { $0 }.joined(separator: " "))
        let dansNom = Double(voulus.intersection(nom).count)
        let ailleurs = Double(voulus.intersection(autour).subtracting(nom).count)
        return (dansNom + 0.5 * ailleurs) / Double(voulus.count)
    }

    /// Les lieux qui correspondent au titre ou au lieu de l'étape d'abord, puis la meilleure note.
    static func classer(_ lieux: [LieuPropose], mots: String = "") -> [LieuPropose] {
        let correspondances = lieux.map { correspondance($0, mots: mots) }
        return lieux.enumerated().sorted { a, b in
            let (ca, cb) = (correspondances[a.offset] > 0.34, correspondances[b.offset] > 0.34)
            if ca != cb { return ca }
            if ca, correspondances[a.offset] != correspondances[b.offset] { return correspondances[a.offset] > correspondances[b.offset] }
            switch (a.element.score, b.element.score) {
            case let (x?, y?): return x != y ? x > y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }
}
