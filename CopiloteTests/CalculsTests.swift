import Foundation
import CloudKit
import CoreLocation
import ImageIO
import SwiftData
import Testing
#if os(iOS)
import UIKit
#endif
@testable import Copilote

/// Les calculs d'argent de l'app : ce qu'ils renvoient doit rester juste quand on modifie le code.
@MainActor
struct CalculsTests {
    /// Une base en mémoire, vide, pour chaque test.
    private let conteneur: ModelContainer
    private var contexte: ModelContext { conteneur.mainContext }

    init() throws {
        conteneur = try ModelContainer(
            for: Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self, Depense.self,
            Commentaire.self, AvisEtape.self, Famille.self, Sondage.self, VoteSondage.self, EntreeJournal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func voyage() -> Voyage {
        let debut = Calendar.current.startOfDay(for: .now)
        let v = Voyage(titre: "Essai", debut: debut, fin: debut.addingTimeInterval(2 * 86_400))
        contexte.insert(v)
        return v
    }

    @discardableResult
    private func membre(_ nom: String, famille: String? = nil, tarif: Tarif? = nil, dans v: Voyage) -> Membre {
        let m = Membre(nom: nom)
        m.familleNom = famille
        m.tarifBrut = tarif?.rawValue
        m.voyage = v
        contexte.insert(m)
        return m
    }

    // MARK: Dépenses et remboursements

    @Test func repartirTombeJusteAuCentime() {
        let parts = Comptes.repartir(10, entre: ["a", "b", "c"])
        #expect(parts.map(\.montant) == [3.34, 3.33, 3.33])
        #expect(abs(parts.map(\.montant).reduce(0, +) - 10) < 0.0001)
    }

    @Test func virementsRemettentToutLeMondeAZero() {
        let virements = Comptes.virements(["a": 30, "b": -10, "c": -20])
        #expect(virements.count == 2)
        #expect(virements.allSatisfy { $0.vers == "a" })
        #expect(abs(virements.map(\.montant).reduce(0, +) - 30) < 0.001)
    }

    @Test func soldesRegroupesParFamille() {
        let v = voyage()
        let alex = membre("Alex", famille: "Martin", dans: v)
        let julia = membre("Julia", famille: "Martin", dans: v)
        let bruno = membre("Bruno", dans: v)
        // Alex paie 90 € pour tous les trois : la famille Martin (Alex et Julia) avance 30 € pour Bruno.
        let d = Depense(devise: "EUR", payeurUID: alex.uid)
        d.montant = 90
        d.parts = Comptes.repartir(90, entre: [alex.uid, julia.uid, bruno.uid])
        d.voyage = v
        contexte.insert(d)

        let soldes = v.soldesParCompte(moi: alex.uid)["EUR"] ?? [:]
        #expect(soldes.count == 2)
        #expect(soldes[alex.uid] == 30)
        #expect(soldes[bruno.uid] == -30)
    }

    // MARK: Budget

    @Test func budgetEtudiantSansPrixPaieLePrixAdulte() {
        let v = voyage()
        membre("Alex", tarif: .adulte, dans: v)
        membre("Léa", tarif: .etudiant, dans: v)
        let e = Etape(titre: "Musée", jour: v.debut)
        e.prixAdulte = 20
        e.voyage = v
        contexte.insert(e)

        #expect(v.calculerBudget().elements.total(pour: v.membresTries) == 40)
    }

    @Test func budgetSansLesVoyageursNonConcernes() {
        let v = voyage()
        let alex = membre("Alex", tarif: .adulte, dans: v)
        membre("Bruno", tarif: .adulte, dans: v)
        let e = Etape(titre: "Plongée", jour: v.debut)
        e.prixAdulte = 100
        e.exclusBudget = [alex.uid]
        e.voyage = v
        contexte.insert(e)

        #expect(v.calculerBudget().elements.total(pour: v.membresTries) == 100)
    }

    @Test func budgetPrendLePrixReelDUneReservationLiee() {
        let v = voyage()
        let alex = membre("Alex", tarif: .adulte, dans: v)
        let bruno = membre("Bruno", tarif: .adulte, dans: v)
        let hotel = Etape(titre: "Hôtel", jour: v.debut, categorie: .hebergement)
        hotel.prixAdulte = 100
        hotel.voyage = v
        contexte.insert(hotel)
        // Alex a réservé pour lui seul, 150 € : Bruno garde le prix prévu.
        let r = Reservation(type: .hebergement, debut: v.debut)
        r.prix = 150
        r.devise = "EUR"
        r.lien = LienReservation.etape(hotel)
        r.visiblePour = [alex.uid]
        r.voyage = v
        contexte.insert(r)

        let elements = v.calculerBudget().elements
        #expect(elements.total(pour: [alex]) == 150)
        #expect(elements.total(pour: [bruno]) == 100)
    }

    @Test func budgetPrendLesPrixParPersonneDUneReservationLiee() {
        let v = voyage()
        let alex = membre("Alex", tarif: .adulte, dans: v)
        let chloe = membre("Chloé", tarif: .etudiant, dans: v)
        let lou = membre("Lou", tarif: .enfant, dans: v)
        let musee = Etape(titre: "Musée", jour: v.debut, categorie: .activite)
        musee.prixAdulte = 30
        musee.voyage = v
        contexte.insert(musee)
        // Billets à 20 € l'adulte et 8 € l'enfant ; sans prix étudiant, Chloé paie le prix adulte.
        let r = Reservation(type: .activite, debut: v.debut)
        r.prixAdulte = 20
        r.prixEnfant = 8
        r.lien = LienReservation.etape(musee)
        r.voyage = v
        contexte.insert(r)

        let elements = v.calculerBudget().elements
        #expect(elements.total(pour: [alex]) == 20)
        #expect(elements.total(pour: [chloe]) == 20)
        #expect(elements.total(pour: [lou]) == 8)
        #expect(v.montant(de: r)?.montant == 48)
    }

    @Test func hebergementReporteSurLesNuitsDeLaReservation() {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: .now)
        func jour(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: debut)! }
        let v = Voyage(titre: "Essai", debut: debut, fin: jour(6))
        contexte.insert(v)
        membre("Alex", dans: v)
        // L'hôtel est saisi pour la nuit du jour 2 ; la nuit du jour 4 a déjà un autre hébergement, qui reste à côté de lui.
        let hotel = Etape(titre: "Hôtel du Lac", jour: nil, categorie: .hebergement)
        hotel.prixAdulte = 80
        hotel.voyage = v
        contexte.insert(hotel)
        v.placerEntreJours(hotel, apres: jour(2))
        let autre = Etape(titre: "Camping", jour: nil, categorie: .hebergement)
        autre.voyage = v
        contexte.insert(autre)
        v.placerEntreJours(autre, apres: jour(4))
        // Réservé du jour 1 au jour 5, 400 € : nuits des jours 1, 2, 3 et 4.
        let r = Reservation(type: .hebergement, debut: jour(1).addingTimeInterval(15 * 3600))
        r.fin = jour(5).addingTimeInterval(11 * 3600)
        r.prix = 400
        r.lien = LienReservation.etape(hotel)
        r.voyage = v
        contexte.insert(r)

        let report = v.reporterHebergement(de: r, dans: contexte)
        #expect(report?.nuits.count == 3)
        #expect(report?.voisins.map(\.etape.titre) == ["Camping"])
        #expect(report?.voisins.map { cal.isDate($0.nuit, inSameDayAs: jour(4)) } == [true])
        #expect(v.hebergements(apres: jour(1)).map(\.titre) == ["Hôtel du Lac"])
        #expect(v.hebergements(apres: jour(3)).map(\.titre) == ["Hôtel du Lac"])
        // La nuit du jour 4 a désormais deux hébergements côte à côte : le camping garde sa place.
        #expect(Set(v.hebergements(apres: jour(4)).map(\.titre)) == ["Hôtel du Lac", "Camping"])
        #expect(autre.jour.map { cal.isDate($0, inSameDayAs: jour(4)) } == true)
        #expect(v.hebergements(apres: jour(0)).isEmpty)
        // Le prix de la réservation couvre le séjour : il n'est pas compté deux fois.
        #expect(v.calculerBudget().elements.total(pour: v.membres) == 400)
        // Une seconde validation n'ajoute rien.
        #expect(v.reporterHebergement(de: r, dans: contexte) == nil)
    }

    @Test func budgetAdolescentPaieSonPrixOuLePrixEnfant() {
        let v = voyage()
        let sam = membre("Sam", tarif: .adolescent, dans: v)
        #expect(Tarif.pour(age: 11) == .enfant)
        #expect(Tarif.pour(age: 14) == .adolescent)
        #expect(Tarif.pour(age: 18) == .adulte)
        let zoo = Etape(titre: "Zoo", jour: v.debut, categorie: .activite)
        zoo.prixAdulte = 25
        zoo.prixEnfant = 10
        zoo.voyage = v
        contexte.insert(zoo)
        // Sans prix adolescent : le prix enfant.
        #expect(v.calculerBudget().elements.total(pour: [sam]) == 10)
        zoo.prixAdolescent = 15
        #expect(v.calculerBudget().elements.total(pour: [sam]) == 15)
    }

    @Test func budgetEnfantEtAdolescentPeuventEchangerLeurPrix() {
        let v = voyage()
        let sam = membre("Sam", tarif: .adolescent, dans: v)
        let lou = membre("Lou", tarif: .enfant, dans: v)
        let parc = Etape(titre: "Parc", jour: v.debut, categorie: .activite)
        parc.prixEnfant = 10
        parc.prixAdolescent = 15
        parc.voyage = v
        contexte.insert(parc)
        // Ici, Sam paie le prix enfant et Lou le prix adolescent.
        parc.basculesTarif = [sam.uid, lou.uid]
        let elements = v.calculerBudget().elements
        #expect(elements.total(pour: [sam]) == 10)
        #expect(elements.total(pour: [lou]) == 15)
    }

    @Test func dateDeNaissanceDonneLAgeAuDepart() {
        let v = voyage()
        let lou = membre("Lou", dans: v)
        lou.age = 30
        // 12 ans la veille du départ : adolescent, quel que soit l'âge saisi.
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: v.debut)!
        lou.dateNaissance = Calendar.current.date(byAdding: .year, value: -12, to: veille)
        #expect(lou.ageAuVoyage == 12)
        #expect(lou.tarif == .adolescent)
    }

    @Test func infosDuVolPartageesDansLeVoyage() {
        let v = voyage()
        var aller = Transport()
        aller.mode = .avion
        aller.numero = "AF 430"
        v.transportAller = aller
        var infos = InfosVol()
        infos.numero = "AF 430"
        infos.depart.terminal = "2E"
        infos.depart.porte = "K45"
        infos.arrivee.tapis = "5"
        v.partager(infos, "af430", v.jours.first!)
        // Le numéro est retrouvé quelle que soit son écriture ; les infos survivent à l'encodage.
        #expect(v.volPartage("AF430", v.jours.first!)?.infos == infos)
        // Un vol qui n'est plus ni l'aller ni le retour n'est pas gardé.
        v.partager(infos, "XX999", v.jours.first!)
        #expect(v.volPartage("XX999", v.jours.first!) == nil)
    }

    @Test func hebergementDePlusieursNuitsRepartiParNuit() {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: .now)
        func jour(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: debut)! }
        let v = Voyage(titre: "Essai", debut: debut, fin: jour(5))
        contexte.insert(v)
        let alex = membre("Alex", dans: v)
        let hotel = Etape(titre: "Hôtel du Lac", jour: nil, categorie: .hebergement)
        hotel.voyage = v
        contexte.insert(hotel)
        v.placerEntreJours(hotel, apres: jour(1))
        // 300 € pour trois nuits (jours 1, 2 et 3) : 100 € par nuit, sur chacun de ces jours.
        let r = Reservation(type: .hebergement, debut: jour(1).addingTimeInterval(15 * 3600))
        r.fin = jour(4).addingTimeInterval(11 * 3600)
        r.prix = 300
        r.lien = LienReservation.etape(hotel)
        r.voyage = v
        contexte.insert(r)
        v.reporterHebergement(de: r, dans: contexte)

        let elements = v.calculerBudget().elements
        #expect(elements.total(pour: [alex]) == 300)
        for n in 1...3 {
            #expect(elements.filter { cal.isDate($0.jour, inSameDayAs: jour(n)) }.total(pour: [alex]) == 100)
        }
        #expect(v.nuits(de: r).count == 3)
        let copie = v.hebergements(apres: jour(3)).first!
        #expect(v.sejour(de: copie)?.nuits.count == 3)
        // La réservation est liée à l'hébergement de chaque nuit : jour 2, 3 et 4 (nuits des jours 1, 2 et 3), même hôtel.
        let liste = v.nuitsDeSejour(de: r)
        #expect(liste.map(\.numeroDeJour) == [2, 3, 4])
        #expect(liste.allSatisfy { $0.etape?.titre == "Hôtel du Lac" })
        #expect(v.reservations(lieesA: LienReservation.etape(copie)).count == 1)
    }

    @Test func transportsDExtremiteCreentLeurEtapeDArriveeEtDeDepart() {
        let v = voyage()
        let premierJour = v.jours.first!, dernierJour = v.jours.last!
        let musee = Etape(titre: "Musée", jour: premierJour, categorie: .musee)
        musee.ordre = 3
        musee.voyage = v
        contexte.insert(musee)
        let fin = Etape(titre: "Dîner", jour: dernierJour, categorie: .repas)
        fin.ordre = 5
        fin.voyage = v
        contexte.insert(fin)

        var aller = Transport()
        aller.mode = .avion
        aller.arriveeLieu = "Aéroport de San José"
        aller.arriveeLatitude = 9.99; aller.arriveeLongitude = -84.2
        v.transportAller = aller
        var retour = Transport()
        retour.mode = .avion
        retour.departLieu = "Aéroport de San José"
        v.transportRetour = retour

        // L'arrivée ouvre le premier jour, le départ ferme le dernier.
        #expect(v.etapes(du: premierJour).map(\.titre) == ["Aéroport de San José", "Musée"])
        #expect(v.etapes(du: dernierJour).map(\.titre) == ["Dîner", "Aéroport de San José"])
        #expect(v.etapes(du: premierJour).first?.latitude == 9.99)
        // Enregistrer de nouveau le transport met l'étape à jour, sans en créer une seconde.
        aller.arriveeLieu = "Aéroport Juan Santamaría"
        v.transportAller = aller
        #expect(v.etapes(du: premierJour).map(\.titre) == ["Aéroport Juan Santamaría", "Musée"])
        // Sans lieu précisé, aucune étape n'est créée.
        let autre = voyage()
        autre.transportAller = Transport()
        #expect(autre.etapes.isEmpty)
    }

    // MARK: Sous-étapes

    private func etape(_ titre: String, jour: Date?, dans v: Voyage) -> Etape {
        let e = Etape(titre: titre, jour: jour)
        e.voyage = v
        contexte.insert(e)
        return e
    }

    @Test func uneEtapeAPlacerDevientUneSousEtape() {
        let v = voyage()
        let circuit = etape("Circuit", jour: v.debut, dans: v)
        let a = etape("Point A", jour: nil, dans: v)
        let b = etape("Point B", jour: nil, dans: v)
        #expect(v.etapesSansJour.count == 2)

        #expect(circuit.rattacher(b, avant: nil))
        #expect(circuit.rattacher(a, avant: b))
        #expect(circuit.sousEtapes.map(\.titre) == ["Point A", "Point B"])
        // Les sous-étapes ne sont plus « à placer », ni dans le jour : elles suivent leur étape.
        #expect(v.etapesSansJour.isEmpty)
        #expect(v.etapes(du: v.debut).map(\.titre) == ["Circuit"])
        #expect(a.jourEffectif == circuit.jour)
        // Pas de sous-étape dans une sous-étape, ni d'étape déjà placée dans un jour.
        let autre = etape("Autre", jour: v.debut, dans: v)
        #expect(!circuit.rattacher(autre, avant: nil))
        #expect(!a.peutRecevoir(etape("C", jour: nil, dans: v)))
    }

    @Test func uneSousEtapeSansSonEtapeRevientAPlacer() {
        let v = voyage()
        let circuit = etape("Circuit", jour: v.debut, dans: v)
        let a = circuit.ajouterSousEtape(dans: contexte)
        a.titre = "Point A"
        #expect(v.etapesSansJour.isEmpty)
        contexte.delete(circuit)
        try? contexte.save()
        #expect(v.etapesSansJour.map(\.titre) == ["Point A"])
    }

    @Test func sousEtapeRemiseAPlacerOuPlaceeDansUnJour() {
        let v = voyage()
        let circuit = etape("Circuit", jour: v.debut, dans: v)
        let a = circuit.ajouterSousEtape(dans: contexte)
        let b = circuit.ajouterSousEtape(dans: contexte)
        a.titre = "A"; b.titre = "B"
        a.transport = Transport()
        a.detacherDeSonEtape()
        #expect(a.parentUID == nil && a.transport == nil)
        #expect(v.etapesSansJour.map(\.titre) == ["A"])
        // Glissée sur un jour, une sous-étape devient une étape ordinaire.
        v.deplacer(b, vers: v.debut, avant: nil)
        #expect(b.parentUID == nil)
        #expect(!circuit.aDesSousEtapes)
    }

    @Test func dupliquerUneEtapeCopieSesSousEtapes() {
        let v = voyage()
        let circuit = etape("Circuit", jour: v.debut, dans: v)
        let a = circuit.ajouterSousEtape(dans: contexte)
        let b = circuit.ajouterSousEtape(dans: contexte)
        a.titre = "A"; b.titre = "B"
        var t = Transport(); t.mode = .pied
        a.transport = t
        let copie = circuit.copie(dans: contexte)
        #expect(copie.sousEtapes.map(\.titre) == ["A", "B"])
        #expect(copie.sousEtapes.first?.transport?.mode == .pied)
        #expect(circuit.sousEtapes.count == 2)
        // Une sous-étape dupliquée reste dans son étape, juste après l'originale.
        _ = a.copie(dans: contexte)
        #expect(circuit.sousEtapes.map(\.titre) == ["A", "A", "B"])
    }

    @Test func budgetDUneSousEtapeAuJourDeSonEtape() {
        let v = voyage()
        membre("Alex", tarif: .adulte, dans: v)
        let circuit = etape("Circuit", jour: v.debut, dans: v)
        let a = circuit.ajouterSousEtape(dans: contexte)
        a.titre = "Musée"
        a.prixAdulte = 15
        let budget = v.calculerBudget()
        #expect(budget.elements.total(pour: v.membresTries) == 15)
        #expect(budget.etapesSansJour == 0)
    }

    // MARK: Album photo

    /// Une grande photo (4 032 × 3 024, comme un iPhone), bruitée pour peser lourd, avec sa date de prise de vue.
    private func grandePhoto(prise: String) -> Data {
        let largeur = 4032, hauteur = 3024
        var pixels = [UInt8](repeating: 0, count: largeur * hauteur * 4)
        var graine: UInt32 = 12345
        for i in stride(from: 0, to: pixels.count, by: 4) {
            graine = graine &* 1_664_525 &+ 1_013_904_223
            pixels[i] = UInt8(truncatingIfNeeded: graine >> 24); pixels[i + 1] = UInt8(truncatingIfNeeded: graine >> 16)
            pixels[i + 2] = UInt8(truncatingIfNeeded: graine >> 8); pixels[i + 3] = 255
        }
        let contexteImage = CGContext(data: &pixels, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: largeur * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = contexteImage.makeImage()!
        let sortie = NSMutableData()
        let destination = CGImageDestinationCreateWithData(sortie, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: prise],
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return sortie as Data
    }

    @Test func unePhotoDAlbumEstReduite() throws {
        let originale = grandePhoto(prise: "2026:10:23 14:05:00")
        let prete = try #require(PhotoAlbum.preparer(originale))
        let source = try #require(CGImageSourceCreateWithData(prete.donnees as CFData, nil))
        let proprietes = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let largeur = try #require(proprietes[kCGImagePropertyPixelWidth] as? Int)
        let hauteur = try #require(proprietes[kCGImagePropertyPixelHeight] as? Int)
        // Le grand côté passe à 2 048 pixels, en gardant les proportions.
        #expect(largeur == 2048)
        #expect(hauteur == 1536)
        #expect(prete.donnees.count < originale.count / 3)
        var composants = DateComponents(); composants.year = 2026; composants.month = 10; composants.day = 23; composants.hour = 14; composants.minute = 5
        #expect(prete.priseLe == Calendar.current.date(from: composants))
        #expect(PhotoAlbum.preparer(Data("pas une image".utf8)) == nil)
    }

    #if os(iOS)
    /// Une photo prise avec l'appareil : ses pixels sont ceux du capteur, tournés par l'orientation ; une fois encodée puis
    /// réduite pour l'album, elle doit être à l'endroit et garder sa date de prise de vue.
    @Test func unePhotoPriseGardeSonOrientationEtSaDate() throws {
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = UIImage(cgImage: try #require(ctx.makeImage()), scale: 1, orientation: .right)
        let meta: [String: Any] = [kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2026:10:22 09:15:00"]]
        let originale = try #require(BoutonPhotoAlbum.encoder(image, metadonnees: meta))
        let prete = try #require(PhotoAlbum.preparer(originale))
        let source = try #require(CGImageSourceCreateWithData(prete.donnees as CFData, nil))
        let decodee = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decodee.width == 20)
        #expect(decodee.height == 40)
        var composants = DateComponents(); composants.year = 2026; composants.month = 10; composants.day = 22; composants.hour = 9; composants.minute = 15
        #expect(prete.priseLe == Calendar.current.date(from: composants))
    }
    #endif

    @Test func lAlbumEstAPartDesPhotosDuLieuEtNeSuitPasUneCopie() throws {
        let v = voyage()
        let musee = etape("Musée", jour: v.debut, dans: v)
        let duLieu = Document(nom: "Musée – photo 1", extensionFichier: "jpg", donnees: Data([1]))
        duLieu.etape = musee; duLieu.voyage = v; contexte.insert(duLieu)
        let prete = try #require(PhotoAlbum.preparer(grandePhoto(prise: "2026:10:23 10:00:00")))
        musee.ajouterAuAlbum(prete, dans: contexte)
        let sous = musee.ajouterSousEtape(dans: contexte)
        sous.ajouterAuAlbum(prete, dans: contexte)
        #expect(musee.album.count == 1)
        #expect(musee.photosDuLieu.map(\.nom) == ["Musée – photo 1"])
        #expect(sous.album.count == 1)
        // Une photo d'album n'est pas un document du voyage à vérifier (passeport…).
        #expect(musee.album.first?.membreUID == nil)
        let copie = musee.copie(dans: contexte)
        #expect(copie.album.isEmpty)
        #expect(copie.photosDuLieu.count == 1)
    }

    // MARK: Journal des modifications

    @Test func leJournalNoteQuiAjouteModifieEtSupprime() throws {
        let v = voyage()
        let moi = membre("Léa", dans: v)
        MoiVoyage.ecrire(moi.uid, v)
        defer { UserDefaults.standard.removeObject(forKey: MoiVoyage.cle(v)) }
        let journal = JournalModifications(contexte: contexte)
        var horloge = Date(timeIntervalSince1970: 1_800_000_000)
        journal.maintenant = { horloge }
        journal.accepterTout()

        // Ajout puis retouches dans la foulée : une seule ligne « ajout ».
        let etape = Etape(titre: "Louvre", jour: v.debut)
        etape.voyage = v; contexte.insert(etape)
        journal.noter()
        etape.notes = "Billets pris"
        horloge += 60
        journal.noter()
        var lignes = v.journal.sorted { $0.date < $1.date }
        #expect(lignes.count == 1)
        #expect(lignes.first?.action == .ajout)
        #expect(lignes.first?.auteurNom == "Léa")
        #expect(lignes.first?.phrase == "a ajouté l'étape « Louvre »")

        // Plus tard, une modification : nouvelle ligne avec les champs changés.
        horloge += 3600
        etape.titre = "Musée du Louvre"
        etape.duree = 5400
        journal.noter()
        lignes = v.journal.sorted { $0.date < $1.date }
        #expect(lignes.count == 2)
        #expect(lignes.last?.action == .modification)
        #expect(lignes.last?.champsEnClair == "Durée, Titre", "\(lignes.last?.champs ?? [])")

        // Ce qui arrive d'iCloud n'est pas noté à mon nom.
        horloge += 3600
        etape.heure = horloge
        journal.accepter(noms: [Codec.nom(.etape, etape.uid)])
        journal.noter()
        #expect(v.journal.count == 2)

        // Suppression : une ligne.
        horloge += 3600
        contexte.delete(etape)
        journal.noter()
        #expect(v.journal.count == 3)
        #expect(v.journal.contains { $0.action == .suppression && $0.libelle == "Musée du Louvre" })
    }

    @Test func lesHeuresDArriveeEtDeDepartPassentParLaSynchronisation() throws {
        let v = voyage()
        let etape = Etape(titre: "Volcan", jour: v.debut)
        etape.voyage = v; contexte.insert(etape)
        let sous = etape.ajouterSousEtape(dans: contexte)
        let arrivee = Date(timeIntervalSince1970: 1_800_000_000), depart = arrivee.addingTimeInterval(5400)
        etape.arriveeReelle = arrivee; etape.departReel = depart
        sous.arriveeReelle = arrivee
        let zone = Codec.zone(de: v)
        let r = Codec.enregistrement(pour: etape, zone: zone, systeme: nil, avecAsset: false)
        let rs = Codec.enregistrement(pour: sous, zone: zone, systeme: nil, avecAsset: false)
        #expect(Codec.champs(de: r)["arriveeReelle"] != nil)
        // Effacée ici : l'enregistrement reçu la remet ; effacée là-bas, elle disparaît ici.
        etape.arriveeReelle = nil; etape.departReel = nil; sous.arriveeReelle = nil
        _ = Codec.appliquer(r, contexte)
        _ = Codec.appliquer(rs, contexte)
        #expect(etape.arriveeReelle == arrivee)
        #expect(etape.departReel == depart)
        #expect(sous.arriveeReelle == arrivee && sous.departReel == nil)
        r["departReel"] = nil
        _ = Codec.appliquer(r, contexte)
        #expect(etape.departReel == nil)
    }

    @Test func uneEtapeAjouteePuisRetireeAussitotNeLaissePasDeTrace() throws {
        let v = voyage()
        let journal = JournalModifications(contexte: contexte)
        journal.accepterTout()
        let etape = Etape(titre: "", jour: v.debut)
        etape.voyage = v; contexte.insert(etape)
        journal.noter()
        #expect(v.journal.count == 1)
        contexte.delete(etape)
        journal.noter()
        try contexte.save()
        #expect(v.journal.isEmpty)
    }

    @Test func lesPhotosAjouteesEnsembleFontUneLigne() throws {
        let v = voyage()
        let etape = Etape(titre: "Montmartre", jour: v.debut)
        etape.voyage = v; contexte.insert(etape)
        let journal = JournalModifications(contexte: contexte)
        journal.accepterTout()
        let prete = try #require(PhotoAlbum.preparer(grandePhoto(prise: "2026:10:23 10:00:00")))
        for _ in 0..<3 { _ = etape.ajouterAuAlbum(prete, dans: contexte) }
        journal.noter()
        #expect(v.journal.count == 1)
        #expect(v.journal.first?.nombre == 3)
        #expect(v.journal.first?.phrase == "a ajouté 3 photos à l'album de « Montmartre »")
    }

    // MARK: Documents importants

    @Test func unDocumentImportantSuitLaPersonneDansSesVoyages() throws {
        let paris = voyage(), rome = voyage(), autre = voyage()
        let leaParis = membre("Léa", dans: paris)
        leaParis.email = "lea@exemple.fr"
        let leaRome = membre("Léa", dans: rome)
        leaRome.email = "LEA@exemple.fr "
        membre("Hugo", dans: autre)
        let passeport = Document(nom: "Passeport Léa", extensionFichier: "pdf", donnees: Data([1, 2, 3]))
        passeport.membreUID = leaParis.uid; passeport.type = .passeport; passeport.voyage = paris
        contexte.insert(passeport)

        DocumentsImportants.marquer(passeport, dans: contexte)
        let copie = try #require(rome.documents.first)
        #expect(copie.membreUID == leaRome.uid)
        #expect(copie.importantUID == passeport.importantUID)
        #expect(copie.type == .passeport)
        #expect(autre.documents.isEmpty)
        // Rien en double si on recommence.
        #expect(DocumentsImportants.repandre(dans: contexte) == 0)

        // Un nouveau voyage de Léa reçoit le document.
        let lisbonne = voyage()
        membre("Léa", dans: lisbonne).email = "lea@exemple.fr"
        #expect(DocumentsImportants.repandre(dans: contexte) == 1)
        #expect(lisbonne.documents.count == 1)

        // Une modification passe sur toutes les copies.
        passeport.expireLe = Date(timeIntervalSince1970: 2_000_000_000)
        DocumentsImportants.reporter(passeport, dans: contexte)
        #expect(copie.expireLe == passeport.expireLe)

        // Plus important : il reste ici, les copies partent.
        DocumentsImportants.retirer(passeport, dans: contexte)
        try contexte.save()
        #expect(passeport.importantUID == nil)
        #expect(paris.documents.count == 1)
        #expect(rome.documents.isEmpty && lisbonne.documents.isEmpty)
    }

    @Test func laVignetteDUnPDFEstSaPremierePage() throws {
        let donnees = NSMutableData()
        var boite = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consommateur = try #require(CGDataConsumer(data: donnees as CFMutableData))
        let ctx = try #require(CGContext(consumer: consommateur, mediaBox: &boite, nil))
        ctx.beginPDFPage(nil); ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(boite); ctx.endPDFPage(); ctx.closePDF()
        let image = try #require(VignettesDocuments.image(de: donnees as Data, extensionFichier: "PDF", cle: "essai-pdf", cote: 200))
        #expect(image.height == 200)
        #expect(image.width == 150)
    }

    // MARK: Parcours de la journée

    @Test func leverEtCoucherDuSoleilAParis() throws {
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        let zone = try #require(TimeZone(identifier: "Europe/Paris"))
        func jour(_ a: Int, _ m: Int, _ j: Int) -> Date { Calendar.current.date(from: DateComponents(year: a, month: m, day: j))! }
        func heure(_ d: Date) -> Double {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double(c.hour! * 60 + c.minute!)
        }
        // Solstice d'été : lever vers 5 h 47, coucher vers 21 h 58 (heure d'été).
        let ete = try #require(Soleil.leverCoucher(jour: jour(2026, 6, 21), paris, zone: zone))
        #expect(abs(heure(ete.lever) - (5 * 60 + 47)) <= 3)
        #expect(abs(heure(ete.coucher) - (21 * 60 + 58)) <= 3)
        // Solstice d'hiver : lever vers 8 h 42, coucher vers 16 h 56.
        let hiver = try #require(Soleil.leverCoucher(jour: jour(2026, 12, 21), paris, zone: zone))
        #expect(abs(heure(hiver.lever) - (8 * 60 + 42)) <= 3)
        #expect(abs(heure(hiver.coucher) - (16 * 60 + 56)) <= 3)
        // À midi le soleil est haut, à minuit il est sous l'horizon.
        #expect(Soleil.hauteur(ParcoursJour.instant(jour(2026, 6, 21), 14 * 60, zone: zone), paris) > 60)
        #expect(Soleil.hauteur(ParcoursJour.instant(jour(2026, 6, 21), 1 * 60, zone: zone), paris) < 0)
        // Nuit polaire au Svalbard en décembre : ni lever ni coucher.
        #expect(Soleil.leverCoucher(jour: jour(2026, 12, 21), CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6), zone: zone) == nil)
    }

    @Test func leParcoursSuitLesHorairesDeLaJournee() throws {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: .now)
        let jour = cal.date(byAdding: .day, value: 1, to: debut)!
        let v = Voyage(titre: "Essai", debut: debut, fin: cal.date(byAdding: .day, value: 2, to: debut)!)
        contexte.insert(v)
        func etape(_ titre: String, _ lat: Double, _ lon: Double, jour j: Date?) -> Etape {
            let e = Etape(titre: titre, jour: j)
            e.latitude = lat; e.longitude = lon
            e.voyage = v
            contexte.insert(e)
            return e
        }
        let hotelVeille = etape("Hôtel de la veille", 48.85, 2.35, jour: nil)
        hotelVeille.categorie = .hebergement
        v.placerEntreJours(hotelVeille, apres: debut)
        let a = etape("Musée", 48.86, 2.33, jour: jour)
        a.heure = jour.addingTimeInterval(10 * 3600); a.duree = 60; a.ordre = 0
        var marche = Transport(); marche.mode = .pied
        a.transport = marche
        let b = etape("Butte", 48.88, 2.34, jour: jour)
        b.heure = jour.addingTimeInterval(12 * 3600); b.duree = 90; b.ordre = 1
        let sous = etape("Place", 48.887, 2.341, jour: nil)
        sous.parentUID = b.uid
        let hotel = etape("Hôtel du soir", 48.87, 2.36, jour: nil)
        hotel.categorie = .hebergement
        v.placerEntreJours(hotel, apres: jour)
        hotel.heure = jour.addingTimeInterval(19 * 3600)

        let p = try #require(ParcoursJour.calculer(voyage: v, jour: jour))
        // Une heure avant de quitter l'hôtel (à 10 h, heure de la première étape) jusqu'à une heure après l'arrivée à celui du soir.
        #expect(p.debut == 9 * 60)
        #expect(p.fin == 20 * 60)
        #expect(p.arrets.map(\.titre) == ["Hôtel de la veille", "Musée", "Butte", "Hôtel du soir"])
        #expect(p.arrets[2].sous.map(\.titre) == ["Place"])
        // Au musée à 10 h 30, sans transport (un point) avant le premier trajet à pied.
        let auMusee = try #require(p.position(a: 10 * 60 + 30))
        #expect(abs(auMusee.latitude - 48.86) < 0.0001)
        // La marche (20 min estimées) arrive à 12 h pile à la Place, la sous-étape de la Butte : à 11 h 50, à mi-chemin, en piéton.
        let enRoute = try #require(p.position(a: 11 * 60 + 50))
        #expect(abs(enRoute.latitude - (48.86 + 48.887) / 2) < 0.001)
        // Arrivé : directement à la sous-étape, pas au lieu de la Butte.
        let aLaPlace = try #require(p.position(a: 12 * 60 + 5))
        #expect(abs(aLaPlace.latitude - 48.887) < 0.0001)
        #expect(p.mode(a: 11 * 60 + 50) == .pied)
        #expect(abs(p.curseur(a: 11 * 60 + 50) - 1.5) < 0.01)
        // La sous-étape s'affiche quand on approche de la Butte, puis disparaît une fois repartis.
        #expect(p.sousEtapesVisibles(p.arrets[2], a: 12 * 60 + 30))
        #expect(!p.sousEtapesVisibles(p.arrets[2], a: 10 * 60 + 30))
        #expect(!p.sousEtapesVisibles(p.arrets[2], a: 18 * 60 + 30))
        let visites = stride(from: 12.0 * 60, through: 13.5 * 60, by: 1).compactMap { p.sousArret(a: $0) }
        #expect(visites.contains { $0.arret == 2 && $0.sous == 0 })
        // Le soir, à l'hôtel.
        let soir = try #require(p.position(a: 19 * 60 + 30))
        #expect(abs(soir.latitude - 48.87) < 0.0001 && abs(soir.longitude - 2.36) < 0.0001)
        // De 5 à 20 secondes de lecture.
        #expect(p.secondes >= 5 && p.secondes <= 20)
    }

    @Test func lesTrajetsVontDeLaDerniereSousEtapeALaPremiereDeLaSuivante() throws {
        let cal = Calendar.current
        let debut = cal.startOfDay(for: .now)
        let jour = cal.date(byAdding: .day, value: 1, to: debut)!
        let v = Voyage(titre: "Essai", debut: debut, fin: cal.date(byAdding: .day, value: 2, to: debut)!)
        contexte.insert(v)
        func etape(_ titre: String, _ lat: Double, _ lon: Double, jour j: Date?, parent: Etape? = nil) -> Etape {
            let e = Etape(titre: titre, jour: j)
            e.latitude = lat; e.longitude = lon
            e.voyage = v
            contexte.insert(e)
            if let parent { e.parentUID = parent.uid; e.ordre = Double(parent.sousEtapes.count) }
            return e
        }
        let a = etape("Quartier A", 48.80, 2.30, jour: jour)
        a.heure = jour.addingTimeInterval(9 * 3600); a.duree = 120; a.ordre = 0
        var marche = Transport(); marche.mode = .pied
        a.transport = marche
        let a1 = etape("A1", 48.81, 2.31, jour: nil, parent: a)
        let a2 = etape("A2", 48.82, 2.32, jour: nil, parent: a)
        let b = etape("Quartier B", 48.90, 2.40, jour: jour)
        b.heure = jour.addingTimeInterval(12 * 3600); b.duree = 120; b.ordre = 1
        let b1 = etape("B1", 48.91, 2.41, jour: nil, parent: b)
        _ = etape("B2", 48.92, 2.42, jour: nil, parent: b)
        let sansSous = etape("Musée", 48.85, 2.35, jour: nil)

        // Le transport de A vers B part de la dernière sous-étape de A et arrive à la première de B.
        #expect(a.sortie === a2 && b.entree === b1)
        #expect(a.entree === a1 && sansSous.entree === sansSous && sansSous.sortie === sansSous)
        #expect(a1.entree === a1 && a1.sortie === a1)
        // Une sous-étape pas encore placée sur la carte ne compte pas.
        let b3 = etape("B3", 0, 0, jour: nil, parent: b)
        b3.latitude = nil; b3.longitude = nil
        #expect(b.sortie.titre == "B2")

        let p = try #require(ParcoursJour.calculer(voyage: v, jour: jour))
        let iA = try #require(p.arrets.firstIndex { $0.titre == "Quartier A" })
        // Le trajet de A à B : de A2 à B1, sans passer par le lieu des étapes.
        let trajet = try #require(p.morceaux.first { $0.trajet && $0.arret == iA })
        #expect(trajet.points.first?.latitude == 48.82 && trajet.points.last?.latitude == 48.91)
        // Pendant le séjour à A, l'icône ne va jamais au lieu de l'étape : elle commence à A1.
        let sejourA = p.morceaux.filter { !$0.trajet && $0.arret == iA }
        #expect(sejourA.first?.points.first?.latitude == 48.81)
        #expect(!sejourA.flatMap(\.points).contains { $0.latitude == 48.80 })
    }
}
