import SwiftUI

/// Le décor d'un transport dans l'agenda : ciel et nuages pour l'avion, route pour la voiture, rails pour le train…
struct FondTransport: View {
    var mode: ModeTransport
    var sousType: String = ""

    private enum Decor { case ciel, route, voieBus, rails, tunnel, tram, mer, sentier, piste }

    private var decor: Decor {
        switch mode {
        case .avion: .ciel
        case .voiture: .route
        case .pied: .sentier
        case .velo: .piste
        case .commun:
            switch sousType {
            case "Bus": .voieBus
            case "Métro": .tunnel
            case "Tram": .tram
            case "Ferry": .mer
            default: .rails
            }
        }
    }

    var body: some View {
        Canvas { c, t in
            switch decor {
            case .ciel: ciel(c, t)
            case .route: route(c, t, asphalte: Color(rouge: 0x3A, vert: 0x3D, bleu: 0x44), marque: Color(rouge: 0xFF, vert: 0xD1, bleu: 0x3B))
            case .voieBus: route(c, t, asphalte: Color(rouge: 0x9C, vert: 0x3B, bleu: 0x35), marque: .white)
            case .rails: rails(c, t, fond: Color(rouge: 0x8E, vert: 0x84, bleu: 0x78), traverses: Color(rouge: 0x5E, vert: 0x44, bleu: 0x30))
            case .tunnel: rails(c, t, fond: Color(rouge: 0x1D, vert: 0x22, bleu: 0x33), traverses: Color(rouge: 0x3A, vert: 0x42, bleu: 0x5C), tunnel: true)
            case .tram: rails(c, t, fond: Color(rouge: 0x6B, vert: 0x70, bleu: 0x78), traverses: .clear)
            case .mer: mer(c, t)
            case .sentier: sentier(c, t)
            case .piste: piste(c, t)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Ciel

    private func ciel(_ c: GraphicsContext, _ t: CGSize) {
        let rect = CGRect(origin: .zero, size: t)
        c.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(rouge: 0x2F, vert: 0x8B, bleu: 0xF0), Color(rouge: 0xA9, vert: 0xDC, bleu: 0xFF)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: t.height)))
        // Des nuages : paquets de cercles blancs, répartis sur la largeur.
        let n = max(Int(t.width / 70), 2)
        for i in 0..<n {
            let cx = t.width * (CGFloat(i) + 0.3 + CGFloat((i * 37) % 5) / 10) / CGFloat(n)
            let cy = t.height * (0.28 + CGFloat((i * 53) % 6) / 10)
            let r = min(t.height * 0.34, 20) * (0.8 + CGFloat(i % 3) * 0.2)
            for (dx, dy, k) in [(-0.9, 0.2, 0.8), (0.0, -0.3, 1.0), (0.9, 0.15, 0.85), (0.3, 0.3, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                let cercle = CGRect(x: cx + dx * r - r * k, y: cy + dy * r - r * k, width: 2 * r * k, height: 2 * r * k)
                c.fill(Path(ellipseIn: cercle), with: .color(.white.opacity(0.92)))
            }
        }
    }

    // MARK: Route

    private func route(_ c: GraphicsContext, _ t: CGSize, asphalte: Color, marque: Color) {
        c.fill(Path(CGRect(origin: .zero, size: t)), with: .color(asphalte))
        // Grain de l'asphalte.
        for i in 0..<Int(t.width * t.height / 90) {
            let x = CGFloat((i * 97) % Int(max(t.width, 1))), y = CGFloat((i * 53) % Int(max(t.height, 1)))
            c.fill(Path(CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.07)))
        }
        // Lignes de rive, et ligne centrale en tirets.
        for y in [4.0, t.height - 4.0] {
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: t.width, y: y))
            c.stroke(p, with: .color(.white.opacity(0.85)), lineWidth: 1.6)
        }
        var milieu = Path(); milieu.move(to: CGPoint(x: 0, y: t.height / 2)); milieu.addLine(to: CGPoint(x: t.width, y: t.height / 2))
        c.stroke(milieu, with: .color(marque), style: StrokeStyle(lineWidth: 2.4, dash: [14, 10]))
    }

    // MARK: Rails

    private func rails(_ c: GraphicsContext, _ t: CGSize, fond: Color, traverses: Color, tunnel: Bool = false) {
        c.fill(Path(CGRect(origin: .zero, size: t)), with: .color(fond))
        if tunnel {
            // Lumières de tunnel, et ligne jaune de sécurité.
            for i in 0..<Int(t.width / 36) {
                c.fill(Path(ellipseIn: CGRect(x: 14 + CGFloat(i) * 36, y: 3, width: 5, height: 5)), with: .color(Color(rouge: 0xFF, vert: 0xE0, bleu: 0x82).opacity(0.9)))
            }
            c.fill(Path(CGRect(x: 0, y: t.height - 4, width: t.width, height: 2.5)), with: .color(Color(rouge: 0xFF, vert: 0xC9, bleu: 0x1F)))
        } else {
            for i in 0..<Int(t.width * t.height / 120) {
                let x = CGFloat((i * 89) % Int(max(t.width, 1))), y = CGFloat((i * 61) % Int(max(t.height, 1)))
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)), with: .color(.black.opacity(0.14)))
            }
        }
        let y1 = t.height * 0.32, y2 = t.height * 0.68
        // Traverses en bois, puis les deux rails brillants.
        var x: CGFloat = 4
        while x < t.width {
            c.fill(Path(roundedRect: CGRect(x: x, y: y1 - 5, width: 5, height: y2 - y1 + 10), cornerRadius: 1), with: .color(traverses))
            x += 13
        }
        for y in [y1, y2] {
            var rail = Path(); rail.move(to: CGPoint(x: 0, y: y)); rail.addLine(to: CGPoint(x: t.width, y: y))
            c.stroke(rail, with: .color(Color(white: 0.28)), lineWidth: 3.4)
            c.stroke(rail, with: .color(Color(white: 0.88)), lineWidth: 1.6)
        }
    }

    // MARK: Mer

    private func mer(_ c: GraphicsContext, _ t: CGSize) {
        c.fill(Path(CGRect(origin: .zero, size: t)), with: .linearGradient(
            Gradient(colors: [Color(rouge: 0x35, vert: 0xA7, bleu: 0xD9), Color(rouge: 0x0E, vert: 0x5F, bleu: 0x9E)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: t.height)))
        for ligne in 0..<max(Int(t.height / 12), 2) {
            var vague = Path()
            let y = 8 + CGFloat(ligne) * 12
            vague.move(to: CGPoint(x: 0, y: y))
            var x: CGFloat = 0
            while x < t.width {
                vague.addQuadCurve(to: CGPoint(x: x + 14, y: y), control: CGPoint(x: x + 7, y: y - 4 - CGFloat(ligne % 2) * 2))
                x += 14
            }
            c.stroke(vague, with: .color(.white.opacity(0.4)), lineWidth: 1.3)
        }
    }

    // MARK: À pied et à vélo

    private func sentier(_ c: GraphicsContext, _ t: CGSize) {
        c.fill(Path(CGRect(origin: .zero, size: t)), with: .color(Color(rouge: 0x6E, vert: 0xA8, bleu: 0x4F)))
        let chemin = CGRect(x: 0, y: t.height * 0.18, width: t.width, height: t.height * 0.64)
        c.fill(Path(chemin), with: .color(Color(rouge: 0xE2, vert: 0xCF, bleu: 0xA2)))
        // Empreintes de pas, alternées.
        var x: CGFloat = 10, haut = true
        while x < t.width {
            c.fill(Path(ellipseIn: CGRect(x: x, y: t.height / 2 + (haut ? -7 : 2), width: 5, height: 7)), with: .color(Color(rouge: 0x9A, vert: 0x80, bleu: 0x52).opacity(0.85)))
            x += 16; haut.toggle()
        }
    }

    private func piste(_ c: GraphicsContext, _ t: CGSize) {
        c.fill(Path(CGRect(origin: .zero, size: t)), with: .color(Color(rouge: 0x2E, vert: 0x8B, bleu: 0x57)))
        for y in [3.0, t.height - 3.0] {
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: t.width, y: y))
            c.stroke(p, with: .color(.white.opacity(0.8)), lineWidth: 1.4)
        }
        var milieu = Path(); milieu.move(to: CGPoint(x: 0, y: t.height / 2)); milieu.addLine(to: CGPoint(x: t.width, y: t.height / 2))
        c.stroke(milieu, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
    }
}

/// Une étiquette lisible sur n'importe quel décor : pastille claire avec l'icône, le titre et le détail.
struct EtiquetteTransport: View {
    var symbole: String
    var titre: String
    var detail: String = ""
    var teinte: Color = .indigo

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbole).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(teinte))
            VStack(alignment: .leading, spacing: 0) {
                Text(titre).font(.caption.weight(.bold)).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
