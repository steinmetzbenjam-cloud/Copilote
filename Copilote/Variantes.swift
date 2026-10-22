import Foundation
import SwiftData

/// Un itinéraire bis : une variante qui quitte l'itinéraire principal après une de ses étapes (ou l'hôtel d'une nuit),
/// passe par ses propres étapes, puis le rejoint plus loin, ou pas.
/// Ses étapes sont des étapes ordinaires, marquées par `Etape.variante` ; chacune porte le transport vers la suivante,
/// la dernière celui vers l'étape où l'itinéraire bis rejoint le principal.
struct Variante: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var nom: String
    /// Étape de l'itinéraire principal d'où part l'itinéraire bis.
    var departUID: String
    /// Étape de l'itinéraire principal où il le rejoint (une étape d'un jour ou l'hôtel d'une nuit) ; nil : il ne le rejoint pas.
    var raccordUID: String?
    /// Transport de l'étape de départ vers la première étape de l'itinéraire bis (vers le raccord s'il n'a pas encore d'étape) :
    /// celui de l'étape de départ reste celui de l'itinéraire principal.
    var transportDepart: Transport?
}

extension LienReservation {
    /// Transport du départ d'un itinéraire bis vers sa première étape.
    static func variante(_ v: Variante) -> String { "variante:\(v.id)" }
}

extension Voyage {
    /// Les itinéraires bis, dans l'ordre de leur création.
    var variantes: [Variante] {
        get { variantesJSON.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([Variante].self, from: $0) } ?? [] }
        set { variantesJSON = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } }
    }

    func variante(_ id: String?) -> Variante? {
        guard let id else { return nil }
        return variantes.first { $0.id == id }
    }

    /// L'itinéraire bis dont fait partie l'étape (nil : elle est sur l'itinéraire principal).
    func variante(de etape: Etape) -> Variante? { variante(etape.variante) }

    func modifierVariante(_ id: String, _ changement: (inout Variante) -> Void) {
        var liste = variantes
        guard let i = liste.firstIndex(where: { $0.id == id }) else { return }
        changement(&liste[i])
        variantes = liste
    }

    /// Les étapes d'un itinéraire bis, jour après jour : les étapes du jour dans l'ordre choisi, puis un éventuel hébergement de nuit.
    func etapes(deVariante id: String) -> [Etape] {
        etapes
            .filter { $0.variante == id && $0.jour != nil }
            .sorted { ($0.jour ?? .distantFuture, $0.apresJour ? 1 : 0, $0.ordre, $0.creeLe) < ($1.jour ?? .distantFuture, $1.apresJour ? 1 : 0, $1.ordre, $1.creeLe) }
    }

    /// Étape de l'itinéraire principal d'où part l'itinéraire bis.
    func depart(de v: Variante) -> Etape? { etapes.first { $0.uid == v.departUID && $0.variante == nil } }

    /// Étape de l'itinéraire principal où l'itinéraire bis le rejoint.
    func raccord(de v: Variante) -> Etape? {
        guard let uid = v.raccordUID else { return nil }
        return etapes.first { $0.uid == uid && $0.variante == nil }
    }

    /// Les itinéraires bis qui partent de cette étape.
    func variantes(partantDe etape: Etape) -> [Variante] { variantes.filter { $0.departUID == etape.uid } }

    /// Itinéraires bis dont l'étape de départ n'est plus dans l'itinéraire principal (supprimée, ou remise « à placer »).
    var variantesDetachees: [Variante] {
        let principales = Set(elementsDuVoyage.map(\.uid))
        return variantes.filter { !principales.contains($0.departUID) }
    }

    /// Les étapes où un itinéraire bis peut rejoindre le principal : toutes celles qui suivent son départ, hôtels des nuits compris.
    func raccordsPossibles(pour v: Variante) -> [Etape] {
        let liste = elementsDuVoyage
        guard let i = liste.firstIndex(where: { $0.uid == v.departUID }) else { return [] }
        return Array(liste[(i + 1)...])
    }

    /// Crée un itinéraire bis qui part de cette étape (sans raccord : on le choisit ensuite).
    func creerVariante(depuis etape: Etape) -> Variante {
        let noms = Set(variantes.map(\.nom))
        var numero = variantes.count + 1
        while noms.contains("Bis \(numero)") { numero += 1 }
        let v = Variante(nom: "Bis \(numero)", departUID: etape.uid)
        variantes.append(v)
        return v
    }

    /// Supprime l'itinéraire bis et ses étapes ; le Budget revient à l'itinéraire principal s'il le suivait.
    func supprimerVariante(_ id: String, dans contexte: ModelContext) {
        for e in etapes where e.variante == id { contexte.delete(e) }
        variantes.removeAll { $0.id == id }
        if varianteBudget == id { varianteBudget = nil }
    }

    /// Jour d'une nouvelle étape de l'itinéraire bis : celui de sa dernière étape (hors `sauf`), ou celui de son départ (le lendemain d'un hôtel).
    private func jourPourNouvelleEtape(de v: Variante, sauf: Etape? = nil) -> Date? {
        guard let reference = etapes(deVariante: v.id).last(where: { $0 !== sauf }) ?? depart(de: v), let jour = reference.jour else { return jours.first }
        guard reference.apresJour else { return jour }
        let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
        return min(lendemain, jours.last ?? lendemain)
    }

    /// Ajoute une étape vide à la fin de l'itinéraire bis.
    func ajouterEtape(a v: Variante, dans contexte: ModelContext) -> Etape {
        let etape = Etape(titre: "", jour: jourPourNouvelleEtape(de: v))
        etape.variante = v.id
        etape.ordre = (etapes(deVariante: v.id).map(\.ordre).max() ?? -1) + 1
        etape.voyage = self
        contexte.insert(etape)
        return etape
    }

    /// Place l'étape (de l'itinéraire principal, à placer, ou d'un itinéraire bis) dans l'itinéraire bis `v`, juste avant `cible`
    /// (une de ses étapes) ou à la fin, puis renumérote ses étapes. Elle prend le jour de `cible`, ou celui de la fin de l'itinéraire bis.
    /// Refusé pour l'étape d'où part un itinéraire bis : elle doit rester sur l'itinéraire principal. Renvoie false si rien ne change.
    @discardableResult
    func placer(_ etape: Etape, dansVariante v: Variante, avant cible: Etape?) -> Bool {
        guard cible !== etape, etapes.contains(where: { $0 === etape }), variantes(partantDe: etape).isEmpty else { return false }
        // Un jour de l'itinéraire principal que l'étape quitte : ses étapes sont renumérotées.
        let ancienJour = etape.variante == nil && !etape.apresJour ? etape.jour : nil
        let jour = cible?.jour ?? jourPourNouvelleEtape(de: v, sauf: etape)
        etape.variante = v.id
        etape.apresJour = false
        etape.jour = jour.map { Calendar.current.startOfDay(for: $0) }
        var liste = etapes(deVariante: v.id).filter { $0 !== etape }
        let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
        liste.insert(etape, at: index)
        for (i, e) in liste.enumerated() { e.ordre = Double(i) }
        if let ancienJour { for (i, e) in etapes(du: ancienJour).enumerated() { e.ordre = Double(i) } }
        return true
    }

    /// Vrai si déposer l'étape avant `cible` (ou à la fin) la laisse à la même place dans son itinéraire bis.
    func resteEnPlace(_ etape: Etape, dansVariante v: Variante, avant cible: Etape?) -> Bool {
        guard etape.variante == v.id else { return false }
        let liste = etapes(deVariante: v.id)
        guard let i = liste.firstIndex(where: { $0 === etape }) else { return false }
        return cible === etape || (i + 1 < liste.count ? liste[i + 1] : nil) === cible
    }

    /// Étapes des itinéraires bis dont le transport ne mènerait plus au même endroit si l'étape quittait sa place
    /// et, avec `v`, entrait dans cet itinéraire bis avant `cible` (ou à la fin) : elle-même, l'étape d'avant à l'ancienne place,
    /// et celle d'avant à la nouvelle. Les transports de l'itinéraire principal relèvent de `transportsPerdus`.
    func transportsPerdusBis(deplacant etape: Etape, vers v: Variante?, avant cible: Etape?) -> [Etape] {
        var touchees: [Etape] = []
        if etape.variante != nil {
            touchees.append(etape)
            if let p = precedente(de: etape) { touchees.append(p) }
        }
        if let v {
            let liste = etapes(deVariante: v.id).filter { $0 !== etape }
            let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
            if index > 0 { touchees.append(liste[index - 1]) }
        }
        var vues = Set<String>()
        return touchees.filter { $0.transport != nil && vues.insert($0.uid).inserted }
    }

    /// Le transport prévu pour arriver à l'étape : celui de l'élément qui la précède, ou celui du départ de son itinéraire bis.
    func transportPourArriver(a etape: Etape) -> Transport? {
        if let depart = precedente(de: etape) { return depart.transport }
        if let v = variante(de: etape), etapes(deVariante: v.id).first === etape { return v.transportDepart }
        return nil
    }

    // MARK: Itinéraire suivi par le Budget

    /// Ce que compte un itinéraire : l'itinéraire principal, ou un itinéraire bis à la place de la partie du principal qu'il contourne.
    struct Parcours {
        /// L'itinéraire bis suivi (nil : le principal).
        var variante: Variante?
        /// Étapes qui ne comptent pas : celles des autres itinéraires bis, et celles du principal que l'itinéraire bis contourne.
        var exclues: Set<String> = []
        /// Étapes dont le transport ne compte pas : le départ de l'itinéraire bis (il a le sien), la dernière étape d'un itinéraire bis
        /// qui ne rejoint pas le principal.
        var sansTransport: Set<String> = []
        /// Le transport du départ de l'itinéraire bis compte (il mène à une étape).
        var avecTransportDepart = false

        func compte(_ etape: Etape) -> Bool { !exclues.contains(etape.uid) }
        func transport(de etape: Etape) -> Transport? { sansTransport.contains(etape.uid) ? nil : etape.transport }
    }

    /// L'itinéraire choisi pour le Budget. Un itinéraire bis dont le départ n'est plus dans le voyage laisse la place au principal.
    var parcoursDuBudget: Parcours {
        var parcours = Parcours()
        let choisie = variante(varianteBudget)
        parcours.exclues = Set(etapes.filter { $0.variante != nil && $0.variante != choisie?.id }.map(\.uid))
        let liste = elementsDuVoyage
        guard let v = choisie, let i = liste.firstIndex(where: { $0.uid == v.departUID }) else {
            if let choisie { parcours.exclues.formUnion(etapes.filter { $0.variante == choisie.id }.map(\.uid)) }
            return parcours
        }
        // Le raccord n'a de sens que plus loin que le départ ; sinon, l'itinéraire bis ne rejoint pas le principal.
        let j = raccord(de: v).flatMap { r in liste.firstIndex { $0 === r } }.flatMap { $0 > i ? $0 : nil }
        parcours.variante = v
        parcours.exclues.formUnion(liste[(i + 1)..<(j ?? liste.count)].map(\.uid))
        parcours.sansTransport.insert(v.departUID)
        let propres = etapes(deVariante: v.id)
        if j == nil, let derniere = propres.last { parcours.sansTransport.insert(derniere.uid) }
        parcours.avecTransportDepart = !propres.isEmpty || j != nil
        return parcours
    }
}
