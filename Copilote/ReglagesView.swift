import SwiftUI

struct ReglagesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var google = Cles.lire(.google) ?? ""
    @State private var tripadvisor = Cles.lire(.tripadvisor) ?? ""
    private var cloud = PartageCloud.shared

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
                    Toggle("Synchroniser avec iCloud", isOn: Binding(get: { cloud.actif }, set: { cloud.definirActif($0) }))
                        .disabled(!PartageCloud.disponible)
                    if !PartageCloud.disponible {
                        Text("Indisponible dans cette version de l'app : il faut un compte Apple Developer payant (voir SETUP-ICLOUD.md).")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if !cloud.statut.isEmpty {
                        Text(cloud.statut).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Garde tes voyages à jour sur tous tes appareils et permet de les partager avec ton groupe.")
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
