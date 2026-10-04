import SwiftUI
import SwiftData

/// Onglet « Étapes » : toutes les étapes du voyage. On peut en préparer sans savoir quel jour elles auront lieu.
struct EtapesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?

    var body: some View {
        List {
            Section {
                if voyage.etapesSansJour.isEmpty {
                    Text("Aucune étape en attente. Prépare ici des idées, tu les glisseras ensuite sur un jour dans l'itinéraire.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(voyage.etapesSansJour) { ligne($0) }
                Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter() }
            } header: {
                Label("À placer", systemImage: "tray.full")
            }
            ForEach(voyage.jours, id: \.self) { jour in
                let etapes = voyage.etapes(du: jour)
                if !etapes.isEmpty {
                    Section(jour.formatted(.dateTime.weekday(.wide).day().month())) {
                        ForEach(etapes) { ligne($0) }
                    }
                }
            }
        }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
    }

    private func ligne(_ etape: Etape) -> some View {
        Button { etapeEnEdition = etape } label: {
            HStack(spacing: 12) {
                Image(systemName: etape.categorie.symbole).frame(width: 24).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).foregroundStyle(.primary)
                    if !etape.lieu.isEmpty {
                        Text(etape.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if let heure = etape.heure {
                    Text(heure.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ajouter() {
        let etape = Etape(titre: "", jour: nil)
        etape.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }
}
