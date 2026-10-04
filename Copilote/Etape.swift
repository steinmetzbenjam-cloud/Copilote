import Foundation
import SwiftData
import CoreLocation

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
    /// Heure de fin (facultative).
    var heureFin: Date?
    var categorie: CategorieEtape
    var notes: String
    var latitude: Double?
    var longitude: Double?
    // Infos récupérées via les suggestions (Google, Tripadvisor).
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
    var creeLe: Date
    var uid: String = ""
    /// Position dans la journée (réglée en glissant les étapes).
    var ordre: Double = 0
    var voyage: Voyage?
    @Relationship(deleteRule: .cascade, inverse: \Document.etape)
    var photos: [Document] = []

    init(titre: String, jour: Date, categorie: CategorieEtape = .visite) {
        self.titre = titre
        self.lieu = ""
        self.jour = Calendar.current.startOfDay(for: jour)
        self.heure = nil
        self.categorie = categorie
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}

extension Etape {
    var aDesInfosDeLieu: Bool {
        resume != nil || horaires != nil || photoURL != nil || !photos.isEmpty || noteGoogle != nil || noteTripadvisor != nil || siteWeb != nil
    }

    /// Reprend dans l'étape ce que l'on sait d'un lieu proposé : nom du lieu proposé (qui remplace le titre saisi), adresse, position, catégorie, et tout le reste dans les notes.
    func appliquer(_ lieu: LieuPropose) {
        titre = lieu.nom
        self.lieu = lieu.adresse.isEmpty ? lieu.nom : "\(lieu.nom), \(lieu.adresse)"
        latitude = lieu.coordonnee.latitude
        longitude = lieu.coordonnee.longitude
        categorie = lieu.type == .restaurant ? .repas : .visite
        resume = lieu.resume
        horaires = lieu.horaires.isEmpty ? nil : lieu.horaires.joined(separator: "\n")
        let google = lieu.avis(de: .google), tripadvisor = lieu.avis(de: .tripadvisor)
        noteGoogle = google?.note
        avisGoogle = google?.nombre
        lienGoogle = google?.lien?.absoluteString
        noteTripadvisor = tripadvisor?.note
        avisTripadvisor = tripadvisor?.nombre
        lienTripadvisor = tripadvisor?.lien?.absoluteString
        siteWeb = lieu.siteWeb?.absoluteString
        ajouterAuxNotes(Self.notes(pour: lieu))
    }

    /// Ajoute un bloc aux notes sans écraser ce qui y est déjà, et sans le répéter si on valide deux fois le même lieu.
    private func ajouterAuxNotes(_ bloc: String) {
        let entete = bloc.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? bloc
        guard !notes.contains(entete) else { return }
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? bloc : notes + "\n\n———\n\n" + bloc
    }

    /// Fiche texte d'un lieu : description, notes des avis, horaires, adresse, liens.
    static func notes(pour lieu: LieuPropose) -> String {
        func note(_ a: AvisSource) -> String {
            "\(a.source.rawValue) : \(a.note.formatted(.number.precision(.fractionLength(1))))/5 (\(a.nombre.formatted()) avis)"
        }
        var lignes = ["📍 \(lieu.nom)"]
        let genre = [lieu.genre, lieu.prix].compactMap { $0 }.joined(separator: " · ")
        if !genre.isEmpty { lignes.append(genre) }
        if let resume = lieu.resume, !resume.isEmpty { lignes += ["", resume] }
        if !lieu.avis.isEmpty { lignes += ["", "Avis"] + lieu.avis.map(note) }
        if let classement = lieu.classementTripadvisor { lignes.append(classement) }
        if !lieu.horaires.isEmpty { lignes += ["", "Horaires"] + lieu.horaires }
        if !lieu.adresse.isEmpty { lignes += ["", "Adresse : \(lieu.adresse)"] }
        var liens: [String] = []
        if let site = lieu.siteWeb { liens.append("Site : \(site.absoluteString)") }
        for a in lieu.avis { if let url = a.lien { liens.append("\(a.source.rawValue) : \(url.absoluteString)") } }
        liens.append("Vidéos : \(lienVideos(pour: lieu.nom).absoluteString)")
        return (lignes + [""] + liens).joined(separator: "\n")
    }

    /// Les API de Google et Tripadvisor ne fournissent pas de vidéos : on renvoie vers une recherche.
    static func lienVideos(pour nom: String) -> URL {
        var composants = URLComponents(string: "https://www.youtube.com/results")!
        composants.queryItems = [URLQueryItem(name: "search_query", value: nom)]
        return composants.url!
    }

    var coordonnee: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
