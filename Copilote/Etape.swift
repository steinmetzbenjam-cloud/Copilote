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
        resume != nil || horaires != nil || photoURL != nil || noteGoogle != nil || noteTripadvisor != nil || siteWeb != nil
    }

    /// Reprend dans l'étape ce que l'on sait d'un lieu proposé.
    func appliquer(_ lieu: LieuPropose) {
        if titre.trimmingCharacters(in: .whitespaces).isEmpty { titre = lieu.nom }
        self.lieu = lieu.adresse.isEmpty ? lieu.nom : "\(lieu.nom), \(lieu.adresse)"
        latitude = lieu.coordonnee.latitude
        longitude = lieu.coordonnee.longitude
        categorie = lieu.type == .restaurant ? .repas : .visite
        resume = lieu.resume
        horaires = lieu.horaires.isEmpty ? nil : lieu.horaires.joined(separator: "\n")
        photoURL = lieu.photos.first?.absoluteString
        let google = lieu.avis(de: .google), tripadvisor = lieu.avis(de: .tripadvisor)
        noteGoogle = google?.note
        avisGoogle = google?.nombre
        lienGoogle = google?.lien?.absoluteString
        noteTripadvisor = tripadvisor?.note
        avisTripadvisor = tripadvisor?.nombre
        lienTripadvisor = tripadvisor?.lien?.absoluteString
        siteWeb = lieu.siteWeb?.absoluteString
    }

    var coordonnee: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
