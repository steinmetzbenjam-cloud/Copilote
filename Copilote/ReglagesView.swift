import SwiftUI

struct ReglagesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var google = Cles.lire(.google) ?? ""
    @State private var tripadvisor = Cles.lire(.tripadvisor) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Clé d'API", text: $google)
                        .autocorrectionDisabled()
                    Link("Créer une clé Google Places", destination: URL(string: "https://console.cloud.google.com/apis/library/places.googleapis.com")!)
                } header: {
                    Text("Google Places")
                } footer: {
                    Text("Active « Places API (New) » dans ton projet Google Cloud, puis crée une clé. Notes, avis, photos, horaires et descriptions.")
                }

                Section {
                    SecureField("Clé d'API", text: $tripadvisor)
                        .autocorrectionDisabled()
                    Link("Créer une clé Tripadvisor", destination: URL(string: "https://www.tripadvisor.com/developers")!)
                } header: {
                    Text("Tripadvisor")
                } footer: {
                    Text("Clé « Content API » du portail développeurs Tripadvisor. Notes, avis, classement, descriptions.")
                }

                Section {
                } footer: {
                    Text("Les clés restent dans le trousseau de cet appareil, et ne sont jamais envoyées ailleurs que chez Google et Tripadvisor. Sans clé, les suggestions viennent de Plans, sans notes.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Réglages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        Cles.enregistrer(google, pour: .google)
                        Cles.enregistrer(tripadvisor, pour: .tripadvisor)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
