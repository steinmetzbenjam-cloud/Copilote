import Foundation
import SwiftData
import CoreLocation

/// Un lieu de référence pour une journée : un pays, une région, une ville ou un endroit précis.
struct LieuReference: Codable, Hashable, Identifiable {
    var id = UUID()
    var nom: String
    var detail = ""
    var latitude: Double
    var longitude: Double
    var codePays: String?
    var estPays = false

    var coordonnee: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// « 🇨🇷 Costa Rica » pour un pays, sinon le nom tel quel.
    var etiquette: String {
        if estPays, let code = codePays, let pays = Pays.avec(code: code) { return "\(pays.drapeau) \(nom)" }
        return nom
    }
}

/// Informations propres à une journée du voyage : titre, lieux autour desquels elle se déroule, notes.
@Model
final class JourVoyage {
    var date: Date
    var titre: String
    var notes: String
    var lieux: [LieuReference] = []
    var uid: String = ""
    var creeLe: Date
    var voyage: Voyage?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.titre = ""
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var estVide: Bool { titre.trimmingCharacters(in: .whitespaces).isEmpty && notes.trimmingCharacters(in: .whitespaces).isEmpty && lieux.isEmpty }
}

extension Voyage {
    func infos(du jour: Date) -> JourVoyage? {
        infosJours.first { Calendar.current.isDate($0.date, inSameDayAs: jour) }
    }
}
