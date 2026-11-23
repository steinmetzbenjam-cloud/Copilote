import Foundation
import SwiftData
import Testing
@testable import Copilote

/// L'import des itinéraires préparés par la compétence Claude « itineraire-copilote ».
@MainActor
struct ItineraireClaudeTests {
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
        let v = Voyage(titre: "Japon", debut: debut, fin: debut.addingTimeInterval(5 * 86_400))
        contexte.insert(v)
        return v
    }

    /// L'exemple livré avec la compétence : l'app doit toujours savoir le lire.
    private func exemple() throws -> Data {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: racine.appending(path: "Outils/competence-claude/itineraire-copilote/exemples/kyoto.json"))
    }

    private func minutes(_ d: Date?) -> Int? {
        d.map { Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
    }

    @Test func lExempleDeLaCompetenceDevientUneEtapeAPlacerAvecSesSousEtapes() throws {
        let v = voyage()
        v.deviseLocale = "JPY"
        let it = try ItineraireClaude.lire(exemple())
        let parent = v.importer(it, dans: contexte)

        #expect(parent.jour == nil)
        #expect(parent.parentUID == nil)
        #expect(parent.titre == "Kyoto, temples de l'Est")
        #expect(v.etapesSansJour.contains { $0 === parent })
        #expect(!v.etapesSansJour.contains { $0.parentUID != nil })

        let sous = parent.sousEtapes
        #expect(sous.map(\.titre) == it.etapes.map(\.titre))
        #expect(sous.allSatisfy { $0.jour == nil && $0.coordonnee != nil })
        // Horaires : de la première arrivée à la dernière fin ; une durée sans heure de fin donne la fin.
        #expect(minutes(parent.heure) == 8 * 60 + 30)
        #expect(minutes(parent.heureFin) == 16 * 60)
        #expect(minutes(sous[1].heureFin) == 10 * 60 + 25)
        #expect(sous[0].duree == 75)
        #expect(parent.coordonnee?.latitude == sous[0].coordonnee?.latitude)
        #expect(sous[3].categorie == .repas)

        // Transports : de chaque sous-étape vers la suivante, pas après la dernière.
        #expect(sous[0].transport?.mode == .pied)
        #expect(sous[3].transport?.mode == .commun)
        #expect(sous[3].transport?.sousType == "Bus")
        #expect(sous[3].transport?.numero == "Bus 203")
        #expect(sous[3].transport?.dureeModifiee == 25)
        #expect(sous[3].transport?.prixAdulte == 230)
        #expect(sous[3].transport?.monnaieAdulte == .locale)
        #expect(sous[0].transport?.dureeModifiee == nil)
        #expect(sous.last?.transport == nil)

        // Prix dans la monnaie locale du voyage.
        #expect(sous[0].prixAdulte == 500)
        #expect(sous[0].monnaieAdulte == .locale)
        #expect(parent.notes.contains("Conseils"))
    }

    @Test func leTexteCollePeutEntourerLeJSON() throws {
        let texte = """
        Voici ton itinéraire :
        ```json
        {"format":"copilote-itineraire","version":1,"titre":"Lisbonne","etapes":[
          {"titre":"Belém","heure":"9h30","duree":90,"transport":{"mode":"tram","duree":25}},
          {"titre":"Alfama","heure":"11h30"}
        ]}
        ```
        Bon voyage !
        """
        let v = voyage()
        let parent = v.importer(try ItineraireClaude.lire(texte: texte), dans: contexte)
        let sous = parent.sousEtapes
        #expect(sous.count == 2)
        #expect(minutes(sous[0].heure) == 9 * 60 + 30)
        #expect(minutes(sous[0].heureFin) == 11 * 60)
        #expect(sous[0].transport?.mode == .commun)
        #expect(sous[0].transport?.sousType == "Tram")
        #expect(sous[0].lieu == "Belém")
    }

    @Test func unPrixDansUneDeviseInconnueResteDansLesNotes() throws {
        let json = #"{"titre":"Essai","etapes":[{"titre":"Musée","prix":{"adulte":15,"devise":"USD"}}]}"#
        let v = voyage()
        let s = try #require(v.importer(try ItineraireClaude.lire(Data(json.utf8)), dans: contexte).sousEtapes.first)
        #expect(s.prixAdulte == nil)
        #expect(s.notes.contains("15 USD"))
    }

    @Test func lesFichiersQuiNeSontPasDesItinerairesSontRefuses() {
        #expect(throws: ItineraireClaude.Erreur.self) { try ItineraireClaude.lire(texte: "") }
        #expect(throws: ItineraireClaude.Erreur.self) { try ItineraireClaude.lire(texte: "Bonjour") }
        #expect(throws: ItineraireClaude.Erreur.self) { try ItineraireClaude.lire(Data(#"{"voyages":[]}"#.utf8)) }
        #expect(throws: ItineraireClaude.Erreur.self) { try ItineraireClaude.lire(Data(#"{"format":"autre","titre":"x","etapes":[{"titre":"a"}]}"#.utf8)) }
        #expect(throws: ItineraireClaude.Erreur.self) { try ItineraireClaude.lire(Data(#"{"titre":"x","etapes":[]}"#.utf8)) }
    }

    @Test func heuresEtModesApprochantsSontCompris() {
        #expect(ItineraireClaude.heureMinutes("09:30")! == (9, 30))
        #expect(ItineraireClaude.heureMinutes("9h")! == (9, 0))
        #expect(ItineraireClaude.heureMinutes("14 h 05")! == (14, 5))
        #expect(ItineraireClaude.heureMinutes("2026-12-03T08:15:00")! == (8, 15))
        #expect(ItineraireClaude.heureMinutes("25:00") == nil)
        #expect(ItineraireClaude.mode("Métro", sousType: nil) == (ModeTransport.commun, "Métro"))
        #expect(ItineraireClaude.mode("à pied", sousType: nil) == (ModeTransport.pied, ""))
        #expect(ItineraireClaude.mode("taxi", sousType: nil) == (ModeTransport.voiture, "Taxi / VTC"))
        #expect(ItineraireClaude.categorie("Musée") == .musee)
        #expect(ItineraireClaude.categorie("restaurant") == .repas)
        #expect(ItineraireClaude.categorie("nature") == .visite)
    }
}
