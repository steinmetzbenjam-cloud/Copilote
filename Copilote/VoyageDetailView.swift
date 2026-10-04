import SwiftUI
import SwiftData

struct VoyageDetailView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var nouveauMembre = ""

    private var membresTries: [Membre] {
        voyage.membres.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        Form {
            Section("Voyage") {
                TextField("Titre", text: $voyage.titre)
                TextField("Destination", text: $voyage.destination)
            }

            Section("Dates") {
                DatePicker("Départ", selection: $voyage.debut, displayedComponents: .date)
                DatePicker("Retour", selection: $voyage.fin, in: voyage.debut..., displayedComponents: .date)
                LabeledContent("Durée", value: "\(voyage.nombreDeJours) jour\(voyage.nombreDeJours > 1 ? "s" : "")")
            }

            Section("Voyageurs (\(voyage.membres.count))") {
                ForEach(membresTries) { membre in
                    Label(membre.nom, systemImage: "person.fill")
                        .contextMenu {
                            Button("Retirer", role: .destructive) { contexte.delete(membre) }
                        }
                }
                .onDelete { indices in
                    for i in indices { contexte.delete(membresTries[i]) }
                }
                HStack {
                    TextField("Ajouter un voyageur", text: $nouveauMembre)
                        .onSubmit(ajouterMembre)
                    Button("Ajouter", action: ajouterMembre)
                        .disabled(nouveauMembre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Notes") {
                TextEditor(text: $voyage.notes)
                    .frame(minHeight: 100)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(voyage.titre)
        .onChange(of: voyage.debut) { _, debut in
            if voyage.fin < debut { voyage.fin = debut }
        }
    }

    private func ajouterMembre() {
        let nom = nouveauMembre.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return }
        let membre = Membre(nom: nom)
        membre.voyage = voyage
        contexte.insert(membre)
        nouveauMembre = ""
    }
}
