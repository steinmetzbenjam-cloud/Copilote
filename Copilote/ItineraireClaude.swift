import Foundation
import SwiftData
import MapKit

/// Un itinéraire préparé par Claude (compétence « Itinéraire Copilote ») : une journée, ou un morceau de journée,
/// avec ses étapes et les transports de l'une à l'autre. Il entre dans le voyage comme UNE étape à placer
/// dont les sous-étapes sont les étapes trouvées par Claude.
///
/// Format (JSON, version 1) — voir `Outils/competence-claude/itineraire-copilote/SKILL.md` :
/// ```
/// { "format": "copilote-itineraire", "version": 1, "titre": "…", "etapes": [ { "titre": "…", "heure": "09:00", "transport": { "mode": "pied" } } ] }
/// ```
/// La lecture est indulgente : champs inconnus ignorés, catégories et modes approchants reconnus, heures « 9h30 » ou « 09:30 ».
struct ItineraireClaude: Decodable, Equatable {
    static let format = "copilote-itineraire"

    var format: String?
    var version: Int?
    var titre: String
    var lieu: String?
    var date: String?
    var categorie: String?
    var resume: String?
    var notes: String?
    var conseils: [String]?
    var latitude: Double?
    var longitude: Double?
    var fuseau: String?
    var etapes: [EtapeClaude]

    struct EtapeClaude: Decodable, Equatable {
        var titre: String
        var lieu: String?
        var adresse: String?
        var latitude: Double?
        var longitude: Double?
        var categorie: String?
        var heure: String?
        var heureFin: String?
        /// Minutes passées sur place.
        var duree: Double?
        var resume: String?
        var notes: String?
        var horaires: String?
        var siteWeb: String?
        var prix: PrixClaude?
        /// Le trajet vers l'étape suivante (absent pour la dernière).
        var transport: TransportClaude?
    }

    struct TransportClaude: Decodable, Equatable {
        var mode: String?
        var sousType: String?
        var compagnie: String?
        var numero: String?
        var de: String?
        var vers: String?
        var depart: String?
        var arrivee: String?
        /// Minutes de trajet estimées.
        var duree: Double?
        var distanceKm: Double?
        var notes: String?
        var prix: PrixClaude?
    }

    /// Prix par personne, dans la devise indiquée (code ISO : EUR, JPY…). Sans devise : euros.
    struct PrixClaude: Decodable, Equatable {
        var adulte: Double?
        var etudiant: Double?
        var adolescent: Double?
        var enfant: Double?
        var devise: String?
    }

    // MARK: Lecture

    enum Erreur: LocalizedError {
        case vide, illisible(String), pasUnItineraire, sansEtape

        var errorDescription: String? {
            switch self {
            case .vide: "Aucun itinéraire à lire : le texte est vide."
            case .illisible(let detail): "L'itinéraire n'a pas pu être lu (\(detail)). Demande à Claude de refaire le fichier au format Copilote."
            case .pasUnItineraire: "Ce fichier n'est pas un itinéraire Copilote préparé par Claude."
            case .sansEtape: "L'itinéraire ne contient aucune étape."
            }
        }
    }

    /// Lit un itinéraire depuis un texte : le JSON seul, ou tout un message de Claude qui le contient (bloc de code compris).
    static func lire(texte: String) throws -> ItineraireClaude {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Erreur.vide }
        guard let debut = t.firstIndex(of: "{"), let fin = t.lastIndex(of: "}"), debut < fin else { throw Erreur.pasUnItineraire }
        return try lire(Data(t[debut...fin].utf8))
    }

    static func lire(_ donnees: Data) throws -> ItineraireClaude {
        let it: ItineraireClaude
        do {
            it = try JSONDecoder().decode(ItineraireClaude.self, from: donnees)
        } catch DecodingError.keyNotFound(let cle, _) {
            if cle.stringValue == "etapes" || cle.stringValue == "titre" { throw Erreur.pasUnItineraire }
            throw Erreur.illisible("champ « \(cle.stringValue) » manquant")
        } catch DecodingError.typeMismatch(_, let contexte), DecodingError.valueNotFound(_, let contexte) {
            let chemin = contexte.codingPath.map { $0.intValue.map { "\($0 + 1)" } ?? $0.stringValue }.joined(separator: " › ")
            throw Erreur.illisible("valeur inattendue : \(chemin)")
        } catch {
            throw Erreur.illisible("ce n'est pas du JSON valide")
        }
        if let f = it.format, f != format { throw Erreur.pasUnItineraire }
        guard !it.etapes.isEmpty else { throw Erreur.sansEtape }
        return it
    }

    // MARK: Traductions

    /// « 09:30 », « 9h30 », « 9 h », « 09:30:00 », « 2026-12-03T09:30 » → heure et minutes.
    static func heureMinutes(_ texte: String?) -> (heure: Int, minute: Int)? {
        guard var t = texte?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        if let i = t.firstIndex(of: "t"), t.contains("-") { t = String(t[t.index(after: i)...]) }
        let nombres = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let h = nombres.first, (0...23).contains(h) else { return nil }
        let m = nombres.count > 1 ? nombres[1] : 0
        guard (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Une heure saisie dans l'app : seules l'heure et les minutes comptent (lues dans le fuseau du lieu).
    static func date(_ texte: String?) -> Date? {
        guard let hm = heureMinutes(texte) else { return nil }
        return Calendar.current.date(bySettingHour: hm.heure, minute: hm.minute, second: 0, of: Calendar.current.startOfDay(for: .now))
    }

    static func categorie(_ texte: String?) -> CategorieEtape {
        let t = (texte ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if let c = CategorieEtape(rawValue: t), !CategorieEtape.retirees.contains(c) { return c }
        switch t {
        case "musee", "museum", "galerie", "exposition": return .musee
        case "repas", "restaurant", "cafe", "dejeuner", "diner", "petit-dejeuner", "bar", "marche": return .repas
        case "hebergement", "hotel", "logement": return .hebergement
        case "activite", "spectacle", "loisir", "sport", "plage", "baignade": return .activite
        case "nature", "parc", "jardin", "randonnee", "point de vue", "panorama": return .visite
        default: return .visite
        }
    }

    /// Le mode de l'app et le type proposé (« Métro », « Taxi / VTC »…) pour un mode écrit par Claude.
    static func mode(_ texte: String?, sousType: String?) -> (ModeTransport, String) {
        let t = (texte ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let s = sousType ?? ""
        switch t {
        case "pied", "a pied", "marche", "walk", "walking": return (.pied, s)
        case "velo", "bike", "bicycle": return (.velo, s)
        case "voiture", "car", "auto": return (.voiture, s)
        case "taxi", "vtc", "uber": return (.voiture, s.isEmpty ? "Taxi / VTC" : s)
        case "location": return (.voiture, s.isEmpty ? "Location" : s)
        case "commun", "transports en commun", "transit": return (.commun, s)
        case "train", "tgv", "shinkansen": return (.commun, s.isEmpty ? "Train" : s)
        case "bus", "car (autocar)", "autocar": return (.commun, s.isEmpty ? "Bus" : s)
        case "metro", "subway": return (.commun, s.isEmpty ? "Métro" : s)
        case "tram", "tramway": return (.commun, s.isEmpty ? "Tram" : s)
        case "avion", "vol", "plane", "flight": return (.avion, s)
        case "bateau", "ferry", "navette", "boat": return (.bateau, s.isEmpty && t == "ferry" ? "Ferry" : s)
        default: return (ModeTransport(rawValue: t) ?? .pied, s)
        }
    }
}

// MARK: Dans le voyage

extension Voyage {
    /// Ajoute l'itinéraire de Claude aux étapes à placer : une étape qui le contient, ses sous-étapes et leurs transports.
    @discardableResult
    func importer(_ it: ItineraireClaude, dans contexte: ModelContext) -> Etape {
        let parent = Etape(titre: it.titre.trimmingCharacters(in: .whitespacesAndNewlines), jour: nil,
                           categorie: ItineraireClaude.categorie(it.categorie))
        parent.ordre = (etapesSansJour.map(\.ordre).max() ?? -1) + 1
        parent.voyage = self
        contexte.insert(parent)

        var sous: [Etape] = []
        for (i, e) in it.etapes.enumerated() {
            let s = Etape(titre: e.titre.trimmingCharacters(in: .whitespacesAndNewlines), jour: nil, categorie: ItineraireClaude.categorie(e.categorie))
            s.voyage = self
            contexte.insert(s)
            s.parentUID = parent.uid
            s.ordre = Double(i)
            let adresse = [e.lieu, e.adresse].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            s.lieu = adresse.map { $0.localizedCaseInsensitiveContains(s.titre) ? $0 : "\(s.titre), \($0)" } ?? s.titre
            if let la = e.latitude, let lo = e.longitude, (-90...90).contains(la), (-180...180).contains(lo), la != 0 || lo != 0 {
                s.latitude = la; s.longitude = lo
            }
            s.fuseauChoisi = it.fuseau.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
            s.heure = ItineraireClaude.date(e.heure)
            s.heureFin = ItineraireClaude.date(e.heureFin)
            if let debut = s.heure, let fin = s.heureFin, fin > debut {
                s.duree = fin.timeIntervalSince(debut) / 60
            } else if let d = e.duree, d > 0 {
                s.duree = d
                if let debut = s.heure { s.heureFin = debut.addingTimeInterval(d * 60) }
            }
            s.resume = e.resume?.nonVide
            s.horaires = e.horaires?.nonVide
            s.siteWeb = e.siteWeb?.nonVide
            var notes = e.notes?.nonVide.map { [$0] } ?? []
            if let p = e.prix, let reste = appliquerPrix(p, a: s) { notes.append(reste) }
            s.notes = notes.joined(separator: "\n\n")
            // Le transport vers la sous-étape suivante (la dernière n'en a pas : la suite de la journée se règle dans l'app).
            if let t = e.transport, i + 1 < it.etapes.count { s.transport = transportImporte(t) }
            sous.append(s)
        }

        // L'étape qui contient tout : sa position est celle donnée, sinon celle du premier point ; ses horaires couvrent les sous-étapes.
        let premier = sous.first
        parent.lieu = it.lieu?.nonVide ?? premier?.lieu ?? ""
        if let la = it.latitude, let lo = it.longitude, la != 0 || lo != 0 {
            parent.latitude = la; parent.longitude = lo
        } else {
            parent.latitude = premier?.latitude; parent.longitude = premier?.longitude
        }
        parent.fuseauChoisi = premier?.fuseauChoisi
        parent.heure = sous.compactMap(\.heure).first
        parent.heureFin = sous.reversed().compactMap { $0.heureFin ?? $0.heure }.first
        if let debut = parent.heure, let fin = parent.heureFin, fin > debut { parent.duree = fin.timeIntervalSince(debut) / 60 } else { parent.heureFin = nil }
        var notes: [String] = []
        if let r = it.resume?.nonVide { notes.append(r) }
        if let n = it.notes?.nonVide { notes.append(n) }
        let conseils = (it.conseils ?? []).compactMap(\.nonVide)
        if !conseils.isEmpty { notes.append((["Conseils"] + conseils.map { "• \($0)" }).joined(separator: "\n")) }
        if let d = it.date?.nonVide { notes.append("Prévu pour le \(d).") }
        notes.append("✨ Itinéraire préparé par Claude le \(Date.now.formatted(date: .long, time: .omitted)).")
        parent.notes = notes.joined(separator: "\n\n")
        return parent
    }

    private func transportImporte(_ t: ItineraireClaude.TransportClaude) -> Transport {
        var r = Transport()
        (r.mode, r.sousType) = ItineraireClaude.mode(t.mode, sousType: t.sousType?.nonVide)
        r.compagnie = t.compagnie?.nonVide ?? ""
        r.numero = t.numero?.nonVide ?? ""
        r.de = t.de?.nonVide ?? ""
        r.vers = t.vers?.nonVide ?? ""
        r.depart = ItineraireClaude.date(t.depart)
        r.arrivee = ItineraireClaude.date(t.arrivee)
        // L'app calcule elle-même les trajets à pied, à vélo, en voiture ou en bateau ; pour les autres, la durée de Claude sert d'estimation.
        if let d = t.duree, d > 0, r.depart == nil || r.arrivee == nil, !r.mode.aUnItineraire { r.dureeModifiee = d }
        var notes = t.notes?.nonVide.map { [$0] } ?? []
        let estimation = [t.duree.map { "≈ \(CategorieEtape.texteDuree($0))" }, t.distanceKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" }]
            .compactMap { $0 }
        if !estimation.isEmpty { notes.append("Estimation de Claude : " + estimation.joined(separator: ", ")) }
        if let p = t.prix {
            let (monnaie, reste) = monnaieImportee(p)
            if let monnaie {
                r.prixAdulte = p.adulte; r.prixEtudiant = p.etudiant; r.prixAdolescent = p.adolescent; r.prixEnfant = p.enfant
                r.monnaieAdulte = monnaie; r.monnaieEtudiant = monnaie; r.monnaieAdolescent = monnaie; r.monnaieEnfant = monnaie
            } else if let reste { notes.append(reste) }
        }
        r.notes = notes.joined(separator: "\n")
        return r
    }

    /// Range le prix dans l'étape quand sa devise est l'euro ou une monnaie du voyage ; sinon renvoie le texte à garder dans les notes.
    private func appliquerPrix(_ p: ItineraireClaude.PrixClaude, a e: Etape) -> String? {
        let (monnaie, reste) = monnaieImportee(p)
        guard let monnaie else { return reste }
        e.prixAdulte = p.adulte; e.prixEtudiant = p.etudiant; e.prixAdolescent = p.adolescent; e.prixEnfant = p.enfant
        e.monnaieAdulte = monnaie; e.monnaieEtudiant = monnaie; e.monnaieAdolescent = monnaie; e.monnaieEnfant = monnaie
        return nil
    }

    /// La monnaie de l'app qui correspond à la devise du prix ; nil (et le prix en texte) pour une devise que le voyage n'a pas.
    private func monnaieImportee(_ p: ItineraireClaude.PrixClaude) -> (MonnaiePrix?, String?) {
        let code = (p.devise?.nonVide ?? "EUR").uppercased()
        if code == "EUR" || code == "€" { return (.euro, nil) }
        if code == deviseLocale?.uppercased() { return (.locale, nil) }
        if code == deviseTierce?.uppercased() { return (.tierce, nil) }
        let lignes = [("adulte", p.adulte), ("étudiant", p.etudiant), ("adolescent", p.adolescent), ("enfant", p.enfant)]
            .compactMap { nom, v in v.map { "\(nom) \($0.formatted()) \(code)" } }
        return (nil, lignes.isEmpty ? nil : "Prix : " + lignes.joined(separator: ", "))
    }
}

extension ItineraireClaude {
    /// Cherche dans Plans la position des sous-étapes que Claude a laissées sans coordonnées, près des autres points de l'itinéraire.
    @MainActor static func completerPositions(de parent: Etape) async {
        let points = parent.sousEtapes
        let connus = points.compactMap(\.coordonnee)
        for s in points where s.coordonnee == nil {
            let requete = MKLocalSearch.Request()
            requete.naturalLanguageQuery = s.lieu.isEmpty ? s.titre : s.lieu
            if let centre = connus.first {
                requete.region = MKCoordinateRegion(center: centre, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
            }
            guard let item = try? await MKLocalSearch(request: requete).start().mapItems.first else { continue }
            s.latitude = item.placemark.coordinate.latitude
            s.longitude = item.placemark.coordinate.longitude
        }
        if parent.coordonnee == nil, let c = parent.sousEtapes.compactMap(\.coordonnee).first {
            parent.latitude = c.latitude; parent.longitude = c.longitude
        }
    }
}

private extension String {
    /// Le texte sans espaces autour, ou nil s'il est vide.
    var nonVide: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
