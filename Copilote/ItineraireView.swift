import SwiftUI
import SwiftData

struct ItineraireView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?

    private let cal = Calendar.current

    private var horsDates: [Etape] {
        voyage.etapes.filter { e in !voyage.jours.contains { cal.isDate($0, inSameDayAs: e.jour) } }
    }

    var body: some View {
        List {
            ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                Section {
                    ForEach(voyage.etapes(du: jour)) { ligne($0) }
                    Button("Ajouter une étape", systemImage: "plus.circle") { ajouter(le: jour) }
                        .buttonStyle(.borderless)
                } header: {
                    Text("Jour \(index + 1) · \(jour.formatted(.dateTime.weekday(.wide).day().month()))")
                }
            }
            if !horsDates.isEmpty {
                Section("Hors des dates du voyage") {
                    ForEach(horsDates) { ligne($0) }
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
                Image(systemName: etape.categorie.symbole)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).font(.headline)
                    if etape.noteGoogle != nil || etape.noteTripadvisor != nil {
                        NotesView(google: etape.noteGoogle.flatMap { n in etape.avisGoogle.map { (n, $0) } },
                                  tripadvisor: etape.noteTripadvisor.flatMap { n in etape.avisTripadvisor.map { (n, $0) } })
                    }
                    if !etape.lieu.isEmpty {
                        Text(etape.lieu).lineLimit(1).font(.subheadline).foregroundStyle(.secondary)
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
        .swipeActions {
            Button("Supprimer", role: .destructive) { contexte.delete(etape) }
        }
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }

    private func ajouter(le jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }
}
