import Foundation
import SwiftData
import CloudKit

enum TypeCloud: String, CaseIterable {
    case voyage = "Voyage", jour = "Jour", membre = "Membre", depense = "Depense", reservation = "Reservation", etape = "Etape", document = "Document"
    case commentaire = "Commentaire", avisEtape = "AvisEtape"
}

/// Donne un identifiant stable aux objets créés avant l'arrivée de la synchronisation.
enum Identifiants {
    @MainActor static func attribuer(dans contexte: ModelContext) {
        func remplir<T: PersistentModel>(_ type: T.Type, _ chemin: ReferenceWritableKeyPath<T, String>) {
            for objet in (try? contexte.fetch(FetchDescriptor<T>())) ?? [] where objet[keyPath: chemin].isEmpty {
                objet[keyPath: chemin] = UUID().uuidString
            }
        }
        remplir(Voyage.self, \.uid)
        remplir(Membre.self, \.uid)
        remplir(Etape.self, \.uid)
        remplir(Reservation.self, \.uid)
        remplir(Document.self, \.uid)
        remplir(JourVoyage.self, \.uid)
        remplir(Depense.self, \.uid)
        remplir(Commentaire.self, \.uid)
        remplir(AvisEtape.self, \.uid)
        try? contexte.save()
    }
}

/// Conversion des objets de l'app en enregistrements CloudKit, et inversement.
enum Codec {
    struct Entree {
        var nom: String
        var type: TypeCloud
        var zone: CKRecordZone.ID
        var empreinte: String
    }

    // MARK: Noms et zones

    static func nom(_ type: TypeCloud, _ uid: String) -> String { "\(type.rawValue)-\(uid)" }

    static func analyser(_ recordName: String) -> (TypeCloud, String)? {
        guard let tiret = recordName.firstIndex(of: "-"), let type = TypeCloud(rawValue: String(recordName[..<tiret])) else { return nil }
        return (type, String(recordName[recordName.index(after: tiret)...]))
    }

    static func zone(de voyage: Voyage) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "voyage-\(voyage.uid)",
                        ownerName: voyage.zoneProprietaire.isEmpty ? CKCurrentUserDefaultName : voyage.zoneProprietaire)
    }

    static func uid(zone zoneName: String) -> String { String(zoneName.dropFirst("voyage-".count)) }

    /// Les voyages d'abord, puis ce qui en dépend.
    static func ordre(_ recordType: String) -> Int {
        TypeCloud.allCases.firstIndex { $0.rawValue == recordType } ?? 99
    }

    // MARK: Recherche d'objets

    static func voyage(uid: String, _ contexte: ModelContext) -> Voyage? {
        try? contexte.fetch(FetchDescriptor<Voyage>(predicate: #Predicate { $0.uid == uid })).first
    }

    static func objet(recordName: String, _ contexte: ModelContext) -> (any PersistentModel)? {
        guard let (type, uid) = analyser(recordName) else { return nil }
        switch type {
        case .voyage: return try? contexte.fetch(FetchDescriptor<Voyage>(predicate: #Predicate { $0.uid == uid })).first
        case .membre: return try? contexte.fetch(FetchDescriptor<Membre>(predicate: #Predicate { $0.uid == uid })).first
        case .reservation: return try? contexte.fetch(FetchDescriptor<Reservation>(predicate: #Predicate { $0.uid == uid })).first
        case .etape: return try? contexte.fetch(FetchDescriptor<Etape>(predicate: #Predicate { $0.uid == uid })).first
        case .document: return try? contexte.fetch(FetchDescriptor<Document>(predicate: #Predicate { $0.uid == uid })).first
        case .jour: return try? contexte.fetch(FetchDescriptor<JourVoyage>(predicate: #Predicate { $0.uid == uid })).first
        case .depense: return try? contexte.fetch(FetchDescriptor<Depense>(predicate: #Predicate { $0.uid == uid })).first
        case .commentaire: return try? contexte.fetch(FetchDescriptor<Commentaire>(predicate: #Predicate { $0.uid == uid })).first
        case .avisEtape: return try? contexte.fetch(FetchDescriptor<AvisEtape>(predicate: #Predicate { $0.uid == uid })).first
        }
    }

    static func supprimer(recordName: String, _ contexte: ModelContext) {
        if let objet = objet(recordName: recordName, contexte) { contexte.delete(objet) }
    }

    // MARK: Instantané local

    @MainActor static func instantane(_ contexte: ModelContext) -> [Entree] {
        var entrees: [Entree] = []
        let zoneDefaut = CKRecordZone.default().zoneID
        func ajouter(_ objet: any PersistentModel, _ type: TypeCloud, _ uid: String, _ zone: CKRecordZone.ID) {
            guard !uid.isEmpty else { return }
            let record = enregistrement(pour: objet, zone: zoneDefaut, systeme: nil, avecAsset: false)
            entrees.append(Entree(nom: nom(type, uid), type: type, zone: zone, empreinte: empreinte(de: record)))
        }
        for v in (try? contexte.fetch(FetchDescriptor<Voyage>())) ?? [] where !v.uid.isEmpty {
            let zone = zone(de: v)
            ajouter(v, .voyage, v.uid, zone)
            for j in v.infosJours { ajouter(j, .jour, j.uid, zone) }
            for x in v.depenses { ajouter(x, .depense, x.uid, zone) }
            for m in v.membres { ajouter(m, .membre, m.uid, zone) }
            for r in v.reservations { ajouter(r, .reservation, r.uid, zone) }
            for e in v.etapes { ajouter(e, .etape, e.uid, zone) }
            for d in v.documents { ajouter(d, .document, d.uid, zone) }
            for c in v.commentaires { ajouter(c, .commentaire, c.uid, zone) }
            for a in v.avisEtapes { ajouter(a, .avisEtape, a.uid, zone) }
        }
        return entrees
    }

    // MARK: Empreintes

    static func empreinte(de objet: any PersistentModel) -> String {
        empreinte(de: enregistrement(pour: objet, zone: CKRecordZone.default().zoneID, systeme: nil, avecAsset: false))
    }

    /// Résumé stable du contenu : sert à savoir si un objet a changé depuis la dernière synchronisation.
    static func empreinte(de record: CKRecord) -> String {
        record.allKeys().sorted().compactMap { cle -> String? in
            guard let valeur = record[cle], !(valeur is CKAsset) else { return nil }
            if let date = valeur as? Date { return "\(cle)=\(Int(date.timeIntervalSince1970))" }
            if let nombre = valeur as? NSNumber { return "\(cle)=\(nombre.doubleValue)" }
            if let liste = valeur as? [String] { return "\(cle)=\(liste.joined(separator: ","))" }
            return "\(cle)=\(valeur)"
        }.joined(separator: "|")
    }

    // MARK: Objet → enregistrement

    static func champsSysteme(_ record: CKRecord) -> Data {
        let archiveur = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiveur)
        archiveur.finishEncoding()
        return archiveur.encodedData
    }

    private static func base(_ type: TypeCloud, _ uid: String, _ zone: CKRecordZone.ID, _ systeme: Data?) -> CKRecord {
        if let systeme, let lecteur = try? NSKeyedUnarchiver(forReadingFrom: systeme) {
            lecteur.requiresSecureCoding = true
            let record = CKRecord(coder: lecteur)
            lecteur.finishDecoding()
            if let record { return record }
        }
        return CKRecord(recordType: type.rawValue, recordID: CKRecord.ID(recordName: nom(type, uid), zoneID: zone))
    }

    static func enregistrement(pour objet: any PersistentModel, zone: CKRecordZone.ID, systeme: Data?, avecAsset: Bool) -> CKRecord {
        switch objet {
        case let v as Voyage:
            let r = base(.voyage, v.uid, zone, systeme)
            r["titre"] = v.titre; r["destination"] = v.destination
            r["debut"] = v.debut; r["fin"] = v.fin; r["notes"] = v.notes
            r["pays"] = v.pays; r["creeLe"] = v.creeLe
            r["transportAller"] = v.transportAllerJSON; r["transportRetour"] = v.transportRetourJSON
            return r
        case let j as JourVoyage:
            let r = base(.jour, j.uid, zone, systeme)
            r["date"] = j.date; r["titre"] = j.titre; r["notes"] = j.notes; r["creeLe"] = j.creeLe
            r["lieux"] = lieuxEnTexte(j.lieux); r["voyageUID"] = j.voyage?.uid
            return r
        case let x as Depense:
            let r = base(.depense, x.uid, zone, systeme)
            r["titre"] = x.titre; r["montant"] = x.montant; r["devise"] = x.devise; r["date"] = x.date
            r["categorie"] = x.categorie.rawValue; r["payeurUID"] = x.payeurUID; r["notes"] = x.notes
            r["precise"] = x.repartitionPrecise ? 1 : 0; r["remboursement"] = x.estRemboursement ? 1 : 0
            r["parts"] = partsEnTexte(x.parts); r["creeLe"] = x.creeLe; r["voyageUID"] = x.voyage?.uid
            return r
        case let m as Membre:
            let r = base(.membre, m.uid, zone, systeme)
            r["nom"] = m.nom; r["creeLe"] = m.creeLe; r["voyageUID"] = m.voyage?.uid
            return r
        case let e as Etape:
            let r = base(.etape, e.uid, zone, systeme)
            r["titre"] = e.titre; r["lieu"] = e.lieu; r["jour"] = e.jour; r["heure"] = e.heure; r["heureFin"] = e.heureFin; r["apresJour"] = e.apresJour ? 1 : 0; r["transportJSON"] = e.transportJSON
            r["categorie"] = e.categorie.rawValue; r["notes"] = e.notes
            r["latitude"] = e.latitude; r["longitude"] = e.longitude
            r["ordre"] = e.ordre
            r["resume"] = e.resume; r["horaires"] = e.horaires; r["photoURL"] = e.photoURL
            r["noteGoogle"] = e.noteGoogle; r["avisGoogle"] = e.avisGoogle; r["lienGoogle"] = e.lienGoogle
            r["noteTripadvisor"] = e.noteTripadvisor; r["avisTripadvisor"] = e.avisTripadvisor; r["lienTripadvisor"] = e.lienTripadvisor
            r["siteWeb"] = e.siteWeb; r["creeLe"] = e.creeLe; r["voyageUID"] = e.voyage?.uid
            return r
        case let x as Reservation:
            let r = base(.reservation, x.uid, zone, systeme)
            r["type"] = x.type.rawValue; r["titre"] = x.titre; r["fournisseur"] = x.fournisseur
            r["numeroConfirmation"] = x.numeroConfirmation; r["debut"] = x.debut; r["fin"] = x.fin
            r["lieu"] = x.lieu; r["prix"] = x.prix; r["devise"] = x.devise; r["notes"] = x.notes
            r["ajouteeAItineraire"] = x.ajouteeAItineraire ? 1 : 0; r["creeLe"] = x.creeLe; r["voyageUID"] = x.voyage?.uid
            return r
        case let d as Document:
            let r = base(.document, d.uid, zone, systeme)
            r["nom"] = d.nom; r["extensionFichier"] = d.extensionFichier; r["taille"] = d.donnees.count
            r["creeLe"] = d.creeLe; r["voyageUID"] = d.voyage?.uid; r["reservationUID"] = d.reservation?.uid
            r["etapeUID"] = d.etape?.uid
            if avecAsset {
                let fichier = FileManager.default.temporaryDirectory.appending(path: "\(d.uid).\(d.extensionFichier)")
                if (try? d.donnees.write(to: fichier)) != nil { r["donnees"] = CKAsset(fileURL: fichier) }
            }
            return r
        case let c as Commentaire:
            let r = base(.commentaire, c.uid, zone, systeme)
            r["texte"] = c.texte; r["auteurUID"] = c.auteurUID; r["date"] = c.date; r["voyageUID"] = c.voyage?.uid
            return r
        case let a as AvisEtape:
            let r = base(.avisEtape, a.uid, zone, systeme)
            r["etapeUID"] = a.etapeUID; r["auteurUID"] = a.auteurUID; r["etoiles"] = a.etoiles
            r["envie"] = a.envie.rawValue; r["commentaire"] = a.commentaire; r["modifieLe"] = a.modifieLe
            r["voyageUID"] = a.voyage?.uid
            return r
        default:
            fatalError("Type d'objet inconnu")
        }
    }

    static func lieuxEnTexte(_ lieux: [LieuReference]) -> String {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = .sortedKeys
        return (try? encodeur.encode(lieux)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func partsEnTexte(_ parts: [PartDepense]) -> String {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = .sortedKeys
        return (try? encodeur.encode(parts)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func partsDepuisTexte(_ texte: String?) -> [PartDepense] {
        texte.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([PartDepense].self, from: $0) } ?? []
    }

    static func lieuxDepuisTexte(_ texte: String?) -> [LieuReference] {
        texte.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([LieuReference].self, from: $0) } ?? []
    }

    // MARK: Enregistrement → objet

    /// Crée ou met à jour l'objet local. Renvoie nil si l'objet parent n'est pas encore arrivé.
    @MainActor static func appliquer(_ r: CKRecord, _ contexte: ModelContext) -> (any PersistentModel)? {
        guard let type = TypeCloud(rawValue: r.recordType), let (_, uid) = analyser(r.recordID.recordName) else { return nil }
        func texte(_ cle: String) -> String { r[cle] as? String ?? "" }
        func date(_ cle: String) -> Date? { r[cle] as? Date }
        func nombre(_ cle: String) -> Double? { (r[cle] as? NSNumber)?.doubleValue }
        func entier(_ cle: String) -> Int? { (r[cle] as? NSNumber)?.intValue }
        let parent = (r["voyageUID"] as? String).flatMap { voyage(uid: $0, contexte) }

        switch type {
        case .voyage:
            let v = voyage(uid: uid, contexte) ?? {
                let nouveau = Voyage(titre: "")
                nouveau.uid = uid
                contexte.insert(nouveau)
                return nouveau
            }()
            v.titre = texte("titre"); v.destination = texte("destination")
            v.debut = date("debut") ?? v.debut; v.fin = date("fin") ?? v.fin; v.notes = texte("notes")
            v.pays = r["pays"] as? [String] ?? []; v.creeLe = date("creeLe") ?? v.creeLe
            v.transportAllerJSON = r["transportAller"] as? String; v.transportRetourJSON = r["transportRetour"] as? String
            let proprietaire = r.recordID.zoneID.ownerName
            v.zoneProprietaire = proprietaire == CKCurrentUserDefaultName ? "" : proprietaire
            return v

        case .jour:
            guard let parent else { return nil }
            let j = (objet(recordName: r.recordID.recordName, contexte) as? JourVoyage) ?? {
                let nouveau = JourVoyage(date: .now); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            j.date = date("date") ?? j.date; j.titre = texte("titre"); j.notes = texte("notes")
            j.lieux = lieuxDepuisTexte(r["lieux"] as? String); j.creeLe = date("creeLe") ?? j.creeLe; j.voyage = parent
            return j

        case .depense:
            guard let parent else { return nil }
            let x = (objet(recordName: r.recordID.recordName, contexte) as? Depense) ?? {
                let nouveau = Depense(devise: "EUR"); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            x.titre = texte("titre"); x.montant = nombre("montant") ?? 0; x.devise = texte("devise"); x.date = date("date") ?? x.date
            x.categorie = CategorieDepense(rawValue: texte("categorie")) ?? .autre; x.payeurUID = texte("payeurUID"); x.notes = texte("notes")
            x.repartitionPrecise = (entier("precise") ?? 0) == 1; x.estRemboursement = (entier("remboursement") ?? 0) == 1
            x.parts = partsDepuisTexte(r["parts"] as? String); x.creeLe = date("creeLe") ?? x.creeLe; x.voyage = parent
            return x

        case .membre:
            guard let parent else { return nil }
            let m = (objet(recordName: r.recordID.recordName, contexte) as? Membre) ?? {
                let nouveau = Membre(nom: ""); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            m.nom = texte("nom"); m.creeLe = date("creeLe") ?? m.creeLe; m.voyage = parent
            return m

        case .etape:
            guard let parent else { return nil }
            let e = (objet(recordName: r.recordID.recordName, contexte) as? Etape) ?? {
                let nouveau = Etape(titre: "", jour: .now); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            e.titre = texte("titre"); e.lieu = texte("lieu"); e.jour = date("jour"); e.heure = date("heure"); e.heureFin = date("heureFin"); e.apresJour = nombre("apresJour") == 1; e.transportJSON = r["transportJSON"] as? String
            e.categorie = CategorieEtape(rawValue: texte("categorie")) ?? .autre; e.notes = texte("notes")
            e.latitude = nombre("latitude"); e.longitude = nombre("longitude"); e.ordre = nombre("ordre") ?? 0
            e.resume = r["resume"] as? String; e.horaires = r["horaires"] as? String; e.photoURL = r["photoURL"] as? String
            e.noteGoogle = nombre("noteGoogle"); e.avisGoogle = entier("avisGoogle"); e.lienGoogle = r["lienGoogle"] as? String
            e.noteTripadvisor = nombre("noteTripadvisor"); e.avisTripadvisor = entier("avisTripadvisor")
            e.lienTripadvisor = r["lienTripadvisor"] as? String
            e.siteWeb = r["siteWeb"] as? String; e.creeLe = date("creeLe") ?? e.creeLe; e.voyage = parent
            return e

        case .reservation:
            guard let parent else { return nil }
            let x = (objet(recordName: r.recordID.recordName, contexte) as? Reservation) ?? {
                let nouveau = Reservation(); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            x.type = TypeReservation(rawValue: texte("type")) ?? .autre; x.titre = texte("titre")
            x.fournisseur = texte("fournisseur"); x.numeroConfirmation = texte("numeroConfirmation")
            x.debut = date("debut") ?? x.debut; x.fin = date("fin"); x.lieu = texte("lieu")
            x.prix = nombre("prix"); x.devise = texte("devise"); x.notes = texte("notes")
            x.ajouteeAItineraire = (entier("ajouteeAItineraire") ?? 0) == 1
            x.creeLe = date("creeLe") ?? x.creeLe; x.voyage = parent
            return x

        case .document:
            guard let parent else { return nil }
            let reservationUID = r["reservationUID"] as? String
            let reservation = reservationUID.flatMap { objet(recordName: nom(.reservation, $0), contexte) as? Reservation }
            if reservationUID != nil && reservation == nil { return nil }
            let etapeUID = r["etapeUID"] as? String
            let etape = etapeUID.flatMap { objet(recordName: nom(.etape, $0), contexte) as? Etape }
            if etapeUID != nil && etape == nil { return nil }
            let d = (objet(recordName: r.recordID.recordName, contexte) as? Document) ?? {
                let nouveau = Document(nom: "", extensionFichier: "", donnees: Data()); nouveau.uid = uid
                contexte.insert(nouveau); return nouveau
            }()
            d.nom = texte("nom"); d.extensionFichier = texte("extensionFichier"); d.creeLe = date("creeLe") ?? d.creeLe
            if let fichier = (r["donnees"] as? CKAsset)?.fileURL, let donnees = try? Data(contentsOf: fichier) { d.donnees = donnees }
            d.voyage = parent; d.reservation = reservation; d.etape = etape
            return d

        case .commentaire:
            guard let parent else { return nil }
            let c = (objet(recordName: r.recordID.recordName, contexte) as? Commentaire) ?? {
                let nouveau = Commentaire(texte: "", auteurUID: ""); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            c.texte = texte("texte"); c.auteurUID = texte("auteurUID"); c.date = date("date") ?? c.date; c.voyage = parent
            return c

        case .avisEtape:
            guard let parent else { return nil }
            let a = (objet(recordName: r.recordID.recordName, contexte) as? AvisEtape) ?? {
                let nouveau = AvisEtape(etapeUID: "", auteurUID: ""); nouveau.uid = uid; contexte.insert(nouveau); return nouveau
            }()
            a.etapeUID = texte("etapeUID"); a.auteurUID = texte("auteurUID"); a.etoiles = entier("etoiles") ?? 0
            a.envie = EnvieEtape(rawValue: texte("envie")) ?? .neutre; a.commentaire = texte("commentaire")
            a.modifieLe = date("modifieLe") ?? a.modifieLe; a.voyage = parent
            return a
        }
    }
}
