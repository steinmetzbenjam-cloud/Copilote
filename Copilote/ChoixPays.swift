import SwiftUI

/// Le choix d'un pays : une liste avec recherche (« cos » trouve le Costa Rica), drapeau en tête.
struct ChoixPaysView: View {
    /// Pays déjà choisis : ils ne sont pas proposés à nouveau.
    var dejaChoisis: [String] = []
    var onChoix: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recherche = ""
    /// Le champ de recherche est actif dès l'ouverture : on tape tout de suite le début du nom.
    @State private var rechercheActive = false

    private var resultats: [Pays] {
        let proposes = Pays.tous.filter { !dejaChoisis.contains($0.code) }
        let texte = recherche.trimmingCharacters(in: .whitespaces)
        guard !texte.isEmpty else { return proposes }
        return proposes.filter { $0.nom.localizedStandardContains(texte) || $0.code.caseInsensitiveCompare(texte) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List(resultats) { pays in
                Button {
                    onChoix(pays.code)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(pays.drapeau).font(.title2)
                        Text(pays.nom).foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if resultats.isEmpty {
                    ContentUnavailableView.search(text: recherche)
                }
            }
            .searchable(text: $recherche, isPresented: $rechercheActive, prompt: "Rechercher un pays")
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { rechercheActive = true } }
            .navigationTitle("Choisir un pays")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #endif
    }
}

/// Les pays choisis (avec leur drapeau, un bouton pour retirer chacun), puis le bouton qui ouvre la recherche d'un pays.
struct ListePays: View {
    @Binding var pays: [String]
    @State private var choixOuvert = false

    var body: some View {
        ForEach(pays, id: \.self) { code in
            if let p = Pays.avec(code: code) {
                HStack {
                    Text(p.drapeau)
                    Text(p.nom)
                    Spacer()
                    Button("Retirer", systemImage: "xmark.circle.fill") { pays.removeAll { $0 == code } }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary).buttonStyle(.plain)
                }
            }
        }
        Button(pays.isEmpty ? "Choisir un pays" : "Ajouter un pays", systemImage: "magnifyingglass") { choixOuvert = true }
            .buttonStyle(.borderless)
            .sheet(isPresented: $choixOuvert) {
                ChoixPaysView(dejaChoisis: pays) { pays.append($0) }
            }
    }
}
