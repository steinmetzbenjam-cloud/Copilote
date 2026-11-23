import Foundation
import SwiftData
import CoreLocation
import MapKit

enum CategorieEtape: String, Codable, CaseIterable, Identifiable {
    case visite, musee, nature, repas, transport, hebergement, activite, autre

    var id: String { rawValue }

    var libelle: String {
        switch self {
        case .visite: "Visite"
        case .musee: "Musée"
        case .nature: "Nature"
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
        case .musee: "building.columns.fill"
        case .nature: "leaf.fill"
        case .repas: "fork.knife"
        case .transport: "car.fill"
        case .hebergement: "bed.double.fill"
        case .activite: "ticket.fill"
        case .autre: "star.fill"
        }
    }
}

extension CategorieEtape {
    /// Catégories qu'on ne choisit plus (elles restent lisibles pour les étapes qui les ont déjà).
    static let retirees: Set<CategorieEtape> = [.transport, .nature]

    /// Texte court d'une durée en minutes : « 45 min », « 2 h », « 1 h 30 ».
    static func texteDuree(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }
}

extension Etape {
    /// Une copie de l'étape (lieu, horaires, durée, prix, notes, infos et photos du lieu, sans l'album), placée juste après elle dans son jour.
    /// Le transport vers l'étape suivante n'est pas copié. Un hébergement de nuit est copié dans la même nuit, après les autres.
    /// Ses sous-étapes sont copiées avec elle ; une sous-étape est copiée juste après elle, dans la même étape.
    func copie(dans contexte: ModelContext) -> Etape {
        let c = nouvelleCopie(jour: apresJour ? nil : jour, avecHoraires: true, dans: contexte)
        if let parente = etapeParente {
            // La sous-étape qui suit l'originale, cherchée avant que la copie ne rejoigne la liste.
            let suivante = parente.sousEtapes.drop { $0 !== self }.dropFirst().first
            c.parentUID = parente.uid
            parente.ranger(c, avant: suivante)
            return c
        }
        for s in sousEtapes {
            let cs = s.nouvelleCopie(jour: nil, avecHoraires: true, dans: contexte)
            cs.parentUID = c.uid
            cs.ordre = s.ordre
            cs.transport = s.transport
        }
        if let voyage {
            if apresJour, let nuit = jour {
                voyage.placerEntreJours(c, apres: nuit)
            } else if let j = c.jour {
                // Juste après l'original : les étapes du jour sont renumérotées.
                voyage.inserer(c, apres: self, du: j)
            } else {
                c.ordre = (voyage.etapesSansJour.filter { $0 !== c }.map(\.ordre).max() ?? -1) + 1
            }
        }
        return c
    }

    /// Une copie de cet hébergement pour la nuit qui suit `jour`, à côté de ceux qui y sont déjà.
    func copieHebergement(nuit jour: Date, dans contexte: ModelContext) -> Etape {
        let c = nouvelleCopie(jour: nil, avecHoraires: true, dans: contexte)
        voyage?.placerEntreJours(c, apres: jour)
        return c
    }

    /// La copie elle-même (sans transport), insérée dans le contexte mais pas encore rangée dans son jour.
    private func nouvelleCopie(jour: Date?, avecHoraires: Bool, dans contexte: ModelContext) -> Etape {
        let c = Etape(titre: titre, jour: jour, categorie: categorie)
        c.lieu = lieu
        if avecHoraires { c.heure = heure; c.heureFin = heureFin }
        c.duree = duree; c.fuseauChoisi = fuseauChoisi; c.notes = notes
        c.latitude = latitude; c.longitude = longitude
        c.resume = resume; c.horaires = horaires; c.photoURL = photoURL
        c.noteGoogle = noteGoogle; c.avisGoogle = avisGoogle; c.lienGoogle = lienGoogle
        c.noteTripadvisor = noteTripadvisor; c.avisTripadvisor = avisTripadvisor; c.lienTripadvisor = lienTripadvisor
        c.siteWeb = siteWeb
        c.prixAdulte = prixAdulte; c.prixEnfant = prixEnfant; c.prixEtudiant = prixEtudiant; c.prixAdolescent = prixAdolescent
        c.monnaieAdulte = monnaieAdulte; c.monnaieEnfant = monnaieEnfant; c.monnaieEtudiant = monnaieEtudiant; c.monnaieAdolescent = monnaieAdolescent
        c.categoriesPrixJSON = categoriesPrixJSON
        c.paysFavori = paysFavori
        c.voyage = voyage
        contexte.insert(c)
        // Les photos du lieu suivent la copie ; l'album reste à l'étape d'origine.
        for photo in photosDuLieu {
            let p = Document(nom: photo.nom, extensionFichier: photo.extensionFichier, donnees: photo.donnees)
            p.voyage = voyage
            p.etape = c
            contexte.insert(p)
        }
        return c
    }

    /// L'étape d'où l'on vient pour arriver ici (la précédente du jour, ou l'hôtel de la veille), si un retour vers elle est possible.
    var departPourRetour: Etape? {
        guard jour != nil, !apresJour, let voyage else { return nil }
        return voyage.precedente(de: self)
    }

    /// Aller-retour : ajoute juste après cette étape un retour vers celle d'où l'on vient (copie de son lieu, sans horaires),
    /// avec le même mode de transport qu'à l'aller. Le transport qui partait d'ici part désormais du retour.
    func ajouterRetour(dans contexte: ModelContext) -> Etape? {
        guard let depart = departPourRetour, let voyage, let j = jour else { return nil }
        let retour = depart.nouvelleCopie(jour: j, avecHoraires: false, dans: contexte)
        retour.transport = transport
        let aller = depart.transport
        var trajet = Transport()
        trajet.mode = aller?.mode ?? .voiture
        trajet.sousType = aller?.sousType ?? ""
        trajet.compagnie = aller?.compagnie ?? ""
        transport = trajet
        voyage.inserer(retour, apres: self, du: j)
        return retour
    }
}

extension CategorieEtape {
    /// La catégorie qui correspond à un point d'intérêt de Plans (restaurant, musée, parc, hôtel…).
    init(pointDInteret c: MKPointOfInterestCategory?) {
        switch c {
        case .restaurant?, .cafe?, .bakery?, .brewery?, .winery?, .foodMarket?: self = .repas
        case .museum?: self = .musee
        case .hotel?, .campground?: self = .hebergement
        case .amusementPark?, .aquarium?, .zoo?, .stadium?, .theater?, .movieTheater?, .nightlife?, .marina?, .fitnessCenter?: self = .activite
        default: self = .visite
        }
    }
}

@Model
final class Etape {
    var titre: String
    var lieu: String
    /// nil : étape préparée, pas encore placée dans un jour.
    var jour: Date?
    /// Hébergement placé entre `jour` et le jour suivant (la nuit), plutôt que dans le jour.
    var apresJour: Bool = false
    var heure: Date?
    /// Heure de fin (facultative).
    var heureFin: Date?
    /// Durée de l'activité, en minutes (facultative). Avec une heure de début, elle donne l'heure de fin.
    var duree: Double?
    /// Fuseau horaire des heures de l'étape (identifiant, ex. « America/Costa_Rica »), si différent de celui de son lieu.
    var fuseauChoisi: String?
    /// En voyage : le moment réel où l'on est arrivé à l'étape (un instant, affiché dans le fuseau du lieu). nil : pas encore noté.
    var arriveeReelle: Date?
    /// En voyage : le moment réel où l'on est reparti de l'étape. nil : pas encore noté.
    var departReel: Date?
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
    /// Budget par personne : adulte, enfant, étudiant. Chaque prix est saisi en euros, ou en monnaie locale (drapeaux `…Local`).
    var prixAdulte: Double?
    var prixEnfant: Double?
    var prixEtudiant: Double?
    var prixAdolescent: Double?
    var prixAdolescentLocal: Bool = false
    var prixAdolescentTierce: Bool = false
    var prixAdulteLocal: Bool = false
    var prixEnfantLocal: Bool = false
    var prixEtudiantLocal: Bool = false
    /// Prix saisi dans la troisième monnaie du voyage (prioritaire sur `…Local`).
    var prixAdulteTierce: Bool = false
    var prixEnfantTierce: Bool = false
    var prixEtudiantTierce: Bool = false
    /// Voyageurs (uid) non concernés par le prix prévu : ils ne comptent pas dans le Budget. Vide ou nil : tout le monde.
    var exclusBudget: [String]?
    /// Enfants et adolescents (uid) qui paient ici le prix de l'autre tarif : un adolescent au prix enfant, un enfant au prix adolescent.
    var basculesTarif: [String]?
    /// Autres catégories de prix (voir `CategoriePrix`), en JSON.
    var categoriesPrixJSON: String?
    /// Étape favorite : code ISO de son pays (FR, JP…). Partagé avec le voyage : tous ses voyageurs voient le cœur,
    /// et l'étape est proposée dans leurs prochains voyages dans ce pays. nil : pas favorite pour le voyage.
    var paysFavori: String?
    /// Sous-étape : uid de l'étape qui la contient (les points d'un circuit, d'une visite…). Elle n'a pas de jour à elle :
    /// elle suit son étape, et n'apparaît sur la carte que quand on déplie celle-ci. nil : étape ordinaire.
    var parentUID: String?
    var creeLe: Date
    var uid: String = ""
    /// Transport vers l'étape suivante, en JSON (voir Transport).
    var transportJSON: String?
    /// Position dans la journée (réglée en glissant les étapes).
    var ordre: Double = 0
    var voyage: Voyage?
    @Relationship(deleteRule: .cascade, inverse: \Document.etape)
    var photos: [Document] = []

    init(titre: String, jour: Date?, categorie: CategorieEtape = .visite) {
        self.titre = titre
        self.lieu = ""
        self.jour = jour.map { Calendar.current.startOfDay(for: $0) }
        self.heure = nil
        self.categorie = categorie
        self.notes = ""
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}

extension Etape {
    var aDesInfosDeLieu: Bool {
        resume != nil || horaires != nil || photoURL != nil || !photosDuLieu.isEmpty || noteGoogle != nil || noteTripadvisor != nil || siteWeb != nil
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

// MARK: Sous-étapes

extension Etape {
    /// Préfixe du texte glissé pour déplacer une étape (liste des jours, étapes à placer, sous-étapes).
    static let prefixeGlisser = "copilote-etape:"

    var estSousEtape: Bool { parentUID != nil }

    /// L'étape qui contient cette sous-étape (nil si elle a disparu : la sous-étape repart alors dans « À placer »).
    var etapeParente: Etape? {
        guard let parentUID, let voyage else { return nil }
        return voyage.etapes.first { $0.uid == parentUID }
    }

    /// Les sous-étapes, dans l'ordre choisi. Une sous-étape n'en a pas : un seul niveau.
    var sousEtapes: [Etape] {
        guard parentUID == nil, let voyage else { return [] }
        return voyage.etapes.filter { $0.parentUID == uid }.sorted { ($0.ordre, $0.creeLe) < ($1.ordre, $1.creeLe) }
    }

    var aDesSousEtapes: Bool {
        guard parentUID == nil, let voyage else { return false }
        return voyage.etapes.contains { $0.parentUID == uid }
    }

    /// Le jour de l'étape ; pour une sous-étape, celui de son étape.
    var jourEffectif: Date? { jour ?? etapeParente?.jour }

    /// Où mène le transport qui arrive à cette étape : sa première sous-étape placée sur la carte, sinon l'étape elle-même.
    var entree: Etape { sousEtapes.first { $0.coordonnee != nil } ?? self }
    /// D'où part le transport vers l'étape suivante : sa dernière sous-étape placée sur la carte, sinon l'étape elle-même.
    var sortie: Etape { sousEtapes.last { $0.coordonnee != nil } ?? self }
    var coordonneeEntree: CLLocationCoordinate2D? { entree.coordonnee }
    var coordonneeSortie: CLLocationCoordinate2D? { sortie.coordonnee }

    /// Une étape créée puis laissée vide (ni nom, ni lieu, ni sous-étape) : elle est retirée à la fermeture.
    var sansContenu: Bool {
        titre.trimmingCharacters(in: .whitespaces).isEmpty && lieu.isEmpty && !aDesSousEtapes
    }

    /// Crée une sous-étape vide, à la fin de la liste.
    func ajouterSousEtape(dans contexte: ModelContext) -> Etape {
        let s = Etape(titre: "", jour: nil)
        s.voyage = voyage
        contexte.insert(s)
        s.parentUID = uid
        ranger(s, avant: nil)
        return s
    }

    /// Vrai si `etape` peut devenir une sous-étape de celle-ci : une étape à placer (sans sous-étapes), ou une des siennes qu'on range.
    func peutRecevoir(_ etape: Etape) -> Bool {
        guard etape !== self, parentUID == nil else { return false }
        if etape.parentUID == uid { return true }
        return etape.jour == nil && etape.parentUID == nil && !etape.aDesSousEtapes
    }

    /// Fait de `etape` une sous-étape, juste avant `cible` (à la fin sans cible), et renumérote les sous-étapes.
    @discardableResult
    func rattacher(_ etape: Etape, avant cible: Etape?) -> Bool {
        guard peutRecevoir(etape), cible !== etape else { return false }
        etape.parentUID = uid
        etape.jour = nil
        etape.apresJour = false
        ranger(etape, avant: cible)
        return true
    }

    /// Place la sous-étape juste avant `cible` (à la fin sans cible) et renumérote.
    fileprivate func ranger(_ etape: Etape, avant cible: Etape?) {
        var liste = sousEtapes.filter { $0 !== etape }
        let index = cible.flatMap { c in liste.firstIndex { $0 === c } } ?? liste.count
        liste.insert(etape, at: index)
        for (i, e) in liste.enumerated() { e.ordre = Double(i) }
    }

    /// La sous-étape redevient une étape à placer, sans horaires ni transport.
    func detacherDeSonEtape() {
        guard parentUID != nil else { return }
        parentUID = nil
        transport = nil
        heure = nil
        heureFin = nil
        if let voyage { ordre = (voyage.etapesSansJour.filter { $0 !== self }.map(\.ordre).max() ?? -1) + 1 }
    }
}
