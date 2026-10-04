import SwiftUI
import SwiftData

@main
struct CopiloteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegue
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegue
    #endif

    private let conteneur: ModelContainer

    init() {
        do {
            conteneur = try ModelContainer(for: Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self)
        } catch {
            fatalError("Impossible d'ouvrir la base de données : \(error)")
        }
        PartageCloud.shared.configurer(contexte: conteneur.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(conteneur)
    }
}
