import Foundation
import SwiftData
import CoreLocation

/// Une étape gardée en favori, avec son pays : elle revient dans les étapes à placer de chaque nouveau voyage dans ce pays.
/// On garde ce qui décrit le lieu (nom, adresse, position, infos, notes), pas ce qui tient au voyage (jour, horaires, prix, transport).
struct EtapeFavorite: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    /// Code ISO du pays (FR, JP…).
    var pays: String
    var ajouteeLe = Date.now
    var titre: String
    var lieu: String
    var categorie: CategorieEtape
    var duree: Double?
    var notes: String
    var latitude: Double?
    var longitude: Double?
    var resume: String?
    var horaires: String?
    var photoURL: String?
    var noteGoogle: Double?
    var avisGoogle: Int?
    var lienGoogle: String?
    var noteTripadvisor: Double?
    var avisTripadvisor: Int?
    var lienTripadvisor: String?
    var siteWeb: String?

    init(_ etape: Etape, pays: String) {
        self.pays = pays
        titre = etape.titre
        lieu = etape.lieu
        categorie = etape.categorie
        duree = etape.duree
        notes = etape.notes
        latitude = etape.latitude
        longitude = etape.longitude
        resume = etape.resume
        horaires = etape.horaires
        photoURL = etape.photoURL
        noteGoogle = etape.noteGoogle
        avisGoogle = etape.avisGoogle
        lienGoogle = etape.lienGoogle
        noteTripadvisor = etape.noteTripadvisor
        avisTripadvisor = etape.avisTripadvisor
        lienTripadvisor = etape.lienTripadvisor
        siteWeb = etape.siteWeb
    }

    /// Une nouvelle étape à placer (sans jour), reprise de ce favori.
    func etape() -> Etape {
        let e = Etape(titre: titre, jour: nil, categorie: categorie)
        e.lieu = lieu
        e.duree = duree
        e.notes = notes
        e.latitude = latitude; e.longitude = longitude
        e.resume = resume; e.horaires = horaires; e.photoURL = photoURL
        e.noteGoogle = noteGoogle; e.avisGoogle = avisGoogle; e.lienGoogle = lienGoogle
        e.noteTripadvisor = noteTripadvisor; e.avisTripadvisor = avisTripadvisor; e.lienTripadvisor = lienTripadvisor
        e.siteWeb = siteWeb
        return e
    }
}

/// Les étapes favorites, rangées par pays. Gardées sur l'appareil et partagées entre l'iPhone et le Mac
/// par le stockage clé-valeur d'iCloud (même compte iCloud) : la dernière modification l'emporte.
/// Une étape est reconnue comme favorite à son nom et à sa position : la copie placée dans un autre voyage l'est aussi.
@MainActor @Observable
final class Favoris {
    static let partage = Favoris()

    nonisolated private static let cle = "etapesFavorites"
    /// Vrai une fois les favoris de cet appareil réunis à ceux d'iCloud : ensuite, iCloud fait foi.
    private static let cleFusion = "etapesFavoritesFusionneesICloud"
    private var nuage: NSUbiquitousKeyValueStore { .default }
    /// La liste vient d'iCloud : inutile de l'y renvoyer.
    private var depuisICloud = false

    private(set) var liste: [EtapeFavorite] = [] {
        didSet {
            guard let donnees = try? JSONEncoder().encode(liste) else { return }
            UserDefaults.standard.set(donnees, forKey: Self.cle)
            if !depuisICloud { nuage.set(donnees, forKey: Self.cle) }
        }
    }

    private init() {
        // La liste de l'appareil ne doit pas écraser celle d'iCloud avant qu'on l'ait lue.
        if let donnees = UserDefaults.standard.data(forKey: Self.cle) {
            depuisICloud = true
            liste = Self.decoder(donnees) ?? []
            depuisICloud = false
        }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let raison = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let cles = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard cles.contains(Favoris.cle) else { return }
            MainActor.assumeIsolated { Favoris.partage.recevoir(premiereSynchro: raison == NSUbiquitousKeyValueStoreInitialSyncChange) }
        }
        nuage.synchronize()
        recevoir(premiereSynchro: false)
    }

    /// Reprend la liste d'iCloud. La première fois sur cet appareil, les deux listes sont réunies, sans doublon.
    private func recevoir(premiereSynchro: Bool) {
        guard let donnees = nuage.data(forKey: Self.cle), let distante = Self.decoder(donnees) else {
            // Rien dans iCloud : la liste de l'appareil y est envoyée.
            if !liste.isEmpty, let donnees = try? JSONEncoder().encode(liste) { nuage.set(donnees, forKey: Self.cle) }
            return
        }
        if premiereSynchro || !UserDefaults.standard.bool(forKey: Self.cleFusion) {
            UserDefaults.standard.set(true, forKey: Self.cleFusion)
            let reunie = distante + liste.filter { l in !distante.contains { $0.id == l.id || Self.memeLieu($0, l) } }
            liste = reunie
        } else if distante != liste {
            depuisICloud = true
            liste = distante
            depuisICloud = false
        }
    }

    private static func decoder(_ donnees: Data) -> [EtapeFavorite]? {
        try? JSONDecoder().decode([EtapeFavorite].self, from: donnees)
    }

    func estFavorite(_ etape: Etape) -> Bool {
        liste.contains { Self.correspond($0, etape) }
    }

    /// Ajoute l'étape aux favoris de son pays, ou l'en retire si elle y est déjà.
    /// Faux si son pays n'a pas pu être trouvé (ni position, ni pays dans le voyage).
    @discardableResult
    func basculer(_ etape: Etape) async -> Bool {
        if estFavorite(etape) {
            liste.removeAll { Self.correspond($0, etape) }
            return true
        }
        guard let pays = await Self.pays(de: etape) else { return false }
        // L'étape a pu être ajoutée pendant la recherche du pays (double appui) : pas de doublon.
        guard !estFavorite(etape) else { return true }
        liste.append(EtapeFavorite(etape, pays: pays))
        return true
    }

    /// Ajoute aux étapes à placer d'un nouveau voyage les favoris de ses pays, dans l'ordre où on les a gardés.
    func ajouter(a voyage: Voyage, contexte: ModelContext) {
        let pays = Set(voyage.pays)
        var ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        for favori in liste where pays.contains(favori.pays) {
            // Déjà dans le voyage (même nom, même endroit) : pas de doublon.
            guard !voyage.etapes.contains(where: { Self.correspond(favori, $0) }) else { continue }
            let e = favori.etape()
            e.ordre = ordre
            ordre += 1
            e.voyage = voyage
            contexte.insert(e)
        }
    }

    // MARK: Reconnaissance

    /// Même nom (sans tenir compte des majuscules ni des accents) et, si les deux sont placés, à moins de 200 m l'un de l'autre.
    private static func correspond(_ favori: EtapeFavorite, _ etape: Etape) -> Bool {
        memeEndroit(favori.titre, favori.latitude, favori.longitude, etape.titre, etape.latitude, etape.longitude)
    }

    /// Deux favoris du même lieu (gardés chacun sur un appareil avant la première synchronisation).
    private static func memeLieu(_ a: EtapeFavorite, _ b: EtapeFavorite) -> Bool {
        a.pays == b.pays && memeEndroit(a.titre, a.latitude, a.longitude, b.titre, b.latitude, b.longitude)
    }

    private static func memeEndroit(_ titreA: String, _ latA: Double?, _ lonA: Double?,
                                    _ titreB: String, _ latB: Double?, _ lonB: Double?) -> Bool {
        let nom = normaliser(titreB)
        guard !nom.isEmpty, normaliser(titreA) == nom else { return false }
        guard let latA, let lonA, let latB, let lonB else { return true }
        return CLLocation(latitude: latA, longitude: lonA).distance(from: CLLocation(latitude: latB, longitude: lonB)) < 200
    }

    private static func normaliser(_ texte: String) -> String {
        texte.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le pays de l'étape : celui de sa position, sinon le premier pays du voyage.
    private static func pays(de etape: Etape) async -> String? {
        let paysDuVoyage = etape.voyage?.pays ?? []
        if let c = etape.coordonnee,
           let code = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first?.isoCountryCode {
            return code
        }
        return paysDuVoyage.first
    }
}
