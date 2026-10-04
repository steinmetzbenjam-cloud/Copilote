import SwiftUI
import SwiftData
import CoreLocation

/// Onglet « Étapes » : toutes les étapes du voyage. On peut en préparer sans savoir quel jour elles auront lieu.
struct EtapesView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?
    @State private var transportEnEdition: PaireEtapes?

    struct PaireEtapes: Identifiable {
        let depart: Etape, arrivee: Etape
        var id: String { depart.uid }
    }

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
                        ForEach(Array(etapes.enumerated()), id: \.element.id) { i, etape in
                            ligne(etape)
                            if i + 1 < etapes.count { ligneTransport(etape, etapes[i + 1]) }
                        }
                    }
                }
            }
        }
        .sheet(item: $transportEnEdition) { TransportEditView(depart: $0.depart, arrivee: $0.arrivee) }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
    }

    /// Entre deux étapes : le transport prévu, ou un bouton pour en ajouter un.
    private func ligneTransport(_ depart: Etape, _ arrivee: Etape) -> some View {
        Button { transportEnEdition = PaireEtapes(depart: depart, arrivee: arrivee) } label: {
            HStack(spacing: 8) {
                if let t = depart.transport {
                    Image(systemName: t.mode.symbole).frame(width: 24)
                    Text(descriptif(t))
                    if t.mode.aUnItineraire, let a = depart.coordonnee, let b = arrivee.coordonnee {
                        Spacer()
                        ResumeItineraire(a: a, b: b, mode: t.mode)
                    }
                } else {
                    Image(systemName: "plus.circle").frame(width: 24)
                    Text("Ajouter un transport")
                }
            }
            .font(.subheadline)
            .foregroundStyle(depart.transport == nil ? Color.accentColor : Color.secondary)
            .padding(.leading, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func descriptif(_ t: Transport) -> String {
        var morceaux = [t.mode.libelle]
        if t.mode == .commun, !t.sousType.isEmpty { morceaux = [t.sousType] }
        let ligne = [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " ")
        if !ligne.isEmpty { morceaux.append(ligne) }
        if let d = t.depart {
            morceaux.append(d.formatted(date: .omitted, time: .shortened) + (t.arrivee.map { " → " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
        }
        return morceaux.joined(separator: " · ")
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

private struct ResumeItineraire: View {
    let a: CLLocationCoordinate2D
    let b: CLLocationCoordinate2D
    let mode: ModeTransport
    @State private var itineraires = Itineraires.shared

    var body: some View {
        Text(itineraires.trajet(a, b, mode)?.resume ?? "…")
            .font(.caption).foregroundStyle(.secondary)
            .task(id: Itineraires.cle(a, b, mode)) { await itineraires.charger(a, b, mode) }
    }
}
