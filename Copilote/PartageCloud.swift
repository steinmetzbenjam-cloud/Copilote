import Foundation
import SwiftData
import Observation
import CloudKit

/// Synchronisation et partage de voyages via iCloud (CloudKit).
///
/// Chaque voyage est une « zone » CloudKit dans la base privée de son créateur. L'inviter à d'autres personnes
/// partage la zone entière : elle apparaît alors dans la base partagée des invités, qui la lisent et la modifient.
///
/// Tout le code CloudKit est derrière l'option de compilation `ICLOUD` : il demande un compte Apple Developer
/// payant (voir SETUP-ICLOUD.md). Sans elle, l'app fonctionne normalement, sans synchronisation.
@MainActor @Observable
final class PartageCloud {
    static let shared = PartageCloud()

    static var disponible: Bool {
        #if ICLOUD
        true
        #else
        false
        #endif
    }

    /// Choix de l'utilisateur (Réglages).
    var actif = UserDefaults.standard.bool(forKey: "iCloudActif")
    var statut = ""
    var synchroEnCours = false

    @ObservationIgnored var contexte: ModelContext?

    func configurer(contexte: ModelContext) {
        self.contexte = contexte
        Identifiants.attribuer(dans: contexte)
        #if ICLOUD
        if actif { demarrer() }
        #endif
    }

    func definirActif(_ valeur: Bool) {
        actif = valeur
        UserDefaults.standard.set(valeur, forKey: "iCloudActif")
        #if ICLOUD
        if valeur { demarrer() } else { arreter() }
        #endif
    }

    #if !ICLOUD
    func accepter(_ metadata: CKShare.Metadata) async {}
    #endif

    // MARK: - Implémentation CloudKit

    #if ICLOUD

    static let identifiantConteneur = "iCloud.fr.steinmetz.Copilote"

    struct Meta: Codable {
        var empreinte: String
        var champsSysteme: Data?
        var zoneName: String
        var zoneOwner: String
    }

    @ObservationIgnored var conteneur: CKContainer?
    @ObservationIgnored var moteurPrive: CKSyncEngine?
    @ObservationIgnored var moteurPartage: CKSyncEngine?
    @ObservationIgnored var metas: [String: Meta] = [:]
    @ObservationIgnored var partages: [String: CKShare] = [:]
    @ObservationIgnored var dejaEnfile: [String: String] = [:]
    @ObservationIgnored var enVol: [String: String] = [:]
    @ObservationIgnored var orphelins: [CKRecord] = []
    @ObservationIgnored var boucle: Task<Void, Never>?

    private var dossier: URL {
        let d = URL.applicationSupportDirectory.appending(path: "Copilote", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func demarrer() {
        guard moteurPrive == nil else { return }
        let conteneur = CKContainer(identifier: Self.identifiantConteneur)
        self.conteneur = conteneur
        chargerMetas()

        moteurPrive = CKSyncEngine(.init(database: conteneur.privateCloudDatabase,
                                         stateSerialization: chargerEtat("prive"), delegate: self))
        moteurPartage = CKSyncEngine(.init(database: conteneur.sharedCloudDatabase,
                                           stateSerialization: chargerEtat("partage"), delegate: self))
        statut = "Synchronisation iCloud active."

        Task {
            let compte = try? await conteneur.accountStatus()
            if compte != .available { statut = "Connecte-toi à iCloud dans les Réglages de l'appareil." }
        }
        boucle = Task { [weak self] in
            while !Task.isCancelled {
                self?.verifierChangementsLocaux()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func arreter() {
        boucle?.cancel()
        boucle = nil
        moteurPrive = nil
        moteurPartage = nil
        statut = ""
    }

    // MARK: Persistance de l'état de synchronisation

    private func chargerEtat(_ nom: String) -> CKSyncEngine.State.Serialization? {
        guard let donnees = try? Data(contentsOf: dossier.appending(path: "etat-\(nom).json")) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: donnees)
    }

    func sauvegarderEtat(_ etat: CKSyncEngine.State.Serialization, prive: Bool) {
        guard let donnees = try? JSONEncoder().encode(etat) else { return }
        try? donnees.write(to: dossier.appending(path: "etat-\(prive ? "prive" : "partage").json"))
    }

    private func chargerMetas() {
        guard let donnees = try? Data(contentsOf: dossier.appending(path: "metas.json")) else { return }
        metas = (try? JSONDecoder().decode([String: Meta].self, from: donnees)) ?? [:]
    }

    func sauvegarderMetas() {
        guard let donnees = try? JSONEncoder().encode(metas) else { return }
        try? donnees.write(to: dossier.appending(path: "metas.json"))
    }

    func oublierTout() {
        metas = [:]
        dejaEnfile = [:]
        for nom in ["etat-prive.json", "etat-partage.json", "metas.json"] {
            try? FileManager.default.removeItem(at: dossier.appending(path: nom))
        }
    }

    // MARK: Détection des changements locaux

    func moteur(pourProprietaire proprietaire: String) -> CKSyncEngine? {
        proprietaire == CKCurrentUserDefaultName ? moteurPrive : moteurPartage
    }

    func verifierChangementsLocaux() {
        guard actif, let contexte, moteurPrive != nil else { return }
        let entrees = Codec.instantane(contexte)
        var presents = Set<String>()
        var zonesAjoutees = Set<String>()

        for e in entrees {
            presents.insert(e.nom)
            let connue = metas[e.nom]
            if connue?.empreinte == e.empreinte || dejaEnfile[e.nom] == e.empreinte { continue }
            guard let moteur = moteur(pourProprietaire: e.zone.ownerName) else { continue }
            if connue == nil, e.type == .voyage, e.zone.ownerName == CKCurrentUserDefaultName, zonesAjoutees.insert(e.zone.zoneName).inserted {
                moteur.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: e.zone))])
            }
            moteur.state.add(pendingRecordZoneChanges: [.saveRecord(CKRecord.ID(recordName: e.nom, zoneID: e.zone))])
            dejaEnfile[e.nom] = e.empreinte
        }

        // Ce qui existait et a disparu : suppression (zone entière si c'est le voyage).
        let voyagesSupprimes = Set(metas.filter { $0.key.hasPrefix("Voyage-") && !presents.contains($0.key) }.map(\.value.zoneName))
        for (nom, meta) in metas where !presents.contains(nom) {
            let zone = CKRecordZone.ID(zoneName: meta.zoneName, ownerName: meta.zoneOwner)
            guard let moteur = moteur(pourProprietaire: meta.zoneOwner) else { continue }
            if nom.hasPrefix("Voyage-") {
                moteur.state.add(pendingDatabaseChanges: [.deleteZone(zone)])
            } else if !voyagesSupprimes.contains(meta.zoneName) {
                moteur.state.add(pendingRecordZoneChanges: [.deleteRecord(CKRecord.ID(recordName: nom, zoneID: zone))])
            }
            if nom.hasPrefix("Voyage-") || voyagesSupprimes.contains(meta.zoneName) {
                metas.removeValue(forKey: nom)
            }
        }
        if !voyagesSupprimes.isEmpty { sauvegarderMetas() }
    }

    // MARK: Réception des changements distants

    func appliquer(enregistrements: [CKRecord], suppressions: [CKRecord.ID]) {
        guard let contexte else { return }
        // Seules les zones de voyages nous concernent (pas la zone temporaire de l'outil de schéma).
        var aTraiter = (orphelins + enregistrements).filter { $0.recordID.zoneID.zoneName.hasPrefix("voyage-") }
        orphelins = []

        for record in aTraiter where record is CKShare {
            guard let share = record as? CKShare else { continue }
            partages[share.recordID.zoneID.zoneName] = share
            if let voyage = Codec.voyage(uid: Codec.uid(zone: share.recordID.zoneID.zoneName), contexte) {
                voyage.partage = true
                voyage.participantsCloud = Self.noms(des: share)
            }
        }
        aTraiter.removeAll { $0 is CKShare }
        aTraiter.sort { Codec.ordre($0.recordType) < Codec.ordre($1.recordType) }

        for record in aTraiter {
            if let objet = Codec.appliquer(record, contexte) {
                let nom = record.recordID.recordName
                metas[nom] = Meta(empreinte: Codec.empreinte(de: objet), champsSysteme: Codec.champsSysteme(record),
                                  zoneName: record.recordID.zoneID.zoneName, zoneOwner: record.recordID.zoneID.ownerName)
                dejaEnfile.removeValue(forKey: nom)
            } else if record.recordType != "cloudkit.share" {
                orphelins.append(record)
            }
        }

        for id in suppressions {
            if id.recordName == "cloudkit.zoneshare" {
                partages.removeValue(forKey: id.zoneID.zoneName)
                Codec.voyage(uid: Codec.uid(zone: id.zoneID.zoneName), contexte)?.partage = false
                continue
            }
            Codec.supprimer(recordName: id.recordName, contexte)
            metas.removeValue(forKey: id.recordName)
            dejaEnfile.removeValue(forKey: id.recordName)
        }
        try? contexte.save()
        sauvegarderMetas()
    }

    func supprimerVoyage(zone: CKRecordZone.ID) {
        guard let contexte else { return }
        if let voyage = Codec.voyage(uid: Codec.uid(zone: zone.zoneName), contexte) {
            contexte.delete(voyage)
            try? contexte.save()
        }
        for (nom, meta) in metas where meta.zoneName == zone.zoneName { metas.removeValue(forKey: nom) }
        partages.removeValue(forKey: zone.zoneName)
        sauvegarderMetas()
    }

    static func noms(des share: CKShare) -> [String] {
        share.participants
            .filter { $0.role != .owner || $0 !== share.owner }
            .map { p in
                p.userIdentity.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) }
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "Invité"
            }
    }

    // MARK: Envoi

    func enregistrementAEnvoyer(_ id: CKRecord.ID) -> CKRecord? {
        guard let contexte, let objet = Codec.objet(recordName: id.recordName, contexte) else { return nil }
        let record = Codec.enregistrement(pour: objet, zone: id.zoneID, systeme: metas[id.recordName]?.champsSysteme, avecAsset: true)
        enVol[id.recordName] = Codec.empreinte(de: record)
        return record
    }

    func apresEnvoi(_ e: CKSyncEngine.Event.SentRecordZoneChanges, moteur: CKSyncEngine) {
        for record in e.savedRecords {
            let nom = record.recordID.recordName
            metas[nom] = Meta(empreinte: enVol[nom] ?? Codec.empreinte(de: record), champsSysteme: Codec.champsSysteme(record),
                              zoneName: record.recordID.zoneID.zoneName, zoneOwner: record.recordID.zoneID.ownerName)
            enVol.removeValue(forKey: nom)
            dejaEnfile.removeValue(forKey: nom)
        }
        for id in e.deletedRecordIDs { metas.removeValue(forKey: id.recordName) }

        for echec in e.failedRecordSaves {
            let id = echec.record.recordID
            dejaEnfile.removeValue(forKey: id.recordName)
            switch echec.error.code {
            case .serverRecordChanged:
                // Conflit : on repart de la version du serveur, et nos valeurs sont renvoyées par-dessus.
                if let serveur = echec.error.serverRecord {
                    var meta = metas[id.recordName] ?? Meta(empreinte: "", champsSysteme: nil, zoneName: id.zoneID.zoneName, zoneOwner: id.zoneID.ownerName)
                    meta.champsSysteme = Codec.champsSysteme(serveur)
                    metas[id.recordName] = meta
                    moteur.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                }
            case .zoneNotFound:
                moteur.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                moteur.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .unknownItem:
                metas.removeValue(forKey: id.recordName)
            case .quotaExceeded:
                statut = "Espace iCloud insuffisant."
            case .notAuthenticated:
                statut = "Connecte-toi à iCloud dans les Réglages de l'appareil."
            default:
                statut = "Synchronisation : \(echec.error.localizedDescription)"
            }
        }
        sauvegarderMetas()
    }

    func gererCompte(_ e: CKSyncEngine.Event.AccountChange) {
        switch e.changeType {
        case .signIn: statut = "Synchronisation iCloud active."
        case .signOut, .switchAccounts:
            oublierTout()
            statut = "Le compte iCloud a changé : les voyages seront renvoyés vers le nouveau compte."
        @unknown default: break
        }
    }

    // MARK: Partage

    /// Prépare l'invitation d'un voyage : s'assure qu'il est bien dans iCloud, puis crée (ou retrouve) le partage.
    func preparerPartage(_ voyage: Voyage) async throws -> (CKShare, CKContainer) {
        guard let conteneur, let moteurPrive else { throw ErreurPartage.inactif }
        verifierChangementsLocaux()
        try await moteurPrive.sendChanges()
        let zone = Codec.zone(de: voyage)
        if let existant = partages[zone.zoneName] { return (existant, conteneur) }

        let share = CKShare(recordZoneID: zone)
        share[CKShare.SystemFieldKey.title] = voyage.titre
        share.publicPermission = .none
        let (resultats, _) = try await conteneur.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard case .success(let enregistre)? = resultats[share.recordID], let sauve = enregistre as? CKShare else {
            var detail: String?
            if case .failure(let erreur)? = resultats[share.recordID] { detail = Self.decrire(erreur) }
            throw ErreurPartage.refuse(detail)
        }
        partages[zone.zoneName] = sauve
        voyage.partage = true
        return (sauve, conteneur)
    }

    func accepter(_ metadata: CKShare.Metadata) async {
        if !actif { definirActif(true) }
        guard let conteneur else { statut = "iCloud n'est pas disponible."; return }
        do {
            _ = try await conteneur.accept(metadata)
            try await moteurPartage?.fetchChanges()
            statut = "Voyage reçu."
        } catch {
            statut = "Impossible d'accepter l'invitation : \(error.localizedDescription)"
        }
    }

    enum ErreurPartage: LocalizedError {
        case inactif, refuse(String?)
        var errorDescription: String? {
            switch self {
            case .inactif: "Active d'abord la synchronisation iCloud dans les Réglages."
            case .refuse(let detail): "iCloud a refusé de créer l'invitation" + (detail.map { " (\($0))." } ?? ".")
            }
        }
    }

    /// Code et texte de l'erreur CloudKit, pour comprendre ce qui bloque.
    static func decrire(_ erreur: Error) -> String {
        let e = erreur as NSError
        return "\(e.domain) \(e.code) : \(e.localizedDescription)"
    }

    #endif
}

// MARK: - CloudKit : réception des événements

#if ICLOUD
extension PartageCloud: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            sauvegarderEtat(e.stateSerialization, prive: syncEngine === moteurPrive)
        case .accountChange(let e):
            gererCompte(e)
        case .fetchedDatabaseChanges(let e):
            for suppression in e.deletions { supprimerVoyage(zone: suppression.zoneID) }
        case .fetchedRecordZoneChanges(let e):
            appliquer(enregistrements: e.modifications.map(\.record), suppressions: e.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let e):
            apresEnvoi(e, moteur: syncEngine)
        case .willFetchChanges, .willSendChanges: synchroEnCours = true
        case .didFetchChanges, .didSendChanges: synchroEnCours = false
        default: break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changements = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changements) { id in
            await self.enregistrementAEnvoyer(id)
        }
    }
}
#endif
