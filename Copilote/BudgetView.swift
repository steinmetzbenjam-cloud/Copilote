import SwiftUI

/// Onglet « Budget » : combien le voyage coûte, pour tout le groupe, pour une famille ou pour une personne,
/// par poste (transport, repas, hébergement…) et par jour.
struct BudgetView: View {
    @Bindable var voyage: Voyage

    enum Portee: String, CaseIterable, Identifiable {
        case groupe = "Groupe", famille = "Famille", personne = "Personne"
        var id: String { rawValue }
    }

    @State private var portee = Portee.groupe
    @State private var familleChoisie = ""
    @State private var personneChoisie = ""

    // MARK: Périmètre

    private var familleEffective: String {
        voyage.familles.map(\.nom).first { $0.caseInsensitiveCompare(familleChoisie) == .orderedSame } ?? ""
    }

    private var personneEffective: String {
        let membres = voyage.membresTries
        if membres.contains(where: { $0.uid == personneChoisie }) { return personneChoisie }
        let moi = MoiVoyage.lire(voyage)
        return membres.contains(where: { $0.uid == moi }) ? moi : (membres.first?.uid ?? "")
    }

    private var concernes: [Membre] {
        switch portee {
        case .groupe: voyage.membresTries
        case .famille: voyage.membresTries.filter { $0.famille.caseInsensitiveCompare(familleEffective) == .orderedSame }
        case .personne: voyage.membresTries.filter { $0.uid == personneEffective }
        }
    }

    private func eur(_ montant: Double) -> String { Monnaies.formater(montant, "EUR") }

    private func couleur(_ poste: CategorieEtape) -> Color {
        switch poste {
        case .repas: .orange
        case .hebergement: .indigo
        case .transport: .blue
        case .visite: .pink
        case .activite: .green
        case .autre: .gray
        }
    }

    // MARK: Corps

    var body: some View {
        let calcul = voyage.calculerBudget()
        ScrollView {
            VStack(spacing: 14) {
                if voyage.membres.isEmpty {
                    CadreInfos(titre: "Budget", symbole: "eurosign.circle.fill", couleur: .green) {
                        Text("Pour calculer le coût du voyage, ajoute les voyageurs (et leur âge) dans l'onglet Infos, rangés par famille.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    cadreChoix
                    // En mode famille, les prix s'affichent une fois une famille choisie.
                    if portee != .famille || !familleEffective.isEmpty {
                        cadreTotal(calcul)
                        cadrePostes(calcul)
                        cadreJours(calcul)
                        cadreDetail(calcul)
                        cadreRemarques(calcul)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(FondDePage.couleur)
    }

    // MARK: Cadres

    private var cadreChoix: some View {
        VStack(spacing: 10) {
            Picker("Budget de", selection: $portee) {
                ForEach(Portee.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch portee {
            case .groupe:
                EmptyView()
            case .famille:
                if voyage.familles.isEmpty {
                    Text("Aucune famille : crée-les dans l'onglet Infos.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(voyage.familles) { vignette($0) }
                        }
                        .padding(.vertical, 4).padding(.horizontal, 4)
                    }
                    if familleEffective.isEmpty {
                        Text("Touche une famille pour voir ses prix.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            case .personne:
                Picker("Personne", selection: Binding(get: { personneEffective }, set: { personneChoisie = $0 })) {
                    ForEach(voyage.membresTries) { Text($0.nom).tag($0.uid) }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .modifier(FondDeCarte())
    }

    /// Une famille : sa photo (ou une icône) et son nom dessous. Toucher affiche ses prix.
    private func vignette(_ famille: GroupeFamille) -> some View {
        let choisie = famille.nom.caseInsensitiveCompare(familleEffective) == .orderedSame
        return Button { familleChoisie = famille.nom } label: {
            VStack(spacing: 6) {
                VignetteFamille(photo: voyage.photo(famille: famille.nom), nom: famille.nom, taille: 64)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: choisie ? 3 : 0).padding(-3))
                Text(famille.nom)
                    .font(.footnote.weight(choisie ? .semibold : .regular))
                    .foregroundStyle(choisie ? Color.accentColor : .primary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: 84)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Famille \(famille.nom)")
    }

    private func titreTotal() -> String {
        switch portee {
        case .groupe: "Prix du voyage · tout le groupe"
        case .famille: "Prix du voyage · famille \(familleEffective)"
        case .personne: "Prix du voyage · \(voyage.membre(uid: personneEffective)?.nom ?? "")"
        }
    }

    private func cadreTotal(_ calcul: BudgetCalcule) -> some View {
        let membres = concernes
        let total = calcul.elements.total(pour: membres)
        let uids = Set(membres.map(\.uid))
        let regle = voyage.regle(par: uids)
        let reste = total - regle.euros
        return CadreInfos(titre: titreTotal(), symbole: "eurosign.circle.fill", couleur: .green) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eur(total)).font(.system(size: 38, weight: .bold, design: .rounded))
                if let local = voyage.deviseLocale, let converti = voyage.versLocal(total), voyage.aUneMonnaieLocale {
                    Text("≈ \(Monnaies.formater(converti, local))").foregroundStyle(.secondary)
                }
                if membres.count > 1 {
                    Text("\(membres.count) personnes · en moyenne \(eur(total / Double(membres.count))) chacune")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !voyage.depenses.isEmpty {
                Divider()
                LabeledContent("Déjà réglé", value: eur(regle.euros))
                LabeledContent(reste >= 0 ? "Reste à régler" : "Réglé en trop", value: eur(abs(reste)))
                    .foregroundStyle(reste >= 0 ? Color.primary : .orange)
                if total > 0 {
                    barre(min(max(regle.euros / total, 0), 1), .green)
                }
            }
        }
    }

    private func cadrePostes(_ calcul: BudgetCalcule) -> some View {
        let membres = concernes
        let lignes = CategorieEtape.allCases
            .map { poste in (poste: poste, montant: calcul.elements.filter { $0.poste == poste }.total(pour: membres)) }
            .filter { $0.montant > 0 }
            .sorted { $0.montant > $1.montant }
        let total = lignes.reduce(0) { $0 + $1.montant }
        return CadreInfos(titre: "Par poste", symbole: "chart.pie.fill", couleur: .indigo) {
            if lignes.isEmpty {
                Text("Aucun prix saisi pour l'instant.").foregroundStyle(.secondary)
            }
            ForEach(lignes, id: \.poste) { ligne in
                VStack(spacing: 6) {
                    HStack {
                        Label(ligne.poste.libelle, systemImage: ligne.poste.symbole).foregroundStyle(couleur(ligne.poste))
                        Spacer()
                        Text(eur(ligne.montant)).monospacedDigit()
                        Text("\(Int((ligne.montant / total * 100).rounded())) %")
                            .font(.footnote).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    barre(ligne.montant / total, couleur(ligne.poste))
                }
            }
        }
    }

    private func cadreJours(_ calcul: BudgetCalcule) -> some View {
        let membres = concernes
        let cal = Calendar.current
        let jours = voyage.jours.enumerated().map { index, jour -> (index: Int, jour: Date, elements: [ElementBudget], total: Double) in
            let elements = calcul.elements.filter { cal.isDate($0.jour, inSameDayAs: jour) }
            return (index, jour, elements, elements.total(pour: membres))
        }
        let maximum = jours.map(\.total).max() ?? 0
        return CadreInfos(titre: "Par jour", symbole: "calendar", couleur: .orange,
                          pied: "Le coût de l'hébergement compte pour le jour qui précède la nuit : la journée se termine à l'hôtel.") {
            ForEach(jours, id: \.index) { jour in
                DisclosureGroup {
                    ForEach(jour.elements) { element in
                        let montant = [element].total(pour: membres)
                        if montant > 0 {
                            HStack {
                                Image(systemName: element.poste.symbole).foregroundStyle(couleur(element.poste)).frame(width: 22)
                                Text(element.titre).lineLimit(1)
                                Spacer()
                                Text(eur(montant)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Jour \(jour.index + 1) · \(jour.jour.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                            Spacer()
                            Text(eur(jour.total)).monospacedDigit().fontWeight(.semibold)
                        }
                        barre(maximum > 0 ? jour.total / maximum : 0, .orange)
                    }
                }
            }
        }
    }

    /// Selon le périmètre : les familles (groupe), les personnes (famille), ou le tarif de la personne.
    @ViewBuilder private func cadreDetail(_ calcul: BudgetCalcule) -> some View {
        switch portee {
        case .groupe:
            CadreInfos(titre: "Par famille", symbole: "person.3.fill", couleur: .teal) {
                ForEach(voyage.familles) { famille in
                    ligneFamille(famille.nom, famille.membres, calcul) {
                        familleChoisie = famille.nom
                        portee = .famille
                    }
                }
                ForEach(voyage.membresSansFamille) { membre in
                    ligneFamille(membre.nom, [membre], calcul) {
                        personneChoisie = membre.uid
                        portee = .personne
                    }
                }
            }
        case .famille:
            CadreInfos(titre: "Par personne", symbole: "person.2.fill", couleur: .teal) {
                ForEach(concernes) { membre in
                    Button {
                        personneChoisie = membre.uid
                        portee = .personne
                    } label: {
                        HStack {
                            AvatarView(initiales: Profil.initiales(de: membre.nom), donnees: membre.avatar, taille: 28,
                                       couleur: AvatarView.couleur(pour: membre.uid))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(membre.nom).foregroundStyle(.primary)
                                Text(detailPersonne(membre)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eur(calcul.elements.total(pour: [membre]))).monospacedDigit().foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .personne:
            if let membre = voyage.membre(uid: personneEffective) {
                CadreInfos(titre: "Tarif appliqué", symbole: "person.fill", couleur: .teal,
                           pied: "Le tarif découle de l'âge (enfant jusqu'à \(Tarif.ageEnfantMax) ans) ou du choix fait dans la fiche du voyageur, dans l'onglet Infos.") {
                    LabeledContent("Tarif", value: membre.tarif.libelle)
                    if let age = membre.age { LabeledContent("Âge", value: "\(age) ans") }
                    if !membre.famille.isEmpty { LabeledContent("Famille", value: membre.famille) }
                }
            }
        }
    }

    private func detailPersonne(_ membre: Membre) -> String {
        [membre.age.map { "\($0) ans" }, membre.tarif.libelle].compactMap { $0 }.joined(separator: " · ")
    }

    private func ligneFamille(_ nom: String, _ membres: [Membre], _ calcul: BudgetCalcule, ouvrir: @escaping () -> Void) -> some View {
        let total = calcul.elements.total(pour: membres)
        let regle = voyage.regle(par: Set(membres.map(\.uid))).euros
        return Button(action: ouvrir) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nom).foregroundStyle(.primary).fontWeight(.medium)
                    Text("\(membres.count) personne\(membres.count > 1 ? "s" : "")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(eur(total)).monospacedDigit().foregroundStyle(.primary)
                    if !voyage.depenses.isEmpty {
                        Text("réglé \(eur(regle)) · reste \(eur(total - regle))")
                            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func remarques(_ calcul: BudgetCalcule) -> [String] {
        var notes: [String] = []
        if calcul.etapesSansPrix > 0 {
            notes.append("\(calcul.etapesSansPrix) étape\(calcul.etapesSansPrix > 1 ? "s" : "") placée\(calcul.etapesSansPrix > 1 ? "s" : "") sans prix : elles ne sont pas comptées. Un prix manquant pour un tarif (par exemple enfant) compte pour 0 €.")
        }
        if calcul.etapesSansJour > 0 {
            notes.append("\(calcul.etapesSansJour) étape\(calcul.etapesSansJour > 1 ? "s" : "") avec un prix mais encore « à placer » : elles ne sont pas comptées.")
        }
        if calcul.tauxManquants > 0 {
            notes.append("Des prix sont saisis en monnaie locale sans taux de change : renseigne le taux dans l'onglet Infos.")
        }
        let ignorees = voyage.regle(par: Set(voyage.membres.map(\.uid))).ignorees
        if ignorees > 0 {
            notes.append("\(ignorees) dépense\(ignorees > 1 ? "s" : "") dans une autre monnaie que l'euro ou la monnaie locale ne sont pas prises en compte dans « Déjà réglé ».")
        }
        if !voyage.membres.isEmpty, voyage.membres.allSatisfy({ $0.age == nil && $0.tarifBrut == nil }) {
            notes.append("Aucun âge renseigné : tout le monde est compté au tarif adulte.")
        }
        return notes
    }

    @ViewBuilder private func cadreRemarques(_ calcul: BudgetCalcule) -> some View {
        let notes = remarques(calcul)
        if !notes.isEmpty {
            CadreInfos(titre: "À savoir", symbole: "exclamationmark.circle.fill", couleur: .gray) {
                ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func barre(_ part: Double, _ couleur: Color) -> some View {
        GeometryReader { geometrie in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(couleur).frame(width: max(part > 0 ? 4 : 0, geometrie.size.width * min(part, 1)))
            }
        }
        .frame(height: 6)
    }
}
