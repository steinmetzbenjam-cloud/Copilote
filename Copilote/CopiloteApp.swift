import SwiftUI
import SwiftData

@main
struct CopiloteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Voyage.self)
    }
}
