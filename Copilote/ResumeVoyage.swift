import SwiftUI
import UniformTypeIdentifiers
import ImageIO

/// Le résumé du voyage, mis en page pour être envoyé à tout le groupe : budget, familles, comptes, jour par jour.
struct ResumeVoyageVue: View {
    var voyage: Voyage
    private let calcul: BudgetCalcule
    private let teinte = Color(rouge: 0x5B, vert: 0x6C, bleu: 0xFF)

    init(voyage: Voyage) {
        self.voyage = voyage
        self.calcul = voyage.calculerBudget()
    }

    private func eur(_ x: Double) -> String { Monnaies.formater(x, "EUR") }

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

    private var unites: [(nom: String, membres: [Membre], photo: Data?)] {
        voyage.familles.map { ($0.nom, $0.membres, voyage.photo(famille: $0.nom)) }
            + voyage.membresSansFamille.map { ($0.nom, [$0], $0.avatar) }
    }

    var body: some View {
        let total = calcul.elements.total(pour: voyage.membres)
        VStack(alignment: .leading, spacing: 22) {
            entete(total)
            postes
            familles
            comptes
            jours
            Text("Résumé créé avec Copilote le \(Date.now.formatted(date: .long, time: .omitted)).")
                .font(.caption).foregroundStyle(.gray)
        }
        .padding(28)
        .frame(width: 640, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .foregroundStyle(Color(white: 0.12))
    }

    private func entete(_ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(voyage.titre.isEmpty ? "Voyage" : voyage.titre)
                .font(PoliceVoyage.police(pour: voyage.pays, taille: 34)).foregroundStyle(.white)
            Text(voyage.pays.compactMap { Pays.avec(code: $0).map { "\($0.drapeau) \($0.nom)" } }.joined(separator: "  ·  "))
                .font(.subheadline).foregroundStyle(.white.opacity(0.95))
            Text("\(voyage.debut.formatted(date: .long, time: .omitted)) → \(voyage.fin.formatted(date: .long, time: .omitted)) · \(voyage.nombreDeJours) jour\(voyage.nombreDeJours > 1 ? "s" : "")")
                .font(.subheadline).foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(eur(total)).font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("pour \(voyage.membres.count) voyageur\(voyage.membres.count > 1 ? "s" : "")").foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [teinte, Color(rouge: 0xFF, vert: 0x7A, bleu: 0x59)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func titre(_ texte: String, _ symbole: String, _ c: Color) -> some View {
        Label(texte, systemImage: symbole).font(.headline).foregroundStyle(c)
    }

    private var postes: some View {
        let lignes = CategorieEtape.allCases
            .map { p in (poste: p, montant: calcul.elements.filter { $0.poste == p }.total(pour: voyage.membres)) }
            .filter { $0.montant > 0 }.sorted { $0.montant > $1.montant }
        let somme = lignes.reduce(0) { $0 + $1.montant }
        return VStack(alignment: .leading, spacing: 10) {
            titre("Par poste", "chart.pie.fill", .indigo)
            ForEach(lignes, id: \.poste) { l in
                VStack(spacing: 4) {
                    HStack {
                        Label(l.poste.libelle, systemImage: l.poste.symbole).foregroundStyle(couleur(l.poste))
                        Spacer()
                        Text(eur(l.montant)).monospacedDigit()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.9))
                            Capsule().fill(couleur(l.poste)).frame(width: g.size.width * l.montant / max(somme, 1))
                        }
                    }
                    .frame(height: 6)
                }
            }
            if lignes.isEmpty { Text("Aucun prix saisi.").foregroundStyle(.gray) }
        }
    }

    private var familles: some View {
        VStack(alignment: .leading, spacing: 10) {
            titre("Par famille", "person.3.fill", .teal)
            ForEach(unites, id: \.nom) { u in
                let prevu = calcul.elements.total(pour: u.membres)
                let regle = voyage.regle(par: Set(u.membres.map(\.uid))).euros
                HStack(spacing: 10) {
                    VignetteFamille(photo: u.photo, nom: u.nom, taille: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(u.nom).fontWeight(.semibold)
                        Text("\(u.membres.count) personne\(u.membres.count > 1 ? "s" : "")").font(.caption).foregroundStyle(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(eur(prevu)).monospacedDigit().fontWeight(.semibold)
                        if !voyage.depenses.isEmpty { Text("avancé \(eur(regle))").font(.caption).foregroundStyle(.gray).monospacedDigit() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var comptes: some View {
        let soldes = voyage.soldesParCompte(moi: "")
        let virements = soldes.keys.sorted().flatMap { devise in Comptes.virements(soldes[devise] ?? [:]).map { (devise, $0) } }
        if !voyage.depenses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                titre("Pour s'équilibrer", "arrow.left.arrow.right.circle.fill", .green)
                if virements.isEmpty {
                    Text("Tout le monde est à l'équilibre.").foregroundStyle(.gray)
                }
                ForEach(Array(virements.enumerated()), id: \.offset) { _, v in
                    HStack {
                        Text("\(voyage.nomDuCompte(v.1.de)) → \(voyage.nomDuCompte(v.1.vers))")
                        Spacer()
                        Text(Monnaies.formater(v.1.montant, v.0)).monospacedDigit().fontWeight(.semibold)
                    }
                }
                Text("Les membres d'une même famille ont des comptes communs.").font(.caption).foregroundStyle(.gray)
            }
        }
    }

    private var jours: some View {
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: 8) {
            titre("Jour par jour", "calendar", .orange)
            ForEach(Array(voyage.jours.enumerated()), id: \.offset) { i, jour in
                let elements = calcul.elements.filter { cal.isDate($0.jour, inSameDayAs: jour) }
                let etapes = voyage.etapes(du: jour).map { $0.titre.isEmpty ? $0.categorie.libelle : $0.titre }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Jour \(i + 1) · \(jour.formatted(.dateTime.weekday(.wide).day().month(.wide)))").fontWeight(.semibold)
                        Spacer()
                        Text(eur(elements.total(pour: voyage.membres))).monospacedDigit()
                    }
                    if !etapes.isEmpty { Text(etapes.joined(separator: " · ")).font(.caption).foregroundStyle(.gray) }
                }
                if i < voyage.jours.count - 1 { Divider() }
            }
        }
    }
}

/// Fabrique le PDF (une seule page, à la hauteur du contenu) et l'image du résumé.
@MainActor
enum ExportResume {
    static func fichiers(_ voyage: Voyage) -> (pdf: URL, image: URL)? {
        let dossier = FileManager.default.temporaryDirectory.appending(path: "resume-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let nom = "Résumé – " + (voyage.titre.isEmpty ? "voyage" : voyage.titre).replacingOccurrences(of: "/", with: "-")
        let pdf = dossier.appending(path: nom + ".pdf"), image = dossier.appending(path: nom + ".png")

        let rendu = ImageRenderer(content: ResumeVoyageVue(voyage: voyage))
        rendu.scale = 2
        var reussi = false
        rendu.render { taille, dessiner in
            var cadre = CGRect(origin: .zero, size: taille)
            guard let contexte = CGContext(pdf as CFURL, mediaBox: &cadre, nil) else { return }
            contexte.beginPDFPage(nil)
            dessiner(contexte)
            contexte.endPDFPage()
            contexte.closePDF()
            reussi = true
        }
        guard reussi, let cg = rendu.cgImage,
              let destination = CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (pdf, image)
    }
}
