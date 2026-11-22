import SwiftUI
import SwiftData
import ImageIO
import CoreGraphics

// MARK: - Documents importants

/// Un document « important » (passeport, carte d'identité…) suit son voyageur : il est recopié dans chacun
/// des voyages où cette personne est présente. Toutes les copies portent le même `importantUID`.
///
/// La personne est reconnue d'un voyage à l'autre comme dans « Retrouver un profil » : même e-mail, ou même nom.
/// Chaque copie a un identifiant déduit du document et du voyage : deux appareils qui la créent en même temps
/// créent le même objet, pas un doublon.
@MainActor
enum DocumentsImportants {
    static func estImportant(_ doc: Document) -> Bool { doc.importantUID != nil }

    /// Les autres exemplaires du document (dans les autres voyages).
    static func copies(de doc: Document, dans contexte: ModelContext) -> [Document] {
        guard let cle = doc.importantUID else { return [] }
        return tous(contexte).filter { $0.importantUID == cle && $0 !== doc && !$0.isDeleted }
    }

    /// Marque le document comme important : il apparaît aussitôt dans les autres voyages de son voyageur.
    static func marquer(_ doc: Document, dans contexte: ModelContext) {
        guard doc.importantUID == nil else { return }
        doc.importantUID = doc.uid.isEmpty ? UUID().uuidString : doc.uid
        repandre(dans: contexte)
    }

    /// N'est plus important : le document reste dans ce voyage, ses copies sont retirées des autres.
    static func retirer(_ doc: Document, dans contexte: ModelContext) {
        for copie in copies(de: doc, dans: contexte) { contexte.delete(copie) }
        doc.importantUID = nil
    }

    /// Supprime le document de tous les voyages.
    static func supprimerPartout(_ doc: Document, dans contexte: ModelContext) {
        for copie in copies(de: doc, dans: contexte) { contexte.delete(copie) }
        contexte.delete(doc)
    }

    /// Reporte le nom, le type, la validité et les notes sur toutes les copies.
    static func reporter(_ doc: Document, dans contexte: ModelContext) {
        for copie in copies(de: doc, dans: contexte) {
            if copie.nom != doc.nom { copie.nom = doc.nom }
            if copie.typeBrut != doc.typeBrut { copie.typeBrut = doc.typeBrut }
            if copie.expireLe != doc.expireLe { copie.expireLe = doc.expireLe }
            if copie.notes != doc.notes { copie.notes = doc.notes }
        }
    }

    /// Ajoute les documents importants aux voyages de leur voyageur qui ne les ont pas encore.
    /// Renvoie le nombre de copies créées.
    @discardableResult
    static func repandre(dans contexte: ModelContext) -> Int {
        let importants = tous(contexte).filter { $0.importantUID != nil && !$0.isDeleted }
        guard !importants.isEmpty else { return 0 }
        let membres = ((try? contexte.fetch(FetchDescriptor<Membre>())) ?? []).filter { !$0.isDeleted }
        let personnes = PersonneConnue.regrouper(membres)
        var personneDe: [String: PersonneConnue] = [:]
        for p in personnes { for m in p.membres { personneDe[m.uid] = p } }

        var crees = 0
        for (cle, exemplaires) in Dictionary(grouping: importants, by: { $0.importantUID ?? "" }) {
            // Le modèle : un exemplaire qui a sa date de validité, sinon le plus ancien.
            guard let modele = exemplaires.min(by: { ($0.expireLe == nil ? 1 : 0, $0.creeLe) < ($1.expireLe == nil ? 1 : 0, $1.creeLe) }),
                  !modele.donnees.isEmpty else { continue }
            let voyagesPresents = Set(exemplaires.compactMap { $0.voyage?.uid })
            // Tous les voyageurs de la personne, quel que soit l'exemplaire qui la désigne.
            var voyageurs: [Membre] = []
            for e in exemplaires {
                guard let uid = e.membreUID, let p = personneDe[uid] else { continue }
                for m in p.membres where !voyageurs.contains(where: { $0 === m }) { voyageurs.append(m) }
            }
            var dejaFaits = voyagesPresents
            for membre in voyageurs {
                guard let voyage = membre.voyage, !voyage.uid.isEmpty, !dejaFaits.contains(voyage.uid),
                      voyage.peutGererDocuments(de: membre) else { continue }
                dejaFaits.insert(voyage.uid)
                let uid = "\(cle)~\(voyage.uid)"
                if let existant = try? contexte.fetch(FetchDescriptor<Document>(predicate: #Predicate { $0.uid == uid })).first,
                   !existant.isDeleted {
                    continue
                }
                let copie = Document(nom: modele.nom, extensionFichier: modele.extensionFichier, donnees: modele.donnees)
                copie.uid = uid
                copie.creeLe = modele.creeLe
                copie.typeBrut = modele.typeBrut
                copie.expireLe = modele.expireLe
                copie.notes = modele.notes
                copie.membreUID = membre.uid
                copie.importantUID = cle
                copie.voyage = voyage
                contexte.insert(copie)
                crees += 1
            }
        }
        return crees
    }

    private static func tous(_ contexte: ModelContext) -> [Document] {
        (try? contexte.fetch(FetchDescriptor<Document>(predicate: #Predicate { $0.importantUID != nil }))) ?? []
    }
}

// MARK: - Vignettes

/// Aperçu réduit d'un document : l'image elle-même, la première page d'un PDF, sinon l'icône du type de fichier.
enum VignettesDocuments {
    static func image(de donnees: Data, extensionFichier: String, cle: String, cote: Int) -> CGImage? {
        let cleCache = "\(cle)-\(cote)-\(donnees.count)" as NSString
        if let image = cache.object(forKey: cleCache) { return image.cg }
        let ext = extensionFichier.lowercased()
        let image: CGImage?
        if ext == "pdf" {
            image = premierePage(donnees, cote: cote)
        } else {
            image = PhotoAlbum.vignette(donnees, cle: cle, cote: cote)
        }
        if let image { cache.setObject(ImageEnCache(image), forKey: cleCache) }
        return image
    }

    /// La première page d'un PDF, sur fond blanc.
    static func premierePage(_ donnees: Data, cote: Int) -> CGImage? {
        guard let fournisseur = CGDataProvider(data: donnees as CFData),
              let pdf = CGPDFDocument(fournisseur), let page = pdf.page(at: 1) else { return nil }
        let cadre = page.getBoxRect(.cropBox)
        guard cadre.width > 0, cadre.height > 0 else { return nil }
        let echelle = CGFloat(cote) / max(cadre.width, cadre.height)
        let largeur = max(Int(cadre.width * echelle), 1), hauteur = max(Int(cadre.height * echelle), 1)
        guard let ctx = CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: echelle, y: echelle)
        ctx.translateBy(x: -cadre.minX, y: -cadre.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    private final class ImageEnCache: @unchecked Sendable {
        let cg: CGImage
        init(_ cg: CGImage) { self.cg = cg }
    }
    nonisolated(unsafe) private static let cache: NSCache<NSString, ImageEnCache> = {
        let c = NSCache<NSString, ImageEnCache>()
        c.countLimit = 200
        return c
    }()
}

/// La vignette d'un document, remplissant le cadre qu'on lui donne.
struct VignetteDocument: View {
    let document: Document
    var cote = 360
    var symbole: String?
    @State private var image: CGImage?
    @State private var chargee = false

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.6))
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if chargee {
                VStack(spacing: 4) {
                    Image(systemName: symbole ?? document.symbole).font(.title2).foregroundStyle(.indigo)
                    if !document.extensionFichier.isEmpty {
                        Text(document.extensionFichier.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(document.uid)-\(document.donnees.count)") {
            let donnees = document.donnees, ext = document.extensionFichier, cle = document.uid, cote = cote
            image = await Task.detached(priority: .utility) {
                VignettesDocuments.image(de: donnees, extensionFichier: ext, cle: cle, cote: cote)
            }.value
            chargee = true
        }
    }
}
