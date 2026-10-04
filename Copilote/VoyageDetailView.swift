import SwiftUI
import SwiftData

struct VoyageDetailView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var nouveauMembre = ""
    @State private var paysAAjouter = ""

    private var membresTries: [Membre] {
        voyage.membres.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        Form {
            Section("Voyage") {
                TextField("Titre", text: $voyage.titre)
                TextField("Destination", text: $voyage.destination)
            }

            Section {
                ForEach(voyage.pays, id: \.self) { code in
                    if let pays = Pays.avec(code: code) {
                        HStack {
                            Text(pays.drapeau)
                            Text(pays.nom)
                            Spacer()
                            Button("Retirer", systemImage: "xmark.circle.fill") {
                                voyage.pays.removeAll { $0 == code }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                }
                Picker(voyage.pays.isEmpty ? "Choisir un pays" : "Ajouter un pays", selection: $paysAAjouter) {
                    Text("—").tag("")
                    ForEach(Pays.tous.filter { !voyage.pays.contains($0.code) }) { pays in
                        Text("\(pays.drapeau)  \(pays.nom)").tag(pays.code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: paysAAjouter) { _, code in
                    guard !code.isEmpty else { return }
                    voyage.pays.append(code)
                    paysAAjouter = ""
                }
            } header: {
                Text("Pays")
            } footer: {
                Text("La carte et la recherche de lieux se centrent sur ces pays.")
            }

            SectionPartage(voyage: voyage)

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
