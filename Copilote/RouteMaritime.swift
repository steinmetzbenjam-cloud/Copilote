import Foundation
import MapKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Route en bateau entre deux lieux : elle passe par la mer et suit les côtes au lieu de couper à travers les terres.
/// On fait dessiner par Plans la carte de la zone, on y reconnaît la mer à sa couleur bleue, puis on cherche
/// le plus court chemin sur l'eau, en gardant un peu de distance avec le rivage.
enum RouteMaritime {
    /// Vitesse moyenne retenue pour la durée (celle d'un ferry, environ 16 nœuds) ; la durée se corrige à la main.
    static let vitesse = 30_000.0 / 3600
    /// Côté de la grille sur laquelle on cherche le chemin.
    private static let cote = 480

    static func trajet(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) async -> Trajet? {
        // Si le chemin ne tient pas dans la zone dessinée (une presqu'île à contourner), on l'élargit.
        for marge in [0.4, 1.2, 3.0] {
            guard let carte = await carteDesEaux(a, b, marge: marge) else { return nil }
            if let points = await Task.detached(priority: .userInitiated, operation: { carte.chemin(a, b) }).value {
                var distance = 0.0
                for (p, q) in zip(points, points.dropFirst()) {
                    distance += CLLocation(latitude: p.latitude, longitude: p.longitude).distance(from: CLLocation(latitude: q.latitude, longitude: q.longitude))
                }
                return Trajet(points: points, distance: distance, duree: distance / vitesse)
            }
        }
        return nil
    }

    /// Dessine la zone qui entoure les deux lieux (un carré, avec une marge autour) et repère les pixels de mer.
    private static func carteDesEaux(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, marge: Double) async -> CarteDesEaux? {
        let pa = MKMapPoint(a), pb = MKMapPoint(b)
        let minimum = 4_000 * MKMapPointsPerMeterAtLatitude((a.latitude + b.latitude) / 2)
        let base = max(abs(pa.x - pb.x), abs(pa.y - pb.y), minimum)
        let largeur = min(base * (1 + 2 * marge), MKMapSize.world.width)
        let zone = MKMapRect(x: (pa.x + pb.x - largeur) / 2, y: (pa.y + pb.y - largeur) / 2, width: largeur, height: largeur)

        let options = MKMapSnapshotter.Options()
        options.mapRect = zone
        options.size = CGSize(width: cote, height: cote)
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        options.pointOfInterestFilter = .excludingAll
        // Toujours en clair : les couleurs de la mer et de la terre sont celles qu'on reconnaît.
        #if os(iOS)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        #else
        options.appearance = NSAppearance(named: .aqua)
        #endif
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        #if os(iOS)
        let cg = image.cgImage
        #else
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let cg else { return nil }

        var pixels = [UInt8](repeating: 0, count: cote * cote * 4)
        let dessine = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let contexte = CGContext(data: tampon.baseAddress, width: cote, height: cote, bitsPerComponent: 8, bytesPerRow: cote * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            contexte.draw(cg, in: CGRect(x: 0, y: 0, width: cote, height: cote))
            return true
        }
        guard dessine else { return nil }
        // La mer de Plans est d'un bleu franc (peu de rouge) ; la terre, même les quartiers clairs un peu bleutés, a bien plus de rouge.
        var eau = [Bool](repeating: false, count: cote * cote)
        for i in eau.indices {
            let r = Int(pixels[i * 4]), bleu = Int(pixels[i * 4 + 2])
            eau[i] = bleu > 180 && bleu - r > 80
        }
        return CarteDesEaux(zone: zone, cote: cote, eau: eau)
    }
}

/// La zone dessinée, découpée en cases : de l'eau ou de la terre.
private struct CarteDesEaux: Sendable {
    let zone: MKMapRect
    let cote: Int
    let eau: [Bool]

    private func caseDe(_ c: CLLocationCoordinate2D) -> (Int, Int) {
        let p = MKMapPoint(c)
        let x = Int((p.x - zone.minX) / zone.width * Double(cote)), y = Int((p.y - zone.minY) / zone.height * Double(cote))
        return (min(max(x, 0), cote - 1), min(max(y, 0), cote - 1))
    }

    private func coordonnee(_ i: Int) -> CLLocationCoordinate2D {
        MKMapPoint(x: zone.minX + (Double(i % cote) + 0.5) / Double(cote) * zone.width,
                   y: zone.minY + (Double(i / cote) + 0.5) / Double(cote) * zone.height).coordinate
    }

    /// Le chemin sur l'eau, du lieu de départ au lieu d'arrivée (les ports sont souvent sur la terre de la carte : on rejoint l'eau la plus proche).
    func chemin(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D]? {
        let rivage = distancesAuRivage()
        let rayon = max(cote / 8, 12)
        guard let depart = eauLaPlusProche(caseDe(a), rayon: rayon), let arrivee = eauLaPlusProche(caseDe(b), rayon: rayon),
              let cases = aEtoile(depart, arrivee, rivage: rivage) else { return nil }
        return [a] + lisser(cases).map(coordonnee) + [b]
    }

    /// Pour chaque case d'eau, le nombre de cases qui la séparent de la terre (0 sur la terre).
    private func distancesAuRivage() -> [Int] {
        var d = [Int](repeating: Int.max, count: eau.count)
        var file: [Int] = []
        file.reserveCapacity(eau.count)
        for i in eau.indices where !eau[i] { d[i] = 0; file.append(i) }
        var tete = 0
        while tete < file.count {
            let i = file[tete]; tete += 1
            let x = i % cote, y = i / cote
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < cote, ny < cote else { continue }
                let j = ny * cote + nx
                if d[j] > d[i] + 1 { d[j] = d[i] + 1; file.append(j) }
            }
        }
        return d
    }

    private func eauLaPlusProche(_ c: (Int, Int), rayon: Int) -> Int? {
        var meilleure: Int?, meilleureDistance = Int.max
        for dy in -rayon...rayon {
            for dx in -rayon...rayon {
                let x = c.0 + dx, y = c.1 + dy
                guard x >= 0, y >= 0, x < cote, y < cote, eau[y * cote + x] else { continue }
                let d = dx * dx + dy * dy
                if d < meilleureDistance { meilleureDistance = d; meilleure = y * cote + x }
            }
        }
        return meilleure
    }

    /// Plus court chemin sur l'eau ; longer le rivage de trop près (ou remonter une rivière) coûte plus cher.
    private func aEtoile(_ depart: Int, _ arrivee: Int, rivage: [Int]) -> [Int]? {
        let ax = arrivee % cote, ay = arrivee / cote
        func estimation(_ i: Int) -> Double {
            let dx = Double(i % cote - ax), dy = Double(i / cote - ay)
            return (dx * dx + dy * dy).squareRoot()
        }
        var cout = [Double](repeating: .infinity, count: eau.count)
        var venuDe = [Int](repeating: -1, count: eau.count)
        var fermee = [Bool](repeating: false, count: eau.count)
        var tas = Tas()
        cout[depart] = 0
        tas.ajouter(depart, priorite: estimation(depart))
        let voisins = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
                       (1, 1, 2.0.squareRoot()), (1, -1, 2.0.squareRoot()), (-1, 1, 2.0.squareRoot()), (-1, -1, 2.0.squareRoot())]
        while let i = tas.retirer() {
            if i == arrivee { break }
            if fermee[i] { continue }
            fermee[i] = true
            let x = i % cote, y = i / cote
            for (dx, dy, pas) in voisins {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < cote, ny < cote else { continue }
                let j = ny * cote + nx
                guard eau[j], !fermee[j] else { continue }
                let penalite: Double = switch rivage[j] {
                case ...1: 6
                case 2: 3
                case 3: 1.5
                default: 1
                }
                let nouveau = cout[i] + pas * penalite
                if nouveau < cout[j] {
                    cout[j] = nouveau
                    venuDe[j] = i
                    tas.ajouter(j, priorite: nouveau + estimation(j))
                }
            }
        }
        guard depart == arrivee || venuDe[arrivee] >= 0 else { return nil }
        var cases = [arrivee]
        while let derniere = cases.last, derniere != depart { cases.append(venuDe[derniere]) }
        return cases.reversed()
    }

    /// Retire les zigzags de la grille : on file tout droit tant que la ligne reste sur l'eau, à l'écart de la terre.
    private func lisser(_ cases: [Int]) -> [Int] {
        guard cases.count > 2 else { return cases }
        var resultat = [cases[0]]
        var i = 0
        while i < cases.count - 1 {
            var j = cases.count - 1
            while j > i + 1, !ligneSurLEau(cases[i], cases[j]) { j -= 1 }
            resultat.append(cases[j])
            i = j
        }
        return resultat
    }

    private func ligneSurLEau(_ a: Int, _ b: Int) -> Bool {
        let x0 = a % cote, y0 = a / cote, x1 = b % cote, y1 = b / cote
        let n = max(abs(x1 - x0), abs(y1 - y0))
        guard n > 0 else { return true }
        for k in 0...n {
            let t = Double(k) / Double(n)
            let x = Int((Double(x0) + t * Double(x1 - x0)).rounded()), y = Int((Double(y0) + t * Double(y1 - y0)).rounded())
            if !eau[y * cote + x] { return false }
        }
        return true
    }
}

/// File de priorité (tas binaire) pour la recherche du chemin.
private struct Tas {
    private var elements: [(Int, Double)] = []

    mutating func ajouter(_ valeur: Int, priorite: Double) {
        elements.append((valeur, priorite))
        var i = elements.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard elements[i].1 < elements[parent].1 else { break }
            elements.swapAt(i, parent)
            i = parent
        }
    }

    mutating func retirer() -> Int? {
        guard !elements.isEmpty else { return nil }
        let premier = elements[0].0
        let dernier = elements.removeLast()
        if !elements.isEmpty {
            elements[0] = dernier
            var i = 0
            while true {
                let g = 2 * i + 1, d = g + 1
                var plusPetit = i
                if g < elements.count, elements[g].1 < elements[plusPetit].1 { plusPetit = g }
                if d < elements.count, elements[d].1 < elements[plusPetit].1 { plusPetit = d }
                if plusPetit == i { break }
                elements.swapAt(i, plusPetit)
                i = plusPetit
            }
        }
        return premier
    }
}
