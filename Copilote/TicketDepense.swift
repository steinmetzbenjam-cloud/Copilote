import SwiftUI

extension CategorieDepense {
    /// Une couleur par type de dépense, reprise sur le ticket.
    var couleurTicket: Color {
        switch self {
        case .restauration: Color(rouge: 0xF5, vert: 0x7C, bleu: 0x1F)
        case .transport: Color(rouge: 0x2F, vert: 0x7B, bleu: 0xF2)
        case .hebergement: Color(rouge: 0x6C, vert: 0x4B, bleu: 0xE0)
        case .activites: Color(rouge: 0xE8, vert: 0x3E, bleu: 0x8C)
        case .courses: Color(rouge: 0x1F, vert: 0xA8, bleu: 0x5A)
        case .autre: Color(rouge: 0x6B, vert: 0x7A, bleu: 0x8F)
        }
    }
}

/// Un bord supérieur droit et un bord inférieur en dents de scie, comme un ticket arraché.
struct BordTicket: Shape {
    var dent: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = max(Int((rect.width / (dent * 1.6)).rounded()), 2)
        let pas = rect.width / CGFloat(n)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - dent))
        for i in 0..<n {
            let x = rect.maxX - pas * CGFloat(i)
            p.addLine(to: CGPoint(x: x - pas / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: x - pas, y: rect.maxY - dent))
        }
        p.closeSubpath()
        return p
    }
}

/// Une ligne pointillée de ticket de caisse.
private struct Pointilles: View {
    var body: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary.opacity(0.6)).frame(height: 1)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Faux code-barres décoratif, propre à chaque dépense.
private struct CodeBarres: View {
    var graine: String

    var body: some View {
        let barres = Self.largeurs(graine)
        HStack(spacing: 1.5) {
            ForEach(barres.indices, id: \.self) { Rectangle().frame(width: barres[$0], height: 16) }
        }
        .foregroundStyle(.secondary.opacity(0.7))
    }

    private static func largeurs(_ texte: String) -> [CGFloat] {
        var v = texte.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return (0..<34).map { _ in
            v = v &* 1664525 &+ 1013904223
            return CGFloat(1 + (v >> 24) % 3)
        }
    }
}

/// La dépense présentée comme un ticket de caisse : bandeau de couleur selon le type, lignes pointillées, total en gras.
struct TicketDepense: View {
    var depense: Depense
    var payeur: Membre?
    var voyage: Voyage
    var pour: String
    var etape: String?
    var enEuros: String?
    var total: String
    @Environment(\.colorScheme) private var schema

    private var couleur: Color { depense.estRemboursement ? Color(rouge: 0x0E, vert: 0x9F, bleu: 0x9A) : depense.categorie.couleurTicket }
    private var papier: Color { schema == .dark ? Color(rouge: 0x2A, vert: 0x2A, bleu: 0x2E) : Color(rouge: 0xFF, vert: 0xFD, bleu: 0xF6) }
    private var mono: Font { .system(.footnote, design: .monospaced) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: depense.estRemboursement ? "arrow.left.arrow.right" : depense.categorie.symbole).font(.system(size: 13, weight: .bold))
                Text((depense.estRemboursement ? "Remboursement" : depense.categorie.libelle).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 4)
                Text(depense.date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(couleur)

            VStack(alignment: .leading, spacing: 8) {
                Text(depense.titre.isEmpty ? (depense.estRemboursement ? "Remboursement" : "Sans titre") : depense.titre)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold)).foregroundStyle(.primary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Pointilles()
                ligne("PAYÉ PAR") {
                    HStack(spacing: 6) {
                        if let payeur { RondMembre(membre: payeur, voyage: voyage, taille: 20) }
                        Text(payeur?.nom ?? "—").lineLimit(1)
                    }
                }
                ligne(depense.estRemboursement ? "À" : "POUR") { Text(pour).lineLimit(1) }
                if let etape { ligne("ÉTAPE") { Text(etape).lineLimit(1) } }
                Pointilles()
                HStack(alignment: .firstTextBaseline) {
                    Text("TOTAL").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(total).font(.system(size: 19, weight: .heavy, design: .monospaced)).foregroundStyle(couleur).minimumScaleFactor(0.7).lineLimit(1)
                }
                if let enEuros { Text("≈ \(enEuros)").font(mono).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }
                Spacer(minLength: 0)
                CodeBarres(graine: depense.uid).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 16)
        }
        .frame(width: 236, height: 262, alignment: .top)
        .background(papier)
        .clipShape(BordTicket())
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }

    private func ligne<V: View>(_ titre: String, @ViewBuilder _ valeur: () -> V) -> some View {
        HStack(spacing: 8) {
            Text(titre).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            valeur().font(mono).foregroundStyle(.primary)
        }
    }
}
