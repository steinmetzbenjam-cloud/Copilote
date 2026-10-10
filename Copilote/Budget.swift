import SwiftUI
import SwiftData

/// Monnaie dans laquelle un prix est saisi : l'euro, la monnaie locale du voyage, ou la troisième monnaie choisie dans Infos.
enum MonnaiePrix {
    case euro, locale, tierce

    init(locale: Bool, tierce: Bool) { self = tierce ? .tierce : (locale ? .locale : .euro) }
}

/// Monnaies du voyage : la locale et une troisième au choix (codes ISO : CRC, USD…), avec ce que vaut 1 € dans chacune.
extension Voyage {
    var aUneMonnaieLocale: Bool { !(deviseLocale ?? "").isEmpty }
    var aUneMonnaieTierce: Bool { !(deviseTierce ?? "").isEmpty }

    /// Le montant converti dans l'autre monnaie, quand le taux est connu.
    func versEuros(_ local: Double) -> Double? {
        guard let taux = tauxChange, taux > 0 else { return nil }
        return local / taux
    }

    func versLocal(_ euros: Double) -> Double? {
        guard let taux = tauxChange, taux > 0 else { return nil }
        return euros * taux
    }

    /// Ce que vaut 1 € dans la monnaie (1 pour l'euro), si le taux est connu.
    func taux(_ m: MonnaiePrix) -> Double? {
        switch m {
        case .euro: 1
        case .locale: tauxChange.flatMap { $0 > 0 ? $0 : nil }
        case .tierce: tauxTierce.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// Code ISO de la monnaie, si elle est choisie.
    func code(_ m: MonnaiePrix) -> String? {
        switch m {
        case .euro: "EUR"
        case .locale: aUneMonnaieLocale ? deviseLocale : nil
        case .tierce: aUneMonnaieTierce ? deviseTierce : nil
        }
    }

    func versEuros(_ montant: Double, depuis m: MonnaiePrix) -> Double? { taux(m).map { montant / $0 } }
    func depuisEuros(_ euros: Double, vers m: MonnaiePrix) -> Double? { taux(m).map { euros * $0 } }

    /// Un montant dans la monnaie `code` (euro, locale ou troisième), en euros.
    func versEuros(_ montant: Double, code: String) -> Double? {
        if code == "EUR" { return montant }
        if aUneMonnaieLocale, code == deviseLocale { return versEuros(montant, depuis: .locale) }
        if aUneMonnaieTierce, code == deviseTierce { return versEuros(montant, depuis: .tierce) }
        return nil
    }

    /// Les monnaies proposées pour saisir un montant : l'euro, puis la locale et la troisième si elles sont choisies.
    var codesMonnaies: [String] {
        var codes = ["EUR"]
        for c in [deviseLocale, deviseTierce].compactMap({ $0 }) where !c.isEmpty && !codes.contains(c) { codes.append(c) }
        return codes
    }
}

enum Monnaies {
    /// Libellé d'une monnaie : « CRC · colón costaricien ».
    static func libelle(_ code: String) -> String {
        let nom = Locale(identifier: "fr_FR").localizedString(forCurrencyCode: code) ?? code
        return "\(code) · \(nom)"
    }

    /// Toutes les monnaies, triées par nom.
    static var toutes: [String] {
        Locale.commonISOCurrencyCodes.sorted { libelle($0).localizedCompare(libelle($1)) == .orderedAscending }
    }

    /// La monnaie du premier pays du voyage qui n'utilise pas l'euro.
    static func suggeree(pour pays: [String]) -> String? {
        for code in pays {
            if let monnaie = Locale(identifier: "en_\(code)").currency?.identifier, monnaie != "EUR" { return monnaie }
        }
        return nil
    }

    static func formater(_ montant: Double, _ code: String) -> String {
        montant.formatted(.currency(code: code).precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR")))
    }

    /// Combien de `code` valent 1 €. Service gratuit et sans clé : aucun crédit n'est consommé.
    static func taux(pour code: String) async -> Double? {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/EUR"),
              let (donnees, reponse) = try? await URLSession.shared.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let taux = json["rates"] as? [String: Any],
              let valeur = taux[code] as? Double, valeur > 0 else { return nil }
        return valeur
    }
}

/// Infos du voyage : la monnaie locale, une troisième monnaie au choix, et leurs taux de change en euros.
struct SectionMonnaie: View {
    @Bindable var voyage: Voyage
    @State private var tierceOuverte = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChoixMonnaie(titre: "Monnaie locale", aucune: "Aucune (euro)", code: $voyage.deviseLocale, taux: $voyage.tauxChange)
            if voyage.aUneMonnaieTierce || tierceOuverte {
                Divider()
                ChoixMonnaie(titre: "Troisième monnaie", aucune: "À choisir", code: $voyage.deviseTierce, taux: $voyage.tauxTierce)
                Button("Retirer la troisième monnaie", systemImage: "minus.circle", role: .destructive) {
                    voyage.deviseTierce = nil
                    voyage.tauxTierce = nil
                    tierceOuverte = false
                }
                .buttonStyle(.borderless)
            } else {
                Button("Ajouter une troisième monnaie", systemImage: "plus.circle.fill") { tierceOuverte = true }
                    .buttonStyle(.borderless)
            }
            Text("Sert à saisir le budget de chaque étape et les dépenses dans la monnaie du pays (ou une troisième, le dollar par exemple). Les taux peuvent être corrigés à la main.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear {
            if voyage.deviseLocale == nil, let suggestion = Monnaies.suggeree(pour: voyage.pays) {
                voyage.deviseLocale = suggestion
            }
        }
    }
}

/// Une monnaie au choix, ce que vaut 1 € dans cette monnaie, et le bouton pour reprendre le taux du jour.
private struct ChoixMonnaie: View {
    let titre: String
    let aucune: String
    @Binding var code: String?
    @Binding var taux: Double?
    @State private var enCours = false
    @State private var message = ""

    var body: some View {
        Picker(titre, selection: Binding(get: { code ?? "" }, set: { choisir($0.isEmpty ? nil : $0) })) {
            Text(aucune).tag("")
            ForEach(Monnaies.toutes, id: \.self) { Text(Monnaies.libelle($0)).tag($0) }
        }
        if let code, !code.isEmpty {
            LabeledContent("1 € =") {
                HStack(spacing: 6) {
                    TextField("Taux", value: $taux, format: .number.precision(.fractionLength(0...4)))
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(code).foregroundStyle(.secondary)
                }
            }
            Button { Task { await actualiser() } } label: {
                Label(enCours ? "Mise à jour…" : "Actualiser le taux", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(enCours)
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func choisir(_ nouveau: String?) {
        code = nouveau
        taux = nil
        message = ""
        if nouveau != nil { Task { await actualiser() } }
    }

    private func actualiser() async {
        guard let code else { return }
        enCours = true
        defer { enCours = false }
        if let valeur = await Monnaies.taux(pour: code) {
            taux = valeur
            message = "Taux du jour : 1 € = \(valeur.formatted(.number.precision(.fractionLength(0...4)))) \(code)."
        } else {
            message = "Taux introuvable : saisis-le à la main."
        }
    }
}

/// Trois lignes de prix par personne (adulte, étudiant, enfant), chacune saisie en euros, en monnaie locale ou dans la troisième monnaie.
/// Commun à la fiche d'une étape et à celle d'un transport.
struct LignesPrix: View {
    let voyage: Voyage?
    var adulte: Binding<Double?>
    var adulteMonnaie: Binding<MonnaiePrix>
    var etudiant: Binding<Double?>
    var etudiantMonnaie: Binding<MonnaiePrix>
    var enfant: Binding<Double?>
    var enfantMonnaie: Binding<MonnaiePrix>

    /// Les colonnes : la monnaie locale, l'euro, puis la troisième monnaie, quand elles sont choisies.
    private var colonnes: [MonnaiePrix] {
        guard let voyage else { return [.euro] }
        return (voyage.aUneMonnaieLocale ? [.locale] : []) + [.euro] + (voyage.aUneMonnaieTierce ? [.tierce] : [])
    }

    private func sigle(_ m: MonnaiePrix) -> String {
        m == .euro ? "€" : (voyage?.code(m) ?? "")
    }

    var body: some View {
        // Une colonne par monnaie, son code en tête : les cases s'alignent d'une ligne à l'autre.
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.frame(width: 1, height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(colonnes, id: \.self) { m in
                    Text(sigle(m)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                        .frame(width: largeurCase, alignment: .center)
                }
            }
            ligne("Adulte", adulte, adulteMonnaie)
            ligne("Étudiant", etudiant, etudiantMonnaie)
            ligne("Enfant", enfant, enfantMonnaie)
        }
    }

    private var largeurCase: CGFloat { colonnes.count >= 3 ? 66 : 76 }

    /// Une case par monnaie. Ce que l'on tape dans l'une remplit les autres ;
    /// seul le dernier montant saisi est gardé (avec sa monnaie), les autres cases sont calculées avec les taux.
    private func ligne(_ titre: String, _ prix: Binding<Double?>, _ monnaie: Binding<MonnaiePrix>) -> some View {
        GridRow {
            // Le libellé garde sa taille : jamais tronqué ni coupé sur deux lignes.
            Text(titre).lineLimit(1).fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridColumnAlignment(.leading)
            ForEach(colonnes, id: \.self) { m in
                saisie(Binding<Double?>(
                    get: {
                        guard let valeur = prix.wrappedValue else { return nil }
                        if monnaie.wrappedValue == m { return valeur }
                        return voyage?.versEuros(valeur, depuis: monnaie.wrappedValue).flatMap { voyage?.depuisEuros($0, vers: m) }
                    },
                    set: { prix.wrappedValue = $0; monnaie.wrappedValue = m }))
            }
        }
    }

    private func saisie(_ valeur: Binding<Double?>) -> some View {
        // Une case blanche bordée : on voit où cliquer pour taper le prix.
        TextField("", value: valeur, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.plain)
            // Sans libellé : dans un formulaire Mac, la place du libellé vide étirait la case en hauteur.
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.gray.opacity(0.35), lineWidth: 1))
            .foregroundStyle(.black)
            .frame(width: largeurCase)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }
}

/// Pied commun aux sections de prix : rappelle où régler les monnaies et les taux.
func piedBudget(_ voyage: Voyage?) -> Text {
    if let voyage, !voyage.aUneMonnaieLocale, !voyage.aUneMonnaieTierce {
        Text("Choisis la monnaie locale dans l'onglet Infos pour saisir un prix dans la monnaie du pays.")
    } else if let voyage, (voyage.aUneMonnaieLocale && voyage.taux(.locale) == nil) || (voyage.aUneMonnaieTierce && voyage.taux(.tierce) == nil) {
        Text("Renseigne les taux de change dans l'onglet Infos pour voir la conversion.")
    } else {
        Text("Tape le prix dans l'une des cases : les autres se remplissent avec les taux du voyage.")
    }
}

extension Transport {
    var monnaieAdulte: MonnaiePrix {
        get { MonnaiePrix(locale: prixAdulteLocal ?? false, tierce: prixAdulteTierce ?? false) }
        set { prixAdulteLocal = newValue == .locale; prixAdulteTierce = newValue == .tierce }
    }
    var monnaieEtudiant: MonnaiePrix {
        get { MonnaiePrix(locale: prixEtudiantLocal ?? false, tierce: prixEtudiantTierce ?? false) }
        set { prixEtudiantLocal = newValue == .locale; prixEtudiantTierce = newValue == .tierce }
    }
    var monnaieEnfant: MonnaiePrix {
        get { MonnaiePrix(locale: prixEnfantLocal ?? false, tierce: prixEnfantTierce ?? false) }
        set { prixEnfantLocal = newValue == .locale; prixEnfantTierce = newValue == .tierce }
    }
}

/// Fiche d'un transport : le prix par personne, comme pour une étape (voir `EtapeEditView`).
struct SectionBudgetTransport: View {
    let voyage: Voyage?
    @Binding var transport: Transport

    var body: some View {
        Section {
            LignesPrix(voyage: voyage,
                       adulte: $transport.prixAdulte, adulteMonnaie: $transport.monnaieAdulte,
                       etudiant: $transport.prixEtudiant, etudiantMonnaie: $transport.monnaieEtudiant,
                       enfant: $transport.prixEnfant, enfantMonnaie: $transport.monnaieEnfant)
        } header: {
            Text("Budget")
        } footer: {
            piedBudget(voyage)
        }
    }
}

extension Etape {
    /// Monnaie de chaque prix : rangée dans deux drapeaux (monnaie locale, troisième monnaie) pour garder les données déjà enregistrées.
    var monnaieAdulte: MonnaiePrix {
        get { MonnaiePrix(locale: prixAdulteLocal, tierce: prixAdulteTierce) }
        set { prixAdulteLocal = newValue == .locale; prixAdulteTierce = newValue == .tierce }
    }
    var monnaieEtudiant: MonnaiePrix {
        get { MonnaiePrix(locale: prixEtudiantLocal, tierce: prixEtudiantTierce) }
        set { prixEtudiantLocal = newValue == .locale; prixEtudiantTierce = newValue == .tierce }
    }
    var monnaieEnfant: MonnaiePrix {
        get { MonnaiePrix(locale: prixEnfantLocal, tierce: prixEnfantTierce) }
        set { prixEnfantLocal = newValue == .locale; prixEnfantTierce = newValue == .tierce }
    }

    var aUnBudget: Bool { prixAdulte != nil || prixEnfant != nil || prixEtudiant != nil }

    /// Les trois prix en euros, dans l'ordre adulte / étudiant / enfant, séparés par un slash : « 12 € / 8 € / 6 € ».
    /// Un prix saisi dans une autre monnaie est converti ; un prix absent (ou sans taux pour le convertir) s'affiche « — ».
    var resumeBudget: String? {
        guard aUnBudget else { return nil }
        func euros(_ prix: Double?, _ monnaie: MonnaiePrix) -> String {
            guard let prix else { return "—" }
            if monnaie == .euro { return Monnaies.formater(prix, "EUR") }
            return voyage?.versEuros(prix, depuis: monnaie).map { Monnaies.formater($0, "EUR") } ?? "—"
        }
        return [euros(prixAdulte, monnaieAdulte), euros(prixEtudiant, monnaieEtudiant), euros(prixEnfant, monnaieEnfant)]
            .joined(separator: " / ")
    }
}
