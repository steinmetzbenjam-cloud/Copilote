import SwiftUI
import UniformTypeIdentifiers

struct DepotSurJour: ViewModifier {
    var actif: Bool
    var action: ([String]) -> Bool

    @ViewBuilder func body(content: Content) -> some View {
        if actif { content.dropDestination(for: String.self) { elements, _ in action(elements) } } else { content }
    }
}

/// Fines diagonales, pour reconnaître d'un coup d'œil un transport.
struct Hachures: View {
    var couleur: Color
    var espace: CGFloat

    var body: some View {
        Canvas { contexte, taille in
            var x = -taille.height
            while x < taille.width {
                var trait = Path()
                trait.move(to: CGPoint(x: x, y: taille.height))
                trait.addLine(to: CGPoint(x: x + taille.height, y: 0))
                contexte.stroke(trait, with: .color(couleur), lineWidth: 1.4)
                x += espace
            }
        }
        .allowsHitTesting(false)
    }
}

/// Les étapes préparées sans jour : on les range sur un jour d'un geste.
struct APlacerView: View {
    @Bindable var voyage: Voyage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var etape: Etape?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(voyage.etapesSansJour) { e in
                        HStack(spacing: 10) {
                            Image(systemName: e.categorie.symbole).foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(e.titre.isEmpty ? "Sans titre" : e.titre)
                                if !e.lieu.isEmpty { Text(e.lieu).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { etape = e }
                            Spacer()
                            Menu("Placer…") {
                                ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                                    Button("Jour \(i + 1) · \(jour.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))") {
                                        _ = voyage.deplacer(e, vers: jour, avant: nil)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                            .disabled(voyage.lectureSeule)
                        }
                    }
                    .onDelete { for i in $0 { contexte.delete(voyage.etapesSansJour[i]) } }
                } footer: {
                    Text(voyage.etapesSansJour.isEmpty ? "Aucune étape en attente. Prépare ici des idées, puis place-les sur un jour." : "Choisis un jour : l'étape apparaît dans l'agenda, à l'heure que tu règles ensuite.")
                }
                Section {
                    Button("Ajouter une idée", systemImage: "plus.circle.fill") {
                        let e = Etape(titre: "", jour: nil)
                        e.ordre = (voyage.etapesSansJour.map(\.ordre).max() ?? -1) + 1
                        e.voyage = voyage
                        contexte.insert(e)
                        etape = e
                    }
                    .disabled(voyage.lectureSeule)
                }
            }
            .navigationTitle("À placer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(item: $etape, onDismiss: {
                for e in voyage.etapes where e.titre.trimmingCharacters(in: .whitespaces).isEmpty && e.lieu.isEmpty { contexte.delete(e) }
            }) { e in
                EtapeEditView(etape: e, jours: voyage.jours) { contexte.delete(e) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}
