import SwiftUI
import SwiftData

/// Le planning : une carte par jour, avec sa date, ses lieux de référence et ses étapes.
struct ItineraireView: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var etapeEnEdition: Etape?
    @State private var jourEnEdition: JourVoyage?
    /// Étape au-dessus de laquelle on s'apprête à déposer (trait d'insertion), ou jour survolé.
    @State private var etapeVisee: String?
    @State private var jourVise: Date?
    /// Jour sur lequel la carte est cadrée ; nil = tout le voyage.
    @State private var jourSelectionne: Date?

    private let cal = Calendar.current

    private var horsDates: [Etape] {
        voyage.etapes.filter { e in !voyage.jours.contains { cal.isDate($0, inSameDayAs: e.jour) } }
    }

    var body: some View {
        GeometryReader { geo in
            let panneauLateral = geo.size.width >= 700
            if panneauLateral {
                // iPad, Mac : la carte en fond, les jours empilés dans un panneau à gauche.
                ZStack(alignment: .leading) {
                    fondDeCarte(margeGauche: Self.largeurPanneau)
                    ScrollView { listeDesJours.padding(12) }
                        .frame(width: Self.largeurPanneau)
                        .scrollIndicators(.hidden)
                }
            } else {
                // iPhone : la carte en haut, les jours dessous.
                VStack(spacing: 0) {
                    fondDeCarte(margeGauche: 0).frame(height: max(220, geo.size.height * 0.36))
                    ScrollView { listeDesJours.padding(12) }
                        .background(FondDePage.couleur)
                }
            }
        }
        .sheet(item: $etapeEnEdition, onDismiss: nettoyer) { etape in
            EtapeEditView(etape: etape, jours: voyage.jours) { contexte.delete(etape) }
        }
        .sheet(item: $jourEnEdition, onDismiss: nettoyerJours) { infos in
            JourEditView(jour: infos, voyage: voyage, numero: (voyage.jours.firstIndex { cal.isDate($0, inSameDayAs: infos.date) } ?? 0) + 1)
        }
    }

    private static let largeurPanneau: CGFloat = 404

    private func fondDeCarte(margeGauche: CGFloat) -> some View {
        CarteDuVoyage(voyage: voyage, jourFocus: jourSelectionne, masquerAutresJours: false, margeGauche: margeGauche) { etape in
            etapeEnEdition = etape
        }
    }

    /// Les jours, les uns au-dessus des autres.
    private var listeDesJours: some View {
        LazyVStack(spacing: 12) {
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
    }

    private func estSelectionne(_ jour: Date) -> Bool {
        jourSelectionne.map { cal.isDate($0, inSameDayAs: jour) } ?? false
    }

    // MARK: Carte d'un jour

    private func carte(numero: Int, jour: Date) -> some View {
        let infos = voyage.infos(du: jour)
        let etapes = voyage.etapes(du: jour)
        // Même couleur et mêmes numéros que le tracé et les repères sur la carte.
        let couleur = CarteDuVoyage.couleur(du: numero - 1)
        let placees = etapes.filter { $0.coordonnee != nil }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { jourSelectionne = estSelectionne(jour) ? nil : jour }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("JOUR \(numero)").font(.caption.bold()).foregroundStyle(couleur)
                        Spacer()
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
                                    .background(couleur.opacity(0.14), in: Capsule())
                                    .foregroundStyle(couleur)
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
                    ForEach(etapes) { etape in
                        ligneGlissable(etape, jour: jour, couleur: couleur,
                                       rang: placees.firstIndex { $0 === etape })
                    }
                }
            }

            Button("Ajouter une étape", systemImage: "plus.circle.fill") { ajouter(le: jour) }
                .buttonStyle(.borderless)
                .tint(couleur)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondDeCarte())
        .overlay(alignment: .leading) {
            Capsule().fill(couleur).frame(width: 5).padding(.vertical, 16).padding(.leading, 5)
        }
        .overlay(alignment: .topTrailing) { menuDuJour(jour, infos: infos) }
        .overlay {
            if estSelectionne(jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2.5)
            }
        }
        .overlay {
            if let jourVise, cal.isDate(jourVise, inSameDayAs: jour) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(couleur, lineWidth: 2)
            }
        }
        .dropDestination(for: String.self) { elements, _ in
            recevoir(elements, jour: jour, avant: nil)
        } isTargeted: { visee in
            if visee { jourVise = jour } else if let actuel = jourVise, cal.isDate(actuel, inSameDayAs: jour) { jourVise = nil }
        }
    }

    // MARK: Glisser-déposer

    private static let prefixe = "copilote-etape:"

    private func ligneGlissable(_ etape: Etape, jour: Date, couleur: Color, rang: Int?) -> some View {
        ligne(etape, couleur: couleur, rang: rang)
            .draggable(Self.prefixe + etape.uid) {
                Label(etape.titre.isEmpty ? "Étape" : etape.titre, systemImage: etape.categorie.symbole)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .top) {
                if etapeVisee == etape.uid {
                    Capsule().fill(.tint).frame(height: 3).offset(y: -7)
                }
            }
            .dropDestination(for: String.self) { elements, _ in
                recevoir(elements, jour: jour, avant: etape)
            } isTargeted: { visee in
                if visee { etapeVisee = etape.uid } else if etapeVisee == etape.uid { etapeVisee = nil }
            }
    }

    /// Menu de la carte : modifier le jour, ou remettre ses étapes dans l'ordre des heures.
    private func menuDuJour(_ jour: Date, infos: JourVoyage?) -> some View {
        Menu {
            Button("Modifier le jour", systemImage: "pencil") { jourEnEdition = infos ?? creerInfos(jour) }
            Button("Trier par heure", systemImage: "clock") { trierParHeure(jour) }
                .disabled(voyage.etapes(du: jour).count < 2)
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary).padding(12)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func recevoir(_ elements: [String], jour: Date, avant cible: Etape?) -> Bool {
        defer { etapeVisee = nil; jourVise = nil }
        guard let uid = elements.first(where: { $0.hasPrefix(Self.prefixe) })?.dropFirst(Self.prefixe.count) else { return false }
        return deplacer(String(uid), vers: jour, avant: cible)
    }

    private func deplacer(_ uid: String, vers jour: Date, avant cible: Etape?) -> Bool {
        guard let etape = voyage.etapes.first(where: { $0.uid == uid }) else { return false }
        return withAnimation { voyage.deplacer(etape, vers: jour, avant: cible) }
    }

    private func trierParHeure(_ jour: Date) {
        withAnimation { voyage.trierParHeure(jour) }
    }

    /// `rang` : numéro du repère sur la carte (étapes placées seulement) ; sinon l'icône de la catégorie.
    private func ligne(_ etape: Etape, couleur: Color = .accentColor, rang: Int? = nil) -> some View {
        Button { etapeEnEdition = etape } label: {
            HStack(spacing: 12) {
                Group {
                    if let rang {
                        Text("\(rang + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(couleur, in: Circle())
                    } else {
                        Image(systemName: etape.categorie.symbole)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(couleur)
                    }
                }
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
        etape.ordre = voyage.prochainOrdre(du: jour)
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
