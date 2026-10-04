import SwiftUI

struct ReglagesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var google = Cles.lire(.google) ?? ""
    @State private var tripadvisor = Cles.lire(.tripadvisor) ?? ""
    private var cloud = PartageCloud.shared
    @State private var avertissement: String?

    private func etat(_ service: Cles.Service, saisie: String) -> Cles.Etat {
        saisie.isEmpty ? .absente : Cles.etat(service)
    }

    private func texteEtat(_ etat: Cles.Etat) -> String {
        switch etat {
        case .absente: ""
        case .synchronisee: "Synchronisée avec tes autres appareils (trousseau iCloud)."
        case .locale: "Gardée sur cet appareil seulement : active le trousseau iCloud pour la retrouver ailleurs."
        }
    }

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
                    Text("Active « Places API (New) » dans ton projet Google Cloud, puis crée une clé. Notes, avis, photos, horaires et descriptions.\n\(texteEtat(etat(.google, saisie: google)))")
                }

                Section {
                    SecureField("Clé d'API", text: $tripadvisor)
                        .autocorrectionDisabled()
                    Link("Créer une clé Tripadvisor", destination: URL(string: "https://www.tripadvisor.com/developers")!)
                } header: {
                    Text("Tripadvisor")
                } footer: {
                    Text("Clé « Content API » du portail développeurs Tripadvisor. Notes, avis, classement, descriptions.\n\(texteEtat(etat(.tripadvisor, saisie: tripadvisor)))")
                }

                if let avertissement {
                    Section {
                        Label(avertissement, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                        Button("Fermer quand même") { dismiss() }
                    }
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
                    Text("Les clés sont gardées dans ton trousseau iCloud : saisies une fois, elles apparaissent sur tous tes appareils. Elles ne sont jamais envoyées ailleurs que chez Google et Tripadvisor, ni aux autres voyageurs. Sans clé, les suggestions viennent de Plans, sans notes.")
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
                        let g = Cles.enregistrer(google, pour: .google)
                        let t = Cles.enregistrer(tripadvisor, pour: .tripadvisor)
                        if g && t { dismiss() } else {
                            avertissement = "Clés gardées sur cet appareil seulement : le trousseau iCloud n'est pas disponible. Active-le dans Réglages → ton nom → iCloud → Mots de passe et trousseau."
                        }
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
