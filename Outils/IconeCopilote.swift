// Génère l'icône de Copilote : un avion au-dessus d'une carte dépliée.
// Usage : swiftc IconeCopilote.swift -o /tmp/icone && /tmp/icone <dossier de sortie>
import AppKit

func couleur(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Dessine l'icône dans un carré de 1024 × 1024 (origine en bas à gauche).
func dessiner(_ ctx: CGContext) {
    let espace = CGColorSpaceCreateDeviceRGB()

    // Ciel : dégradé du bleu profond vers un bleu clair.
    let ciel = CGGradient(colorsSpace: espace, colors: [couleur(0x0B4FD6).cgColor, couleur(0x4FA8FF).cgColor, couleur(0xA9DBFF).cgColor] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(ciel, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])

    // Carte dépliée en perspective : trois volets.
    let bas = (gauche: CGPoint(x: 70, y: 110), droite: CGPoint(x: 954, y: 110))
    let haut = (gauche: CGPoint(x: 200, y: 520), droite: CGPoint(x: 824, y: 520))
    func point(_ t: CGFloat, _ h: CGFloat) -> CGPoint {   // t : 0→1 de gauche à droite, h : 0 bas → 1 haut
        let xb = bas.gauche.x + (bas.droite.x - bas.gauche.x) * t, xh = haut.gauche.x + (haut.droite.x - haut.gauche.x) * t
        return CGPoint(x: xb + (xh - xb) * h, y: bas.gauche.y + (haut.gauche.y - bas.gauche.y) * h)
    }

    // Ombre de la carte.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: couleur(0x04225E, 0.55).cgColor)
    ctx.setFillColor(couleur(0xFFFFFF).cgColor)
    ctx.move(to: point(0, 0)); ctx.addLine(to: point(1, 0)); ctx.addLine(to: point(1, 1)); ctx.addLine(to: point(0, 1)); ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()

    let volets: [(CGFloat, CGFloat, UInt32)] = [(0, 1.0 / 3, 0xF7EFD6), (1.0 / 3, 2.0 / 3, 0xCDE8BE), (2.0 / 3, 1, 0xBEE0F6)]
    for (a, b, c) in volets {
        ctx.setFillColor(couleur(c).cgColor)
        ctx.move(to: point(a, 0)); ctx.addLine(to: point(b, 0)); ctx.addLine(to: point(b, 1)); ctx.addLine(to: point(a, 1)); ctx.closePath()
        ctx.fillPath()
    }
    // Reflet et ombre aux plis.
    for (i, t) in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)].enumerated() {
        ctx.setStrokeColor(couleur(i == 0 ? 0x000000 : 0xFFFFFF, i == 0 ? 0.10 : 0.35).cgColor)
        ctx.setLineWidth(5)
        ctx.move(to: point(t, 0)); ctx.addLine(to: point(t, 1)); ctx.strokePath()
    }

    // Rivière, routes et parcs.
    ctx.setStrokeColor(couleur(0x8CC8F2).cgColor); ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: point(0.40, 0.0)); ctx.addCurve(to: point(0.62, 1.0), control1: point(0.30, 0.45), control2: point(0.78, 0.55)); ctx.strokePath()
    ctx.setStrokeColor(couleur(0xFFFFFF, 0.95).cgColor); ctx.setLineWidth(20)
    ctx.move(to: point(0.0, 0.25)); ctx.addLine(to: point(1.0, 0.42)); ctx.strokePath()
    ctx.move(to: point(0.18, 0.0)); ctx.addLine(to: point(0.30, 1.0)); ctx.strokePath()
    ctx.move(to: point(0.80, 0.0)); ctx.addLine(to: point(0.70, 1.0)); ctx.strokePath()
    ctx.setFillColor(couleur(0xA8D79A).cgColor)
    for (t, h, r) in [(0.10, 0.70, 46), (0.88, 0.22, 40)] as [(CGFloat, CGFloat, CGFloat)] {
        let p = point(t, h); ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.55, width: r * 2, height: r * 1.1))
    }

    // Parcours en pointillés, de la carte jusqu'à l'avion, et repère de départ.
    let depart = point(0.30, 0.20), arrivee = CGPoint(x: 640, y: 700)
    ctx.saveGState()
    ctx.setStrokeColor(couleur(0xFF5A36).cgColor); ctx.setLineWidth(15); ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 30])
    ctx.move(to: depart)
    ctx.addCurve(to: arrivee, control1: CGPoint(x: 350, y: 520), control2: CGPoint(x: 520, y: 420))
    ctx.strokePath()
    ctx.restoreGState()
    ctx.setFillColor(couleur(0xFF5A36).cgColor); ctx.fillEllipse(in: CGRect(x: depart.x - 34, y: depart.y - 34, width: 68, height: 68))
    ctx.setFillColor(couleur(0xFFFFFF).cgColor); ctx.fillEllipse(in: CGRect(x: depart.x - 14, y: depart.y - 14, width: 28, height: 28))

    // Ombre portée de l'avion sur la carte.
    ctx.setFillColor(couleur(0x04225E, 0.20).cgColor)
    ctx.fillEllipse(in: CGRect(x: 600, y: 360, width: 250, height: 52))

    // Avion (symbole SF), blanc, incliné vers le haut à droite.
    let reglage = NSImage.SymbolConfiguration(pointSize: 420, weight: .bold)
    guard let symbole = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?.withSymbolConfiguration(reglage) else { return }
    let teinte = NSImage(size: symbole.size, flipped: false) { rect in
        symbole.draw(in: rect)
        couleur(0xFFFFFF).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let l = teinte.size.width, h = teinte.size.height
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 10, height: -22), blur: 30, color: couleur(0x04225E, 0.45).cgColor)
    ctx.translateBy(x: 640, y: 690)
    ctx.rotate(by: 28 * .pi / 180)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    teinte.draw(in: CGRect(x: -l / 2, y: -h / 2, width: l, height: h))
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

func image(taille: Int, pourMac: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: taille, pixelsHigh: taille, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let contexte = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = contexte
    let ctx = contexte.cgContext
    ctx.scaleBy(x: CGFloat(taille) / 1024, y: CGFloat(taille) / 1024)
    if pourMac {
        // macOS : carré arrondi de 824 px centré, avec marge transparente et ombre légère.
        let cadre = CGRect(x: 100, y: 100, width: 824, height: 824)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(CGPath(roundedRect: cadre, cornerWidth: 185, cornerHeight: 185, transform: nil))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: cadre, cornerWidth: 185, cornerHeight: 185, transform: nil)); ctx.clip()
        ctx.translateBy(x: 100, y: 100); ctx.scaleBy(x: 824.0 / 1024, y: 824.0 / 1024)
    }
    dessiner(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sortie = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try? FileManager.default.createDirectory(at: sortie, withIntermediateDirectories: true)
try image(taille: 1024, pourMac: false).write(to: sortie.appendingPathComponent("icone-ios-1024.png"))
for taille in [16, 32, 64, 128, 256, 512, 1024] {
    try image(taille: taille, pourMac: true).write(to: sortie.appendingPathComponent("icone-mac-\(taille).png"))
}
print("Icônes écrites dans \(sortie.path)")
