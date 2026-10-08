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
    /// Mode d'utilisation (`ModeVoyage`) : propre à cet appareil, non synchronisé.
    var modeBrut: String = ModeVoyage.preparation.rawValue
    var participantsCloud: [String] = []
    /// Transport du lieu de départ à la première étape, et de la dernière étape au retour (JSON de `Transport`).
    /// Monnaie locale (code ISO, ex. CRC) et ce que vaut 1 € dans cette monnaie.
    var deviseLocale: String?
    var tauxChange: Double?
    /// Fuseau dans lequel tous les horaires du voyage sont lus (identifiant, ex. « Europe/Paris »), quel que soit le fuseau de l'appareil.
    var fuseauReferenceId: String?
    var transportAllerJSON: String?
    var transportRetourJSON: String?
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
    @Relationship(deleteRule: .cascade, inverse: \Commentaire.voyage)
    var commentaires: [Commentaire] = []
    @Relationship(deleteRule: .cascade, inverse: \AvisEtape.voyage)
    var avisEtapes: [AvisEtape] = []
    @Relationship(deleteRule: .cascade, inverse: \Famille.voyage)
    var fichesFamilles: [Famille] = []
    @Relationship(deleteRule: .cascade, inverse: \Sondage.voyage)
    var sondages: [Sondage] = []
    @Relationship(deleteRule: .cascade, inverse: \VoteSondage.voyage)
    var votes: [VoteSondage] = []

    init(titre: String, destination: String = "", debut: Date = .now, fin: Date = .now.addingTimeInterval(7 * 86_400)) {
        self.titre = titre
        self.destination = destination
        self.debut = debut
        self.fin = fin
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }

    var mode: ModeVoyage {
        get { ModeVoyage(rawValue: modeBrut) ?? .preparation }
        set { modeBrut = newValue.rawValue }
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

    /// Nuit sans hébergement : la dernière étape du jour et la première du lendemain, entre lesquelles on peut prévoir un transport.
    func transportDeNuit(apres jour: Date) -> (depart: Etape, arrivee: Etape)? {
        guard hebergements(apres: jour).isEmpty else { return nil }
        let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
        guard let depart = etapes(du: jour).last, let arrivee = etapes(du: lendemain).first else { return nil }
        return (depart, arrivee)
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

    /// Les étapes de chaque jour, puis l'hébergement de la nuit qui suit : la chaîne le long de laquelle on se déplace.
    /// Les transports relient deux éléments consécutifs, et l'hébergement à la première étape du lendemain.
    private struct Chaine {
        var jours: [[Etape]]
        var nuits: [Etape?]

        var suivantes: [String: String] {
            var r: [String: String] = [:]
            for i in jours.indices {
                let suite = jours[i] + (nuits[i].map { [$0] } ?? [])
                for (a, b) in zip(suite, suite.dropFirst()) { r[a.uid] = b.uid }
                if let h = nuits[i], i + 1 < jours.count, let premiere = jours[i + 1].first { r[h.uid] = premiere.uid }
            }
            return r
        }
    }

    /// Étape suivante pour le transport : la suivante du jour, l'hébergement après la dernière, la première du lendemain après l'hébergement.
    func suivante(de etape: Etape) -> Etape? {
        guard let jour = etape.jour else { return nil }
        let cal = Calendar.current
        if etape.apresJour {
            let lendemain = cal.date(byAdding: .day, value: 1, to: jour) ?? jour
            return etapes(du: lendemain).first
        }
        let liste = etapes(du: jour)
        guard let i = liste.firstIndex(where: { $0 === etape }) else { return nil }
        return i + 1 < liste.count ? liste[i + 1] : hebergements(apres: jour).first
    }

    /// Élément qui précède `etape` pour le transport (celui qui porte le transport pour y arriver) : l'inverse de `suivante(de:)`,
    /// avec en plus, sans hôtel la veille, la dernière étape de la veille.
    func precedente(de etape: Etape) -> Etape? {
        guard let jour = etape.jour else { return nil }
        let cal = Calendar.current
        if etape.apresJour { return etapes(du: jour).last }
        let liste = etapes(du: jour)
        guard let i = liste.firstIndex(where: { $0 === etape }) else { return nil }
        if i > 0 { return liste[i - 1] }
        let veille = cal.date(byAdding: .day, value: -1, to: jour) ?? jour
        return hebergements(apres: veille).first ?? etapes(du: veille).last
    }

    /// Étapes dont le transport serait perdu si on déplaçait `etape` à cet endroit
    /// (`jour` nil : on la retire de son jour ; `nuit` : on la place dans la nuit qui suit `jour`).
    func transportsPerdus(deplacant etape: Etape, vers jour: Date?, avant cible: Etape?, nuit: Bool = false) -> [Etape] {
        let cal = Calendar.current
        let avant = Chaine(jours: jours.map { etapes(du: $0) }, nuits: jours.map { hebergements(apres: $0).first })
        var apres = avant
        for i in apres.jours.indices {
            apres.jours[i].removeAll { $0 === etape }
            if apres.nuits[i] === etape { apres.nuits[i] = nil }
        }
        if let jour, let i = jours.firstIndex(where: { cal.isDate($0, inSameDayAs: jour) }) {
            if nuit {
                apres.nuits[i] = etape
            } else {
                let index = cible.flatMap { c in apres.jours[i].firstIndex { $0 === c } } ?? apres.jours[i].count
                apres.jours[i].insert(etape, at: index)
            }
        }
        let a = avant.suivantes, b = apres.suivantes
        return etapes.filter { $0.transport != nil && a[$0.uid] != b[$0.uid] }
    }

    /// Enlève l'étape de son jour : elle redevient « à placer », sans jour ni horaires.
    @discardableResult
    func retirerDuJour(_ etape: Etape) -> Bool {
        guard let ancienJour = etape.jour, etapes.contains(where: { $0 === etape }) else { return false }
        etape.jour = nil
        etape.apresJour = false
        etape.transport = nil
        etape.heure = nil
        etape.heureFin = nil
        etape.ordre = (etapesSansJour.filter { $0 !== etape }.map(\.ordre).max() ?? -1) + 1
        for (i, e) in etapes(du: ancienJour).enumerated() { e.ordre = Double(i) }
        return true
    }

    /// Jour dont la nuit reçoit un hébergement lâché sur `jour` : la nuit qui suit, ou celle d'avant si c'est le dernier jour.
    func jourDeNuit(pourDepotSur jour: Date) -> Date {
        let cal = Calendar.current
        let jours = self.jours
        guard jours.count > 1, let dernier = jours.last, cal.isDate(dernier, inSameDayAs: jour) else { return jour }
        return jours[jours.count - 2]
    }

    /// Étapes dont le jour n'est plus dans les dates du voyage : elles repartent dans « À placer ».
    func rangerEtapesHorsDates() {
        let cal = Calendar.current
        let jours = self.jours
        for etape in etapes {
            guard let jour = etape.jour, !jours.contains(where: { cal.isDate($0, inSameDayAs: jour) }) else { continue }
            _ = retirerDuJour(etape)
        }
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
