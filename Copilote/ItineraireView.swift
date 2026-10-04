import SwiftUI
import SwiftData

/// Le planning : une carte par jour, avec sa date, ses lieux de référence et ses étapes.
struct ItineraireView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?
    @State private var jourEnEdition: JourVoyage?

    private let cal = Calendar.current

    private var horsDates: [Etape] {
        voyage.etapes.filter { e in !voyage.jours.contains { cal.isDate($0, inSameDayAs: e.jour) } }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(Array(voyage.jours.enumerated()), id: \.element) { index, jour in
                    carte(numero: index + 1, jour: jour)
                }
                if !horsDates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hors des dates du voyage").font(.headline)
                        ForEach(horsDates) { ligne($0) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(FondDeCarte())
                }
            }
            .padding(16)
        }
        .background(FondDePage.couleur)
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
        .sheet(item: $jourEnEdition, onDismiss: nettoyerJours) { infos in
            JourEditView(jour: infos, voyage: voyage, numero: (voyage.jours.firstIndex { cal.isDate($0, inSameDayAs: infos.date) } ?? 0) + 1)
        }
    }

    // MARK: Carte d'un jour

    private func carte(numero: Int, jour: Date) -> some View {
        let infos = voyage.infos(du: jour)
        let etapes = voyage.etapes(du: jour)
        return VStack(alignment: .leading, spacing: 10) {
            Button { jourEnEdition = infos ?? creerInfos(jour) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(.tint)
                        Spacer()
                        Image(systemName: "pencil.circle").foregroundStyle(.secondary)
                    }
                    Text(premiereLettreEnMajuscule(jour.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                        .font(.title3.bold()).foregroundStyle(.primary)
                    if let titre = infos?.titre, !titre.isEmpty {
                        Text(titre).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let lieux = infos?.lieux, !lieux.isEmpty {
                        FlowLayout(espacement: 6) {
                            ForEach(lieux) { lieu in
                                Label(lieu.etiquette, systemImage: lieu.estPays ? "flag.fill" : "mappin.circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.tint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                        }
                    } else {
                        Label("Où se passe la journée ?", systemImage: "mappin.and.ellipse")
                            .font(.footnote).foregroundStyle(.tertiary)
                    }
                    if let notes = infos?.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            if etapes.isEmpty {
                Text("Aucune étape").font(.footnote).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(etapes) { ligne($0) }
                }
            }

            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(le: jour) }
                .buttonStyle(.borderless)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
    }

    private func ligne(_ etape: Etape) -> some View {
        Button { etapeEnEdition = etape } label: {
            HStack(spacing: 12) {
                Image(systemName: etape.categorie.symbole)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(etape.titre.isEmpty ? "Sans titre" : etape.titre).font(.headline).foregroundStyle(.primary)
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
        .contextMenu {
            Button("Supprimer", systemImage: "trash", role: .destructive) { contexte.delete(etape) }
        }
    }

    private func premiereLettreEnMajuscule(_ texte: String) -> String {
        texte.prefix(1).uppercased() + texte.dropFirst()
    }

    // MARK: Création et nettoyage

    private func creerInfos(_ jour: Date) -> JourVoyage {
        let infos = JourVoyage(date: jour)
        infos.voyage = voyage
        contexte.insert(infos)
        return infos
    }

    /// Une étape créée puis laissée vide est retirée à la fermeture.
    private func nettoyer() {
        for etape in voyage.etapes where etape.titre.trimmingCharacters(in: .whitespaces).isEmpty && etape.lieu.isEmpty {
            contexte.delete(etape)
        }
    }

    private func nettoyerJours() {
        for infos in voyage.infosJours where infos.estVide { contexte.delete(infos) }
    }

    private func ajouter(le jour: Date) {
        let etape = Etape(titre: "", jour: jour)
        etape.voyage = voyage
        contexte.insert(etape)
        etapeEnEdition = etape
    }
}

/// Fond arrondi d'une carte de jour.
struct FondDeCarte: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FondDePage.carte))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

enum FondDePage {
    static var couleur: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var carte: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
