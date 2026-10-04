import SwiftUI

/// Dispose des éléments de gauche à droite en passant à la ligne quand il n'y a plus de place.
struct FlowLayout: Layout {
    var espacement: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, hauteurLigne: CGFloat = 0, maxX: CGFloat = 0
        for sous in subviews {
            let taille = sous.sizeThatFits(.unspecified)
            if x > 0, x + taille.width > largeur { x = 0; y += hauteurLigne + espacement; hauteurLigne = 0 }
            x += taille.width + espacement
            hauteurLigne = max(hauteurLigne, taille.height)
            maxX = max(maxX, x - espacement)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + hauteurLigne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, hauteurLigne: CGFloat = 0
        for sous in subviews {
            let taille = sous.sizeThatFits(.unspecified)
            if x > 0, x + taille.width > bounds.width { x = 0; y += hauteurLigne + espacement; hauteurLigne = 0 }
            sous.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += taille.width + espacement
            hauteurLigne = max(hauteurLigne, taille.height)
        }
    }
}
