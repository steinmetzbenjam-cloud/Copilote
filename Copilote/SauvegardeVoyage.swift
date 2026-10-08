import SwiftUI
import SwiftData
import CloudKit
import UniformTypeIdentifiers

/// Sauvegarde de voyages dans un fichier, et restauration depuis ce fichier.
/// Le fichier reprend les enregistrements de la synchronisation iCloud (mêmes champs, mêmes identifiants) :
/// importer un voyage déjà présent remet ses éléments à jour au lieu de le dupliquer.
enum Sauvegarde {
    static let format = "copilote-voyages"

    struct Fichier: Codable {
        var format: String
        var version: Int
        var exporteLe: Date
        var voyages: [VoyageSauve]
    }

    struct VoyageSauve: Codable {
        var uid: String
        var titre: String
        var objets: [Objet]
    }

    struct Objet: Codable {
        var type: String
        var uid: String
        var champs: [String: Valeur]
    }

    enum Valeur: Codable {
        case texte(String), nombre(Double), date(Double), liste([String]), fichier(Data)
    }

    enum Erreur: LocalizedError {
        case illisible
        var errorDescription: String? { "Ce fichier n'est pas une sauvegarde de voyage Copilote." }
    }

    // MARK: Export

    @MainActor static func exporter(_ voyages: [Voyage]) throws -> Data {
        let zone = CKRecordZone.default().zoneID
        func objet(_ modele: any PersistentModel, _ type: TypeCloud, _ uid: String) -> Objet? {
            guard !uid.isEmpty else { return nil }
            let record = Codec.enregistrement(pour: modele, zone: zone, systeme: nil, avecAsset: false)
            var champs: [String: Valeur] = [:]
            for cle in record.allKeys() {
                let valeur = record[cle]
                if let texte = valeur as? String { champs[cle] = .texte(texte) }
                else if let date = valeur as? Date { champs[cle] = .date(date.timeIntervalSince1970) }
                else if let liste = valeur as? [String] { champs[cle] = .liste(liste) }
                else if let nombre = valeur as? NSNumber { champs[cle] = .nombre(nombre.doubleValue) }
            }
            if let document = modele as? Document { champs["donnees"] = .fichier(document.donnees) }
            if let membre = modele as? Membre, let photo = membre.avatar { champs["avatar"] = .fichier(photo) }
            if let famille = modele as? Famille, let photo = famille.avatar { champs["avatar"] = .fichier(photo) }
            return Objet(type: type.rawValue, uid: uid, champs: champs)
        }

        let sauves = voyages.map { v -> VoyageSauve in
            var objets: [Objet?] = [objet(v, .voyage, v.uid)]
            objets += v.infosJours.map { objet($0, .jour, $0.uid) }
            objets += v.membres.map { objet($0, .membre, $0.uid) }
            objets += v.depenses.map { objet($0, .depense, $0.uid) }
            objets += v.reservations.map { objet($0, .reservation, $0.uid) }
            objets += v.etapes.map { objet($0, .etape, $0.uid) }
            objets += v.documents.map { objet($0, .document, $0.uid) }
            objets += v.commentaires.map { objet($0, .commentaire, $0.uid) }
            objets += v.avisEtapes.map { objet($0, .avisEtape, $0.uid) }
            objets += v.fichesFamilles.map { objet($0, .famille, $0.uid) }
            return VoyageSauve(uid: v.uid, titre: v.titre, objets: objets.compactMap { $0 })
        }
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        encodeur.dateEncodingStrategy = .secondsSince1970
        return try encodeur.encode(Fichier(format: format, version: 1, exporteLe: .now, voyages: sauves))
    }

    // MARK: Import

    static func lire(_ donnees: Data) throws -> Fichier {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .secondsSince1970
        guard let fichier = try? decodeur.decode(Fichier.self, from: donnees), fichier.format == format else { throw Erreur.illisible }
        return fichier
    }

    /// Voyages du fichier qui existent déjà sur cet appareil.
    @MainActor static func dejaPresents(_ fichier: Fichier, _ contexte: ModelContext) -> [String] {
        fichier.voyages.filter { Codec.voyage(uid: $0.uid, contexte) != nil }.map(\.titre)
    }

    /// Recrée les voyages du fichier. Un voyage déjà présent est mis à jour sur place : rien de ce qui a été
    /// ajouté depuis n'est supprimé, et il garde son propriétaire iCloud et son partage.
    @MainActor static func importer(_ fichier: Fichier, dans contexte: ModelContext) {
        let zone = CKRecordZone.default().zoneID
        var temporaires: [URL] = []
        defer { temporaires.forEach { try? FileManager.default.removeItem(at: $0) } }

        for sauve in fichier.voyages {
            let existant = Codec.voyage(uid: sauve.uid, contexte)
            let proprietaire = existant?.zoneProprietaire ?? ""
            let partage = existant?.partage ?? false
            let participants = existant?.participantsCloud ?? []
            let mode = existant?.modeBrut

            for objet in sauve.objets.sorted(by: { Codec.ordre($0.type) < Codec.ordre($1.type) }) {
                guard let type = TypeCloud(rawValue: objet.type) else { continue }
                let record = CKRecord(recordType: type.rawValue,
                                      recordID: CKRecord.ID(recordName: Codec.nom(type, objet.uid), zoneID: zone))
                for (cle, valeur) in objet.champs {
                    switch valeur {
                    case .texte(let t): record[cle] = t
                    case .nombre(let n): record[cle] = n
                    case .date(let d): record[cle] = Date(timeIntervalSince1970: d)
                    case .liste(let l): record[cle] = l
                    case .fichier(let donnees):
                        let url = FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString)")
                        if (try? donnees.write(to: url)) != nil {
                            temporaires.append(url)
                            record[cle] = CKAsset(fileURL: url)
                        }
                    }
                }
                _ = Codec.appliquer(record, contexte)
            }

            if let voyage = Codec.voyage(uid: sauve.uid, contexte) {
                voyage.zoneProprietaire = proprietaire
                voyage.partage = partage
                voyage.participantsCloud = participants
                if let mode { voyage.modeBrut = mode }
            }
        }
        try? contexte.save()
        PartageCloud.shared.verifierChangementsLocaux()
    }
}

/// Le fichier proposé à l'enregistrement.
struct SauvegardeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var donnees: Data

    init(donnees: Data) { self.donnees = donnees }
    init(configuration: ReadConfiguration) throws { donnees = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: donnees) }
}

/// Choix des voyages à sauvegarder.
struct ChoixSauvegardeView: View {
    let voyages: [Voyage]
    let onValider: ([Voyage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choisis: Set<String>

    init(voyages: [Voyage], onValider: @escaping ([Voyage]) -> Void) {
        self.voyages = voyages
        self.onValider = onValider
        _choisis = State(initialValue: Set(voyages.map(\.uid)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voyages) { voyage in
                        Button {
                            if choisis.contains(voyage.uid) { choisis.remove(voyage.uid) } else { choisis.insert(voyage.uid) }
                        } label: {
                            HStack {
                                Image(systemName: choisis.contains(voyage.uid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(choisis.contains(voyage.uid) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading) {
                                    Text(voyage.titre).foregroundStyle(.primary)
                                    Text(voyage.debut.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("\(choisis.count) voyage\(choisis.count > 1 ? "s" : "") sélectionné\(choisis.count > 1 ? "s" : "")")
                }
            }
            .navigationTitle("Sauvegarder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sauvegarder") {
                        onValider(voyages.filter { choisis.contains($0.uid) })
                        dismiss()
                    }
                    .disabled(choisis.isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(choisis.count == voyages.count ? "Tout désélectionner" : "Tout sélectionner") {
                        choisis = choisis.count == voyages.count ? [] : Set(voyages.map(\.uid))
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }
}
