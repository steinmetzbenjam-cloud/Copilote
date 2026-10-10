#if ICLOUD && DEBUG
import Foundation
import CloudKit
import SwiftData

/// Outil de développement : envoie dans le schéma iCloud « développement » TOUS les champs de TOUS les types.
///
/// CloudKit ne crée un champ qu'à la première valeur renseignée, et refuse d'en créer en production.
/// Il faut donc que chaque champ ait servi au moins une fois en développement avant de déployer le schéma.
extension PartageCloud {
    func initialiserSchema() async -> String {
        let conteneur = self.conteneur ?? CKContainer(identifier: Self.identifiantConteneur)
        let base = conteneur.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "schema-init")
        do {
            let records = try Self.enregistrementsComplets(zone: zone.zoneID)
            _ = try await base.modifyRecordZones(saving: [zone], deleting: [])
            let (resultats, _) = try await base.modifyRecords(saving: records, deleting: [])
            let echecs = resultats.compactMap { id, resultat -> String? in
                if case .failure(let erreur) = resultat { return "\(id.recordName.prefix(12)) : \(erreur.localizedDescription)" }
                return nil
            }
            _ = try? await base.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            return echecs.isEmpty
                ? "Schéma complet envoyé (\(records.count) types). Déploie-le maintenant depuis la console CloudKit."
                : "Échec : " + echecs.joined(separator: " ; ")
        } catch {
            _ = try? await base.modifyRecordZones(saving: [], deleting: [zone.zoneID])
            return "Échec : \(error.localizedDescription)"
        }
    }

    /// Un exemplaire de chaque type, avec tous les champs optionnels renseignés (construit par le même code que la synchronisation).
    @MainActor private static func enregistrementsComplets(zone: CKRecordZone.ID) throws -> [CKRecord] {
        let conteneur = try ModelContainer(
            for: Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self, Depense.self, Commentaire.self, AvisEtape.self, Famille.self, Sondage.self, VoteSondage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let contexte = conteneur.mainContext

        let voyage = Voyage(titre: "Exemple", destination: "Exemple")
        voyage.pays = ["FR"]; voyage.notes = "x"
        voyage.transportAllerJSON = "x"; voyage.transportRetourJSON = "x"; voyage.deviseLocale = "x"; voyage.tauxChange = 1; voyage.fuseauReferenceId = "x"
        contexte.insert(voyage)

        let membre = Membre(nom: "Exemple"); membre.voyage = voyage
        membre.nomFamille = "x"; membre.email = "x"; membre.familleNom = "x"; membre.age = 1; membre.tarifBrut = "x"; membre.emailInvitation = "x"; membre.roleBrut = "x"; membre.avatar = Data("x".utf8)
        contexte.insert(membre)

        let jour = JourVoyage(date: .now); jour.titre = "x"; jour.notes = "x"; jour.voyage = voyage
        jour.lieux = [LieuReference(nom: "x", detail: "x", latitude: 1, longitude: 1, codePays: "FR", estPays: true)]
        contexte.insert(jour)

        let etape = Etape(titre: "x", jour: .now)
        etape.lieu = "x"; etape.heure = .now; etape.heureFin = .now; etape.duree = 1; etape.fuseauChoisi = "x"; etape.apresJour = true; etape.transportJSON = "x"; etape.notes = "x"; etape.latitude = 1; etape.longitude = 1; etape.ordre = 1
        etape.resume = "x"; etape.horaires = "x"; etape.photoURL = "x"
        etape.noteGoogle = 1; etape.avisGoogle = 1; etape.lienGoogle = "x"
        etape.noteTripadvisor = 1; etape.avisTripadvisor = 1; etape.lienTripadvisor = "x"; etape.siteWeb = "x"
        etape.prixAdulte = 1; etape.prixEnfant = 1; etape.prixEtudiant = 1
        etape.prixAdulteLocal = true; etape.prixEnfantLocal = true; etape.prixEtudiantLocal = true
        etape.voyage = voyage; contexte.insert(etape)

        let reservation = Reservation(type: .vol, debut: .now)
        reservation.titre = "x"; reservation.fournisseur = "x"; reservation.numeroConfirmation = "x"
        reservation.fin = .now; reservation.lieu = "x"; reservation.prix = 1; reservation.devise = "EUR"; reservation.fuseauDebutId = "x"; reservation.fuseauFinId = "x"; reservation.notes = "x"
        reservation.voyage = voyage; contexte.insert(reservation)

        let document = Document(nom: "x", extensionFichier: "txt", donnees: Data("x".utf8))
        document.voyage = voyage; document.reservation = reservation; document.etape = etape; document.membreUID = "x"; document.typeBrut = "x"; document.expireLe = .now; document.notes = "x"; contexte.insert(document)

        let depense = Depense(devise: "EUR", payeurUID: membre.uid)
        depense.titre = "x"; depense.etapeUID = "x"; depense.montant = 1; depense.notes = "x"
        depense.parts = [PartDepense(membreUID: membre.uid, montant: 1)]
        depense.voyage = voyage; contexte.insert(depense)

        let commentaire = Commentaire(texte: "x", auteurUID: membre.uid)
        commentaire.voyage = voyage; contexte.insert(commentaire)

        let avis = AvisEtape(etapeUID: etape.uid, auteurUID: membre.uid)
        avis.etoiles = 1; avis.envie = .incontournable; avis.commentaire = "x"
        avis.voyage = voyage; contexte.insert(avis)

        let famille = Famille(nom: "x"); famille.avatar = Data("x".utf8); famille.voyage = voyage; contexte.insert(famille)

        let sondage = Sondage(titre: "x", auteurUID: membre.uid); sondage.notes = "x"; sondage.optionsJSON = "[]"; sondage.clos = true; sondage.optionRetenue = "x"
        sondage.voyage = voyage; contexte.insert(sondage)
        let vote = VoteSondage(sondageUID: sondage.uid, optionID: "x", compteCle: "m:x", auteurUID: membre.uid)
        vote.voyage = voyage; contexte.insert(vote)

        let objets: [any PersistentModel] = [voyage, membre, jour, etape, reservation, document, depense, commentaire, avis, famille, sondage, vote]
        return objets.map { Codec.enregistrement(pour: $0, zone: zone, systeme: nil, avecAsset: true) }
    }
}
#endif
