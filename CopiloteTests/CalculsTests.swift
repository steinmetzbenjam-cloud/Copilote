import Foundation
import SwiftData
import Testing
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
            Commentaire.self, AvisEtape.self, Famille.self, Sondage.self, VoteSondage.self,
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
        // L'hôtel est saisi pour la nuit du jour 2 ; la nuit du jour 4 a déjà un autre hébergement, qui lui cède la place.
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
        #expect(report?.remplaces.map(\.etape.titre) == ["Camping"])
        #expect(v.hebergements(apres: jour(1)).map(\.titre) == ["Hôtel du Lac"])
        #expect(v.hebergements(apres: jour(3)).map(\.titre) == ["Hôtel du Lac"])
        #expect(v.hebergements(apres: jour(4)).map(\.titre) == ["Hôtel du Lac"])
        #expect(autre.jour == nil)
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
}
