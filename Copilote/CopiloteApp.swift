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
            // La synchronisation iCloud est gérée par PartageCloud (partage entre comptes) : on empêche
            // SwiftData de synchroniser lui-même la base, ce qu'il tente sinon dès que l'app a l'autorisation iCloud.
            let configuration = ModelConfiguration(cloudKitDatabase: .none)
            conteneur = try ModelContainer(
                for: Voyage.self, Membre.self, Etape.self, Reservation.self, Document.self, JourVoyage.self, Depense.self,
                configurations: configuration)
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
