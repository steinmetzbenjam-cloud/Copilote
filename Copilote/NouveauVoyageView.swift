import SwiftUI

/// Fiche de création d'un voyage : rien n'est créé tant qu'on n'a pas touché « Créer ».
struct NouveauVoyageView: View {
    var onCreer: (Voyage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var titre = ""
    @State private var pays: [String] = []
    @State private var debut = Calendar.current.startOfDay(for: .now)
    @State private var fin = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))!
    @FocusState private var titreActif: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Voyage") {
                    TextField("Nom du voyage", text: $titre)
                        .focused($titreActif)
                }

                Section {
                    ListePays(pays: $pays)
                } header: {
                    Text("Pays")
                } footer: {
                    Text("La carte et la recherche de lieux se centrent sur ces pays.")
                }

                Section("Dates") {
                    DatePicker("Départ", selection: $debut, displayedComponents: .date)
                    DatePicker("Retour", selection: $fin, in: debut..., displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nouveau voyage")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer", action: creer)
                }
            }
            .onChange(of: debut) { _, nouveau in if fin < nouveau { fin = nouveau } }
            .onAppear { titreActif = true }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private func creer() {
        let nom = titre.trimmingCharacters(in: .whitespaces)
        let voyage = Voyage(titre: nom.isEmpty ? "Nouveau voyage" : nom,
                            debut: debut, fin: fin)
        voyage.pays = pays
        onCreer(voyage)
        dismiss()
    }
}
