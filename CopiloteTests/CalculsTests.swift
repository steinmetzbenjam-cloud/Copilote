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
}
