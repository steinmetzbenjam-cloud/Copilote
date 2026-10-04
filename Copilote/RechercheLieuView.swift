import SwiftUI
import MapKit

struct RechercheLieuView: View {
    var requeteInitiale: String
    var pays: [String] = []
    var invite = "Aéroport, hôtel, musée, adresse…"
    var onChoix: (LieuTrouve) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var texte = ""
    @State private var resultats: [LieuTrouve] = []
    @State private var enCours = false
    @State private var aCherche = false
    @FocusState private var champActif: Bool

    private var nomsDesPays: String {
        pays.compactMap { Pays.avec(code: $0) }.map { "\($0.drapeau) \($0.nom)" }.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(invite, text: $texte)
                            .focused($champActif)
                            .autocorrectionDisabled()
                        if !texte.isEmpty {
                            Button("Effacer", systemImage: "xmark.circle.fill") {
                                texte = ""
                                champActif = true
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                } footer: {
                    if !pays.isEmpty { Text("Recherche limitée à : \(nomsDesPays)") }
                }

                Section {
                    ForEach(resultats) { lieu in
                        Button { choisir(lieu) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: lieu.symbole)
                                    .frame(width: 24)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lieu.nom).foregroundStyle(.primary)
                                    if !lieu.adresse.isEmpty {
                                        Text(lieu.adresse).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if enCours && resultats.isEmpty {
                    ProgressView()
                } else if aCherche && resultats.isEmpty && !enCours {
                    ContentUnavailableView.search(text: texte)
                }
            }
            .navigationTitle("Chercher un lieu")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task(id: texte) { await lancerRecherche() }
            .onAppear {
                texte = requeteInitiale
                champActif = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    private func lancerRecherche() async {
        guard texte.trimmingCharacters(in: .whitespaces).count >= 2 else {
            resultats = []
            aCherche = false
            return
        }
        // Petite pause pour ne pas interroger Plans à chaque lettre tapée.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        enCours = true
        let trouves = await RechercheLieux.chercher(texte, pays: pays)
        guard !Task.isCancelled else { return }
        resultats = trouves
        aCherche = true
        enCours = false
    }

    private func choisir(_ lieu: LieuTrouve) {
        onChoix(lieu)
        dismiss()
    }
}
