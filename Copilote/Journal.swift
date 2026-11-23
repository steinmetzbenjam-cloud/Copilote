import Foundation
import SwiftData
import CloudKit

// MARK: - Modèle

/// Une ligne du journal des modifications d'un voyage : qui a ajouté, modifié ou supprimé quoi, et quand.
/// Chaque appareil note ce que fait son voyageur ; les lignes voyagent avec le voyage (iCloud), si bien que les
/// organisateurs voient celles de tout le monde.
@Model
final class EntreeJournal {
    var uid: String = ""
    var date: Date = Date.now
    var auteurUID: String = ""
    /// Le nom au moment de la modification (si le voyageur est supprimé ensuite, on sait encore qui c'était).
    var auteurNom: String = ""
    var actionBrut: String = ActionJournal.modification.rawValue
    /// Type de l'objet (celui de la synchronisation : « Etape », « Reservation »…).
    var typeObjet: String = ""
    var objetUID: String = ""
    /// Nom de l'objet au moment de la modification (« Place du Tertre »).
    var libelle: String = ""
    /// Ce qui a changé (clés des champs), pour une modification.
    var champs: [String] = []
    /// Nombre d'éléments de la ligne (plusieurs photos ajoutées d'un coup à un album).
    var nombre: Int = 1
    var voyage: Voyage?

    init(action: ActionJournal, typeObjet: String, objetUID: String, libelle: String, auteurUID: String, auteurNom: String, date: Date = .now) {
        self.uid = UUID().uuidString
        self.actionBrut = action.rawValue
        self.typeObjet = typeObjet
        self.objetUID = objetUID
        self.libelle = libelle
        self.auteurUID = auteurUID
        self.auteurNom = auteurNom
        self.date = date
    }

    var action: ActionJournal { ActionJournal(rawValue: actionBrut) ?? .modification }
}

enum ActionJournal: String {
    case ajout, modification, suppression

    var verbe: String {
        switch self {
        case .ajout: "a ajouté"
        case .modification: "a modifié"
        case .suppression: "a supprimé"
        }
    }

    var symbole: String {
        switch self {
        case .ajout: "plus.circle.fill"
        case .modification: "pencil.circle.fill"
        case .suppression: "minus.circle.fill"
        }
    }
}

// MARK: - Enregistrement des modifications

/// Repère ce que le voyageur de cet appareil change dans ses voyages et l'inscrit au journal.
///
/// Toutes les quelques secondes, l'état de chaque objet (le même que celui envoyé à iCloud) est comparé au précédent.
/// Les changements reçus d'iCloud ou d'une sauvegarde sont « acceptés » sans être notés : ils viennent d'ailleurs,
/// et l'appareil de leur auteur les a déjà inscrits.
@MainActor
final class JournalModifications {
    static let shared = JournalModifications()

    struct Etat: Equatable {
        var voyageUID: String
        var type: TypeCloud
        var uid: String
        /// Le type inscrit au journal : celui de la synchronisation, ou « Photo » pour une photo d'album.
        var typeJournal: String
        /// Pour une photo d'album : l'étape (les photos ajoutées ensemble font une seule ligne).
        var groupe: String?
        var libelle: String
        var champs: [String: String]
    }

    /// Au-delà, les lignes les plus anciennes d'un voyage sont effacées.
    static let maximumParVoyage = 3000
    /// Les modifications successives d'un même objet par la même personne, dans ce délai, ne font qu'une ligne.
    static let regroupement: TimeInterval = 10 * 60
    /// Champs tenus à jour par l'app elle-même : leur changement n'est pas une modification.
    static let champsIgnores: Set<String> = ["creeLe", "modifieLe", "voyageUID"]
    /// Champs qui rattachent un objet à un autre : supprimé (ou ajouté) avec son parent, il n'a pas sa propre ligne.
    static let champsParents = ["etapeUID", "reservationUID", "sondageUID", "parentUID"]

    private var contexte: ModelContext?
    private var connus: [String: Etat] = [:]
    /// Dernière ligne écrite par cet appareil pour chaque objet (pour regrouper).
    private var dernieres: [String: EntreeJournal] = [:]
    private var boucle: Task<Void, Never>?
    var maintenant: () -> Date = { .now }

    init(contexte: ModelContext? = nil) {
        self.contexte = contexte
    }

    func demarrer(contexte: ModelContext) {
        self.contexte = contexte
        connus = etats()
        boucle?.cancel()
        boucle = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.noter()
            }
        }
    }

    /// Prend l'état actuel comme référence, sans rien noter (après un import, par exemple).
    func accepterTout() {
        connus = etats()
    }

    /// Ces objets viennent d'être changés par la synchronisation : leur nouvel état devient la référence.
    func accepter(noms: some Sequence<String>) {
        guard let contexte else { return }
        for nom in noms {
            if let objet = Codec.objet(recordName: nom, contexte), let etat = Self.etat(de: objet) {
                connus[nom] = etat
            } else {
                connus.removeValue(forKey: nom)
            }
        }
    }

    /// Compare l'état actuel au précédent et inscrit ce qui a changé.
    func noter() {
        guard let contexte else { return }
        let actuels = etats()
        defer { connus = actuels }
        guard actuels != connus else { return }

        let ajoutes = actuels.filter { connus[$0.key] == nil }
        let supprimes = connus.filter { actuels[$0.key] == nil }
        let uidsAjoutes = Set(ajoutes.values.map(\.uid))
        let uidsSupprimes = Set(supprimes.values.map(\.uid))
        let voyages = Dictionary(((try? contexte.fetch(FetchDescriptor<Voyage>())) ?? []).map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })

        func rattache(_ etat: Etat, a uids: Set<String>) -> Bool {
            Self.champsParents.contains { etat.champs[$0].map(uids.contains) ?? false }
        }

        for (nom, etat) in ajoutes {
            guard !rattache(etat, a: uidsAjoutes), let voyage = voyages[etat.voyageUID] else { continue }
            inscrire(.ajout, nom: nom, etat: etat, champs: [], dans: voyage, contexte: contexte)
        }
        for (nom, etat) in supprimes {
            // Un voyage supprimé emporte son journal : rien à noter.
            guard !rattache(etat, a: uidsSupprimes), let voyage = voyages[etat.voyageUID] else { continue }
            inscrire(.suppression, nom: nom, etat: etat, champs: [], dans: voyage, contexte: contexte)
        }
        for (nom, etat) in actuels {
            guard let avant = connus[nom], avant.champs != etat.champs, let voyage = voyages[etat.voyageUID] else { continue }
            let cles = Set(avant.champs.keys).union(etat.champs.keys)
                .filter { avant.champs[$0] != etat.champs[$0] && !Self.champsIgnores.contains($0) }
            guard !cles.isEmpty else { continue }
            inscrire(.modification, nom: nom, etat: etat, champs: cles.sorted(), dans: voyage, contexte: contexte)
        }
        for voyage in voyages.values where voyage.journal.count > Self.maximumParVoyage {
            for vieille in voyage.journal.sorted(by: { $0.date > $1.date }).dropFirst(Self.maximumParVoyage) {
                contexte.delete(vieille)
            }
        }
    }

    private func inscrire(_ action: ActionJournal, nom: String, etat: Etat, champs: [String], dans voyage: Voyage, contexte: ModelContext) {
        let moi = MoiVoyage.lire(voyage)
        let auteurNom = voyage.membre(uid: moi)?.nomAffiche ?? Profil.partage.nomComplet
        let maintenant = maintenant()
        func recente(_ ligne: EntreeJournal?) -> EntreeJournal? {
            guard let ligne, ligne.modelContext != nil, !ligne.isDeleted, ligne.auteurUID == moi, ligne.auteurNom == auteurNom,
                  maintenant.timeIntervalSince(ligne.date) < Self.regroupement else { return nil }
            return ligne
        }

        // Plusieurs photos ajoutées (ou retirées) au même album : une seule ligne, avec leur nombre.
        if let groupe = etat.groupe, action != .modification {
            let cle = "\(action.rawValue)-\(groupe)"
            if let ligne = recente(dernieres[cle]) {
                ligne.nombre += 1
                ligne.date = maintenant
                return
            }
            let entree = EntreeJournal(action: action, typeObjet: etat.typeJournal, objetUID: groupe, libelle: etat.libelle,
                                       auteurUID: moi, auteurNom: auteurNom, date: maintenant)
            entree.voyage = voyage
            contexte.insert(entree)
            dernieres[cle] = entree
            return
        }

        // Même objet, même personne, il y a peu : on complète la ligne précédente.
        if let derniere = recente(dernieres[nom]) {
            switch (derniere.action, action) {
            case (.ajout, .suppression):
                // Ajouté puis retiré aussitôt (une étape vide abandonnée…) : il ne s'est rien passé.
                contexte.delete(derniere)
                dernieres.removeValue(forKey: nom)
                return
            case (_, .modification):
                derniere.champs = Array(Set(derniere.champs).union(champs)).sorted()
                derniere.libelle = etat.libelle
                derniere.date = maintenant
                return
            default:
                break
            }
        }
        let entree = EntreeJournal(action: action, typeObjet: etat.typeJournal, objetUID: etat.uid, libelle: etat.libelle,
                                   auteurUID: moi, auteurNom: auteurNom, date: maintenant)
        entree.champs = champs
        entree.voyage = voyage
        contexte.insert(entree)
        dernieres[nom] = entree
    }

    // MARK: État des objets

    private func etats() -> [String: Etat] {
        guard let contexte else { return [:] }
        var sortie: [String: Etat] = [:]
        for v in (try? contexte.fetch(FetchDescriptor<Voyage>())) ?? [] where !v.uid.isEmpty {
            var objets: [any PersistentModel] = [v]
            objets += v.infosJours as [any PersistentModel]
            objets += v.membres as [any PersistentModel]
            objets += v.depenses as [any PersistentModel]
            objets += v.reservations as [any PersistentModel]
            objets += v.etapes as [any PersistentModel]
            objets += v.documents as [any PersistentModel]
            objets += v.commentaires as [any PersistentModel]
            objets += v.avisEtapes as [any PersistentModel]
            objets += v.fichesFamilles as [any PersistentModel]
            objets += v.sondages as [any PersistentModel]
            objets += v.votes as [any PersistentModel]
            // Un objet supprimé reste dans les listes jusqu'à l'enregistrement de la base.
            for objet in objets where !objet.isDeleted {
                guard var etat = Self.etat(de: objet), !etat.uid.isEmpty else { continue }
                etat.voyageUID = v.uid
                sortie[Codec.nom(etat.type, etat.uid)] = etat
            }
        }
        return sortie
    }

    static func etat(de objet: any PersistentModel) -> Etat? {
        let record = Codec.enregistrement(pour: objet, zone: CKRecordZone.default().zoneID, systeme: nil, avecAsset: false)
        guard let type = TypeCloud(rawValue: record.recordType), type != .journal,
              let (_, uid) = Codec.analyser(record.recordID.recordName) else { return nil }
        let photo = (objet as? Document).flatMap { $0.estPhotoAlbum ? $0 : nil }
        return Etat(voyageUID: (record["voyageUID"] as? String) ?? "", type: type, uid: uid,
                    typeJournal: photo == nil ? type.rawValue : EntreeJournal.typePhoto,
                    groupe: photo.map { $0.etape?.uid ?? "" }, libelle: libelle(de: objet), champs: Codec.champs(de: record))
    }

    /// Le nom sous lequel l'objet apparaît dans le journal.
    static func libelle(de objet: any PersistentModel) -> String {
        switch objet {
        case let v as Voyage: return v.titre
        case let j as JourVoyage: return j.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case let m as Membre: return m.nomAffiche
        case let d as Depense: return d.titre
        case let r as Reservation: return r.titre.isEmpty ? r.type.libelle : r.titre
        case let e as Etape: return e.titre.isEmpty ? e.lieu : e.titre
        case let d as Document: return d.estPhotoAlbum ? (d.etape?.titre ?? d.nom) : d.nom
        case let c as Commentaire: return String(c.texte.prefix(60))
        case let a as AvisEtape: return a.voyage?.etapes.first { $0.uid == a.etapeUID }?.titre ?? ""
        case let f as Famille: return f.nom
        case let s as Sondage: return s.titre
        case let x as VoteSondage: return x.voyage?.sondages.first { $0.uid == x.sondageUID }?.titre ?? ""
        default: return ""
        }
    }
}

// MARK: - Présentation

extension EntreeJournal {
    static let typePhoto = "Photo"

    /// « l'étape », « la réservation »… (avec « une photo de l'album » pour les photos d'une étape).
    var objetAvecArticle: String {
        if typeObjet == Self.typePhoto {
            let photos = nombre > 1 ? "\(nombre) photos" : "une photo"
            return action == .suppression ? "\(photos) de l'album de" : "\(photos) à l'album de"
        }
        return switch TypeCloud(rawValue: typeObjet) {
        case .voyage?: "le voyage"
        case .jour?: "le jour"
        case .membre?: "le voyageur"
        case .depense?: "la dépense"
        case .reservation?: "la réservation"
        case .etape?: "l'étape"
        case .document?: "un document"
        case .commentaire?: "un message"
        case .avisEtape?: "son avis sur"
        case .famille?: "la famille"
        case .sondage?: "le vote"
        case .vote?: "son choix pour le vote"
        default: "un élément"
        }
    }

    /// La phrase de la ligne, sans l'auteur : « a modifié l'étape « Place du Tertre » ».
    var phrase: String {
        let nom = libelle.trimmingCharacters(in: .whitespaces)
        return "\(action.verbe) \(objetAvecArticle)" + (nom.isEmpty ? "" : " « \(nom) »")
    }

    /// Ce qui a changé, en clair (« Heure, Notes »).
    var champsEnClair: String {
        var vus = Set<String>()
        return champs.compactMap { cle -> String? in
            let nom = Self.nomsDeChamps[cle] ?? Self.decouper(cle)
            return vus.insert(nom).inserted ? nom : nil
        }.joined(separator: ", ")
    }

    private static func decouper(_ cle: String) -> String {
        var sortie = ""
        for c in cle {
            if c.isUppercase, !sortie.isEmpty { sortie += " " }
            sortie += sortie.isEmpty ? c.uppercased() : c.lowercased()
        }
        return sortie
    }

    static let nomsDeChamps: [String: String] = [
        "titre": "Titre", "lieu": "Lieu", "jour": "Jour", "apresJour": "Nuit", "heure": "Heure", "heureFin": "Heure de fin", "arriveeReelle": "Arrivée", "departReel": "Départ",
        "duree": "Durée", "notes": "Notes", "notesMiseEnFormeEmpreinte": "Notes", "latitude": "Position", "longitude": "Position",
        "ordre": "Ordre", "categorie": "Catégorie", "transport": "Transport", "transportJSON": "Transport", "parentUID": "Étape parente",
        "prixAdulte": "Prix adulte", "prixEnfant": "Prix enfant", "prixEtudiant": "Prix étudiant", "prixAdolescent": "Prix adolescent",
        "exclusBudget": "Budget", "basculesTarif": "Tarifs", "paysFavori": "Favori",
        "debut": "Début", "fin": "Fin", "destination": "Destination", "pays": "Pays", "date": "Date", "lieux": "Lieux",
        "montant": "Montant", "devise": "Devise", "payeurUID": "Payé par", "parts": "Répartition",
        "nom": "Nom", "nomFamille": "Nom de famille", "email": "E-mail", "role": "Rôle", "roleBrut": "Rôle", "famille": "Famille", "familleNom": "Famille",
        "fournisseur": "Fournisseur", "numeroConfirmation": "Numéro de confirmation", "prix": "Prix", "lien": "Lien", "siteWeb": "Site web",
        "taille": "Fichier", "importantUID": "Important", "typeDoc": "Type", "expireLe": "Validité", "etoiles": "Note", "commentaire": "Commentaire", "texte": "Texte",
        "deviseLocale": "Monnaie locale", "tauxChange": "Taux de change", "transportAller": "Transport aller", "transportRetour": "Transport retour",
        "options": "Options", "clos": "Clôture", "optionRetenue": "Choix retenu", "optionID": "Choix",
    ]
}
