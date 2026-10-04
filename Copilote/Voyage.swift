import Foundation
import SwiftData

@Model
final class Voyage {
    var titre: String
    var destination: String
    var debut: Date
    var fin: Date
    var notes: String = ""
    /// Codes ISO des pays visités (FR, IT…), dans l'ordre choisi.
    var pays: [String] = []
    var creeLe: Date
    /// Identifiant stable, commun à tous les appareils (synchronisation iCloud).
    var uid: String = ""
    /// Vide si le voyage est le mien ; sinon, propriétaire iCloud du voyage reçu.
    var zoneProprietaire: String = ""
    var partage: Bool = false
    var participantsCloud: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \Membre.voyage)
    var membres: [Membre] = []
    @Relationship(deleteRule: .cascade, inverse: \Etape.voyage)
    var etapes: [Etape] = []
    @Relationship(deleteRule: .cascade, inverse: \JourVoyage.voyage)
    var infosJours: [JourVoyage] = []
    @Relationship(deleteRule: .cascade, inverse: \Depense.voyage)
    var depenses: [Depense] = []
    @Relationship(deleteRule: .cascade, inverse: \Reservation.voyage)
    var reservations: [Reservation] = []
    @Relationship(deleteRule: .cascade, inverse: \Document.voyage)
    var documents: [Document] = []

    init(titre: String, destination: String = "", debut: Date = .now, fin: Date = .now.addingTimeInterval(7 * 86_400)) {
        self.titre = titre
        self.destination = destination
        self.debut = debut
        self.fin = fin
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var estRecu: Bool { !zoneProprietaire.isEmpty }

    /// Chaque jour du voyage, du départ au retour.
    var jours: [Date] {
        let cal = Calendar.current
        let premier = cal.startOfDay(for: debut)
        return (0..<nombreDeJours).compactMap { cal.date(byAdding: .day, value: $0, to: premier) }
    }

    var nombreDeJours: Int {
        let jours = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: debut), to: Calendar.current.startOfDay(for: fin)).day ?? 0
        return max(jours + 1, 1)
    }
}

extension Voyage {
    /// Étapes d'un jour dans l'ordre choisi en les glissant ; à défaut, par heure puis par ordre de création.
    func etapes(du jour: Date) -> [Etape] {
        etapes
            .filter { !$0.apresJour && ($0.jour.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? false) }
            .sorted { ($0.ordre, $0.heure ?? .distantFuture, $0.creeLe) < ($1.ordre, $1.heure ?? .distantFuture, $1.creeLe) }
    }

    /// Hébergements de la nuit qui suit `jour` (entre ce jour et le suivant).
    func hebergements(apres jour: Date) -> [Etape] {
        etapes
            .filter { $0.apresJour && ($0.jour.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? false) }
            .sorted { ($0.ordre, $0.creeLe) < ($1.ordre, $1.creeLe) }
    }

    /// Place l'étape (un hébergement) entre `jour` et le suivant.
    func placerEntreJours(_ etape: Etape, apres jour: Date) {
        let ancien = etape.apresJour ? nil : etape.jour
        // Un seul hébergement par nuit : l'éventuel occupant repart dans « Étapes à placer ».
        for autre in hebergements(apres: jour) where autre !== etape { retirerDuJour(autre) }
        etape.apresJour = true
        etape.jour = Calendar.current.startOfDay(for: jour)
        etape.ordre = (hebergements(apres: jour).filter { $0 !== etape }.map(\.ordre).max() ?? -1) + 1
        if let ancien { for (i, e) in etapes(du: ancien).enumerated() { e.ordre = Double(i) } }
    }

    /// Étapes préparées sans jour, dans l'ordre où on les a rangées.
    var etapesSansJour: [Etape] {
        etapes.filter { $0.jour == nil }.sorted { ($0.ordre, $0.creeLe) < ($1.ordre, $1.creeLe) }
    }

    /// Étapes dont le transport (vers l'étape suivante) serait perdu si on déplaçait `etape` à cet endroit
    /// (`jour` nil : on la retire de son jour).
    func transportsPerdus(deplacant etape: Etape, vers jour: Date?, avant cible: Etape?) -> [Etape] {
        func suivantes(_ liste: [Etape]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: zip(liste, liste.dropFirst()).map { ($0.uid, $1.uid) })
        }
        var avant: [Etape] = [], apres: [Etape] = []
        var apresSuivantes: [String: String] = [:], avantSuivantes: [String: String] = [:]
        func ajouterJour(_ j: Date, insertion: Bool) {
            let actuelle = etapes(du: j)
            avantSuivantes.merge(suivantes(actuelle)) { a, _ in a }
            var liste = actuelle.filter { $0 !== etape }
            if insertion {
                let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
                liste.insert(etape, at: index)
            }
            apresSuivantes.merge(suivantes(liste)) { a, _ in a }
            avant += actuelle; apres += liste
        }
        if let ancien = etape.jour { ajouterJour(ancien, insertion: false) }
        if let jour, !(etape.jour.map { Calendar.current.isDate($0, inSameDayAs: jour) } ?? false) { ajouterJour(jour, insertion: true) }
        else if let jour, etape.jour != nil {
            // Même jour : on remplace la simulation sans insertion par celle avec insertion.
            avantSuivantes = [:]; apresSuivantes = [:]; avant = []; apres = []
            ajouterJour(jour, insertion: true)
        }
        // Une étape sans jour n'a pas de suivante.
        var concernees = Set(avant.map(\.uid)).union(apres.map(\.uid))
        concernees.insert(etape.uid)
        return etapes.filter { concernees.contains($0.uid) && $0.transport != nil && avantSuivantes[$0.uid] != apresSuivantes[$0.uid] }
    }

    /// Enlève l'étape de son jour : elle redevient « à placer », sans jour ni horaires.
    @discardableResult
    func retirerDuJour(_ etape: Etape) -> Bool {
        guard let ancienJour = etape.jour, etapes.contains(where: { $0 === etape }) else { return false }
        etape.jour = nil
        etape.apresJour = false
        etape.heure = nil
        etape.heureFin = nil
        etape.ordre = (etapesSansJour.filter { $0 !== etape }.map(\.ordre).max() ?? -1) + 1
        for (i, e) in etapes(du: ancienJour).enumerated() { e.ordre = Double(i) }
        return true
    }

    /// Place l'étape à son nouvel endroit (dans le même jour ou un autre), juste avant `cible` ou en fin de journée,
    /// puis renumérote les journées touchées. Renvoie false si rien ne change.
    @discardableResult
    func deplacer(_ etape: Etape, vers jour: Date, avant cible: Etape?) -> Bool {
        guard cible !== etape, etapes.contains(where: { $0 === etape }) else { return false }
        let cal = Calendar.current
        let ancienJour = etape.jour
        var liste = etapes(du: jour).filter { $0 !== etape }
        let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
        liste.insert(etape, at: index)
        etape.apresJour = false
        etape.jour = cal.startOfDay(for: jour)
        for (i, e) in liste.enumerated() { e.ordre = Double(i) }
        if let ancienJour, !cal.isDate(ancienJour, inSameDayAs: jour) {
            for (i, e) in etapes(du: ancienJour).enumerated() { e.ordre = Double(i) }
        }
        return true
    }

    /// Étapes d'un jour dont l'heure précède celle d'une étape placée avant elle (ordre et horaires en contradiction).
    /// Associe l'identifiant de l'étape à l'heure de l'étape précédente qui la contredit.
    /// Les étapes sans heure ne comptent pas.
    func etapesAuxHorairesIncoherents(du jour: Date) -> [String: Date] {
        let cal = Calendar.current
        func minutes(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        var resultat: [String: Date] = [:]
        var plusTardive: Date?
        for etape in etapes(du: jour) {
            guard let heure = etape.heure else { continue }
            if let reference = plusTardive, minutes(heure) < minutes(reference) {
                resultat[etape.uid] = reference
            } else {
                plusTardive = heure
            }
        }
        return resultat
    }

    /// Étapes dont l'heure de début tombe avant la fin d'une étape placée avant elle (les deux se chevauchent).
    /// Associe l'identifiant de l'étape à l'étape précédente qu'elle chevauche.
    func etapesEnChevauchement(du jour: Date) -> [String: Etape] {
        let cal = Calendar.current
        func minutes(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        var resultat: [String: Etape] = [:]
        var precedentes: [Etape] = []
        for etape in etapes(du: jour) {
            guard let debut = etape.heure else { continue }
            if let autre = precedentes.last(where: { p in
                guard let d = p.heure, let f = p.heureFin else { return false }
                return minutes(debut) >= minutes(d) && minutes(debut) < minutes(f)
            }) {
                resultat[etape.uid] = autre
            }
            precedentes.append(etape)
        }
        return resultat
    }

    /// Remet les étapes d'un jour dans l'ordre des heures (celles sans heure à la fin).
    func trierParHeure(_ jour: Date) {
        let triees = etapes(du: jour).sorted { ($0.heure ?? .distantFuture, $0.creeLe) < ($1.heure ?? .distantFuture, $1.creeLe) }
        for (i, e) in triees.enumerated() { e.ordre = Double(i) }
    }

    /// Position à donner à une nouvelle étape pour qu'elle arrive en fin de journée.
    func prochainOrdre(du jour: Date) -> Double {
        (etapes(du: jour).map(\.ordre).max() ?? 0) + 1
    }
}
