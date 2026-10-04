import SwiftUI

struct ReglagesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var google = Cles.lire(.google) ?? ""
    @State private var tripadvisor = Cles.lire(.tripadvisor) ?? ""
    private var cloud = PartageCloud.shared
    @State private var avertissement: String?
    @State private var resultatsTest: [Cles.Service: (ok: Bool, message: String)] = [:]
    @State private var testEnCours = false
    @State private var referent = Cles.referentTripadvisor

    private func etat(_ service: Cles.Service, saisie: String) -> Cles.Etat {
        saisie.isEmpty ? .absente : Cles.etat(service)
    }

    private func apercu(_ saisie: String) -> String { "Clé affichée ici : " + Cles.empreinte(saisie) + "." }

    private func texteEtat(_ etat: Cles.Etat) -> String {
        switch etat {
        case .absente: ""
        case .synchronisee: "Synchronisée avec tes autres appareils (trousseau iCloud)."
        case .locale: "Gardée sur cet appareil seulement : valide avec OK pour la synchroniser (le trousseau iCloud doit être activé)."
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
                    Text("Active « Places API (New) » dans ton projet Google Cloud, puis crée une clé. Notes, avis, photos, horaires et descriptions.\n\(apercu(google)) \(texteEtat(etat(.google, saisie: google)))")
                }

                Section {
                    SecureField("Clé d'API", text: $tripadvisor)
                        .autocorrectionDisabled()
                    TextField("Adresse du site déclaré (facultatif)", text: $referent)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    Link("Créer une clé Tripadvisor", destination: URL(string: "https://www.tripadvisor.com/developers")!)
                } header: {
                    Text("Tripadvisor")
                } footer: {
                    Text("Clé « Content API » du portail développeurs Tripadvisor. Notes, avis, classement, descriptions.\n\(apercu(tripadvisor)) \(texteEtat(etat(.tripadvisor, saisie: tripadvisor)))")
                }

                Section {
                    Button(testEnCours ? "Test en cours…" : "Tester mes clés", systemImage: "checkmark.shield") {
                        Task {
                            testEnCours = true
                            resultatsTest[.google] = await TestCles.tester(.google, cle: google)
                            resultatsTest[.tripadvisor] = await TestCles.tester(.tripadvisor, cle: tripadvisor, referent: referent)
                            testEnCours = false
                        }
                    }
                    .disabled(testEnCours || (google.isEmpty && tripadvisor.isEmpty))
                    ForEach(Cles.Service.allCases) { service in
                        if let r = resultatsTest[service] {
                            Label("\(service.nom) : \(r.message)", systemImage: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.footnote).foregroundStyle(r.ok ? .green : .red)
                        }
                    }
                } footer: {
                    Text("Envoie une requête de test à Google et à Tripadvisor avec les clés saisies ci-dessus, et affiche leur réponse.")
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
                        Cles.referentTripadvisor = referent
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
