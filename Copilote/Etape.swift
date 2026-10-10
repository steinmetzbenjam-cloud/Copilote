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
    /// Texte court d'une durée en minutes : « 45 min », « 2 h », « 1 h 30 ».
    static func texteDuree(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }
}

extension Etape {
    /// Une copie de l'étape (lieu, horaires, durée, prix, notes, infos et photos), placée juste après elle dans son jour.
    /// Le transport vers l'étape suivante n'est pas copié. Un hébergement de nuit n'a qu'une place : sa copie va dans « à placer ».
    func copie(dans contexte: ModelContext) -> Etape {
        let c = nouvelleCopie(jour: apresJour ? nil : jour, avecHoraires: !apresJour, dans: contexte)
        if let voyage {
            if let j = c.jour {
                // Juste après l'original : les étapes du jour sont renumérotées.
                voyage.inserer(c, apres: self, du: j)
            } else {
                c.ordre = (voyage.etapesSansJour.filter { $0 !== c }.map(\.ordre).max() ?? -1) + 1
            }
        }
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
        c.prixAdulte = prixAdulte; c.prixEnfant = prixEnfant; c.prixEtudiant = prixEtudiant
        c.monnaieAdulte = monnaieAdulte; c.monnaieEnfant = monnaieEnfant; c.monnaieEtudiant = monnaieEtudiant
        c.voyage = voyage
        contexte.insert(c)
        for photo in photos {
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
        case .park?, .nationalPark?, .beach?: self = .nature
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
    var prixAdulteLocal: Bool = false
    var prixEnfantLocal: Bool = false
    var prixEtudiantLocal: Bool = false
    /// Prix saisi dans la troisième monnaie du voyage (prioritaire sur `…Local`).
    var prixAdulteTierce: Bool = false
    var prixEnfantTierce: Bool = false
    var prixEtudiantTierce: Bool = false
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
