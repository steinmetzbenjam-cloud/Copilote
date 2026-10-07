import SwiftUI
import SwiftData

/// Monnaie locale du voyage : le code ISO (CRC, JPY…) et ce que vaut 1 € dans cette monnaie.
extension Voyage {
    var aUneMonnaieLocale: Bool { !(deviseLocale ?? "").isEmpty }

    /// Le montant converti dans l'autre monnaie, quand le taux est connu.
    func versEuros(_ local: Double) -> Double? {
        guard let taux = tauxChange, taux > 0 else { return nil }
        return local / taux
    }

    func versLocal(_ euros: Double) -> Double? {
        guard let taux = tauxChange, taux > 0 else { return nil }
        return euros * taux
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

/// Infos du voyage : la monnaie locale et son taux de change en euros.
struct SectionMonnaie: View {
    @Bindable var voyage: Voyage
    @State private var enCours = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Monnaie locale", selection: Binding(get: { voyage.deviseLocale ?? "" },
                                                        set: { choisir($0.isEmpty ? nil : $0) })) {
                Text("Aucune (euro)").tag("")
                ForEach(Monnaies.toutes, id: \.self) { Text(Monnaies.libelle($0)).tag($0) }
            }
            if let code = voyage.deviseLocale, !code.isEmpty {
                LabeledContent("1 € =") {
                    HStack(spacing: 6) {
                        TextField("Taux", value: $voyage.tauxChange, format: .number.precision(.fractionLength(0...4)))
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
            Text("Sert à saisir le budget de chaque étape dans la monnaie du pays. Le taux peut être corrigé à la main.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear {
            if voyage.deviseLocale == nil, let suggestion = Monnaies.suggeree(pour: voyage.pays) { choisir(suggestion) }
        }
    }

    private func choisir(_ code: String?) {
        voyage.deviseLocale = code
        voyage.tauxChange = nil
        message = ""
        if code != nil { Task { await actualiser() } }
    }

    private func actualiser() async {
        guard let code = voyage.deviseLocale else { return }
        enCours = true
        defer { enCours = false }
        if let taux = await Monnaies.taux(pour: code) {
            voyage.tauxChange = taux
            message = "Taux du jour : 1 € = \(taux.formatted(.number.precision(.fractionLength(0...4)))) \(code)."
        } else {
            message = "Taux introuvable : saisis-le à la main."
        }
    }
}

/// Fiche d'une étape : le prix pour les adultes, les enfants et les étudiants.
/// Chaque prix se saisit en euros ou en monnaie locale (au choix, ligne par ligne) ; l'autre monnaie est calculée.
struct SectionBudgetEtape: View {
    @Bindable var etape: Etape

    private var voyage: Voyage? { etape.voyage }

    var body: some View {
        Section {
            ligne("Adulte", $etape.prixAdulte, $etape.prixAdulteLocal)
            ligne("Étudiant", $etape.prixEtudiant, $etape.prixEtudiantLocal)
            ligne("Enfant", $etape.prixEnfant, $etape.prixEnfantLocal)
        } header: {
            Text("Budget")
        } footer: {
            if let voyage, !voyage.aUneMonnaieLocale {
                Text("Choisis la monnaie locale dans l'onglet Infos pour saisir un prix dans la monnaie du pays.")
            } else if voyage?.tauxChange == nil {
                Text("Renseigne le taux de change dans l'onglet Infos pour voir la conversion.")
            } else {
                Text("Tape le prix dans l'une des deux cases : l'autre se remplit avec le taux du voyage.")
            }
        }
    }

    /// Deux cases : monnaie locale à gauche, euros à droite. Ce que l'on tape dans l'une remplit l'autre.
    /// Seul le dernier montant saisi est gardé (avec sa monnaie) ; l'autre case est toujours calculée avec le taux.
    private func ligne(_ titre: String, _ prix: Binding<Double?>, _ local: Binding<Bool>) -> some View {
        let code = voyage?.deviseLocale ?? ""
        let aLocale = voyage?.aUneMonnaieLocale == true
        let caseLocale = Binding<Double?>(
            get: { local.wrappedValue ? prix.wrappedValue : prix.wrappedValue.flatMap { voyage?.versLocal($0) } },
            set: { prix.wrappedValue = $0; local.wrappedValue = true })
        let caseEuros = Binding<Double?>(
            get: { local.wrappedValue ? prix.wrappedValue.flatMap { voyage?.versEuros($0) } : prix.wrappedValue },
            set: { prix.wrappedValue = $0; local.wrappedValue = false })
        return LabeledContent(titre) {
            HStack(spacing: 14) {
                if aLocale { saisie(caseLocale, suffixe: code) }
                saisie(caseEuros, suffixe: "€")
            }
        }
    }

    private func saisie(_ valeur: Binding<Double?>, suffixe: String) -> some View {
        HStack(spacing: 4) {
            TextField("—", value: valeur, format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(suffixe).foregroundStyle(.secondary).font(.callout)
        }
    }
}

extension Etape {
    var aUnBudget: Bool { prixAdulte != nil || prixEnfant != nil || prixEtudiant != nil }

    /// Les trois prix en euros, dans l'ordre adulte / étudiant / enfant, séparés par un slash : « 12 € / 8 € / 6 € ».
    /// Un prix saisi en monnaie locale est converti ; un prix absent (ou sans taux pour le convertir) s'affiche « — ».
    var resumeBudget: String? {
        guard aUnBudget else { return nil }
        func euros(_ prix: Double?, _ local: Bool) -> String {
            guard let prix else { return "—" }
            if !local { return Monnaies.formater(prix, "EUR") }
            return voyage?.versEuros(prix).map { Monnaies.formater($0, "EUR") } ?? "—"
        }
        return [euros(prixAdulte, prixAdulteLocal), euros(prixEtudiant, prixEtudiantLocal), euros(prixEnfant, prixEnfantLocal)]
            .joined(separator: " / ")
    }
}
