import SwiftUI
import SwiftData

struct ReservationsView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var enEdition: Reservation?

    private var reservations: [Reservation] {
        voyage.reservations.sorted { $0.debut < $1.debut }
    }

    /// Totaux par devise, sans conversion.
    private var totaux: [(devise: String, montant: Double)] {
        Dictionary(grouping: voyage.reservations.filter { $0.prix != nil }, by: \.devise)
            .map { ($0.key, $0.value.compactMap(\.prix).reduce(0, +)) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            Section {
                ForEach(reservations) { r in
                    Button { enEdition = r } label: { ligne(r) }.buttonStyle(.plain)
                        .swipeActions {
                            Button("Supprimer", role: .destructive) { contexte.delete(r) }
                        }
                }
                Button("Ajouter une réservation", systemImage: "plus.circle", action: ajouter)
                    .buttonStyle(.borderless)
            } header: {
                Text("Réservations")
            } footer: {
                if !totaux.isEmpty {
                    Text("Total : " + totaux.map { $0.montant.formatted(.currency(code: $0.devise)) }.joined(separator: " + "))
                }
            }

            DocumentsSection(voyage: voyage, reservation: nil, titre: "Documents du voyage")
        }
        .sheet(item: $enEdition, onDismiss: nettoyer) { r in
            ReservationEditView(reservation: r, voyage: voyage) { contexte.delete(r) }
        }
    }

    private func ligne(_ r: Reservation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.type.symbole).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.titre.isEmpty ? r.type.libelle : r.titre).font(.headline)
                Text(r.debut.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !r.numeroConfirmation.isEmpty {
                        Label(r.numeroConfirmation, systemImage: "number").labelStyle(.titleAndIcon)
                    }
                    if !r.documents.isEmpty {
                        Label("\(r.documents.count)", systemImage: "paperclip")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let prix = r.prix {
                Text(prix.formatted(.currency(code: r.devise))).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func ajouter() {
        let r = Reservation(debut: voyage.debut)
        r.voyage = voyage
        contexte.insert(r)
        enEdition = r
    }

    /// Une réservation créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for r in voyage.reservations where r.titre.trimmingCharacters(in: .whitespaces).isEmpty
            && r.fournisseur.isEmpty && r.numeroConfirmation.isEmpty && r.documents.isEmpty {
            contexte.delete(r)
        }
    }
}
