import Foundation
import SwiftData

enum TypeReservation: String, Codable, CaseIterable, Identifiable {
    case vol, train, hebergement, voiture, activite, restaurant, autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .vol: "Vol"
        case .train: "Train, bus, bateau"
        case .hebergement: "Hébergement"
        case .voiture: "Location de voiture"
        case .activite: "Activité, billet"
        case .restaurant: "Restaurant"
        case .autre: "Autre"
        }
    }

    var symbole: String {
        switch self {
        case .vol: "airplane"
        case .train: "tram.fill"
        case .hebergement: "bed.double.fill"
        case .voiture: "car.fill"
        case .activite: "ticket.fill"
        case .restaurant: "fork.knife"
        case .autre: "doc.text.fill"
        }
    }

    /// Catégorie de l'étape créée dans l'itinéraire.
    var categorieEtape: CategorieEtape {
        switch self {
        case .vol, .train, .voiture: .transport
        case .hebergement: .hebergement
        case .activite: .activite
        case .restaurant: .repas
        case .autre: .autre
        }
    }
}

@Model
final class Reservation {
    var type: TypeReservation
    var titre: String
    var fournisseur: String
    var numeroConfirmation: String
    var debut: Date
    var fin: Date?
    var lieu: String
    var prix: Double?
    var devise: String
    var notes: String
    var ajouteeAItineraire: Bool
    /// Fuseaux (identifiants) des heures de début et de fin, s'ils diffèrent de celui du voyage.
    var fuseauDebutId: String?
    var fuseauFinId: String?
    var creeLe: Date
    var uid: String = ""
    var voyage: Voyage?
    @Relationship(deleteRule: .cascade, inverse: \Document.reservation)
    var documents: [Document] = []

    init(type: TypeReservation = .vol, debut: Date = .now) {
        self.type = type
        self.titre = ""
        self.fournisseur = ""
        self.numeroConfirmation = ""
        self.debut = debut
        self.fin = nil
        self.lieu = ""
        self.prix = nil
        self.devise = Locale.current.currency?.identifier ?? "EUR"
        self.notes = ""
        self.ajouteeAItineraire = false
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}

@Model
final class Document {
    var nom: String
    var extensionFichier: String
    @Attribute(.externalStorage) var donnees: Data
    var creeLe: Date
    var uid: String = ""
    var voyage: Voyage?
    var reservation: Reservation?
    /// Renseigné pour les photos rapatriées d'un lieu proposé.
    var etape: Etape?
    /// Voyageur à qui appartient le document (passeport, assurance…), et son type et sa date de validité.
    var membreUID: String?
    var typeBrut: String?
    var expireLe: Date?
    /// Texte libre : pour un plan de métro, sa source, son auteur et sa licence.
    var notes: String?

    init(nom: String, extensionFichier: String, donnees: Data) {
        self.nom = nom
        self.extensionFichier = extensionFichier
        self.donnees = donnees
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var estImage: Bool { ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(extensionFichier.lowercased()) }
    var symbole: String { extensionFichier.lowercased() == "pdf" ? "doc.richtext.fill" : (estImage ? "photo.fill" : "doc.fill") }
}
