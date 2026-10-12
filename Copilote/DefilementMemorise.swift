import SwiftUI

/// Retient où l'on s'est arrêté de faire défiler une vue (l'Itinéraire, le Timing…) pour y revenir exactement au retour.
/// Les positions sont notées pendant le défilement, et gardées d'un lancement à l'autre quand on quitte la vue.
@MainActor enum PositionsDefilement {
    private static var valeurs: [String: CGFloat] = [:]

    static func lire(_ cle: String) -> CGFloat? {
        if let v = valeurs[cle] { return v }
        return (UserDefaults.standard.object(forKey: "defilement-\(cle)") as? Double).map { CGFloat($0) }
    }

    /// Notée en mémoire à chaque mouvement, et dans les réglages dès que le défilement s'arrête un instant
    /// (quitter l'app ne prévient pas la vue : la position doit déjà être enregistrée).
    static func noter(_ position: CGFloat, _ cle: String) {
        valeurs[cle] = max(position, 0)
        attentes[cle]?.cancel()
        let attente = DispatchWorkItem { enregistrer(cle) }
        attentes[cle] = attente
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: attente)
    }
    private static var attentes: [String: DispatchWorkItem] = [:]

    static func enregistrer(_ cle: String) {
        guard let v = valeurs[cle] else { return }
        UserDefaults.standard.set(Double(v), forKey: "defilement-\(cle)")
    }
}

/// Un défilement vertical qui revient là où on l'avait laissé.
/// La position de retour est figée à l'ouverture : l'affichage provisoire en haut de liste (avant le retour) ne l'écrase pas.
/// Le retour se fait sur la vue de défilement du système (UIScrollView, NSScrollView) : SwiftUI ne sait pas viser une position exacte.
struct DefilementMemorise<Contenu: View>: View {
    let cle: String
    /// Appelé quand aucune position n'est retenue (première ouverture), pour choisir où commencer.
    var siAucune: ((ScrollViewProxy) -> Void)?
    @ViewBuilder var contenu: () -> Contenu
    @State private var depart: CGFloat?
    /// Faux tant que le retour à la position retenue n'est pas terminé : rien n'est noté entre-temps.
    @State private var pret = false
    @State private var acces = AccesDefilement()

    init(cle: String, siAucune: ((ScrollViewProxy) -> Void)? = nil, @ViewBuilder contenu: @escaping () -> Contenu) {
        self.cle = cle
        self.siAucune = siAucune
        self.contenu = contenu
        _depart = State(initialValue: PositionsDefilement.lire(cle))
    }

    var body: some View {
        ScrollViewReader { lecteur in
            ScrollView {
                contenu()
                    .background(TrouveurDefilement(acces: acces))
                    .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .scrollView).minY } action: { y in
                        if pret { PositionsDefilement.noter(y, cle) }
                    }
            }
            .onAppear {
                guard let depart else {
                    siAucune?(lecteur)
                    pret = true
                    return
                }
                // Plusieurs passages : la vue du système n'est prête qu'après le premier affichage,
                // et les listes paresseuses ne connaissent leur hauteur qu'une fois les éléments affichés.
                for delai in [0.0, 0.1, 0.3] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delai) { acces.aller(a: depart) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pret = true }
            }
            .onDisappear { PositionsDefilement.enregistrer(cle) }
        }
    }
}

/// La vue de défilement du système qui porte un `ScrollView`, pour y régler la position au point près.
@MainActor final class AccesDefilement {
    #if os(iOS)
    weak var vue: UIScrollView?

    func aller(a y: CGFloat) {
        guard let vue else { return }
        let maxi = max(vue.contentSize.height + vue.adjustedContentInset.bottom - vue.bounds.height, -vue.adjustedContentInset.top)
        vue.setContentOffset(CGPoint(x: vue.contentOffset.x, y: min(y - vue.adjustedContentInset.top, maxi)), animated: false)
    }
    #else
    weak var vue: NSScrollView?

    func aller(a y: CGFloat) {
        guard let vue, let document = vue.documentView else { return }
        let maxi = max(document.frame.height - vue.contentView.bounds.height, 0)
        let cible = document.isFlipped ? min(y, maxi) : maxi - min(y, maxi)
        vue.contentView.scroll(to: NSPoint(x: vue.contentView.bounds.origin.x, y: cible))
        vue.reflectScrolledClipView(vue.contentView)
    }
    #endif
}

/// Une vue invisible posée dans le contenu, qui retrouve la vue de défilement du système autour d'elle.
private struct TrouveurDefilement {
    let acces: AccesDefilement
}

#if os(iOS)
extension TrouveurDefilement: UIViewRepresentable {
    final class Sonde: UIView {
        var trouve: ((UIScrollView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let courant = v, !(courant is UIScrollView) { v = courant.superview }
            if let defilement = v as? UIScrollView { trouve?(defilement) }
        }
    }

    func makeUIView(context: Context) -> Sonde {
        let sonde = Sonde()
        sonde.isUserInteractionEnabled = false
        sonde.trouve = { [acces] in acces.vue = $0 }
        return sonde
    }

    func updateUIView(_ vue: Sonde, context: Context) {}
}
#else
extension TrouveurDefilement: NSViewRepresentable {
    final class Sonde: NSView {
        var trouve: ((NSScrollView) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let defilement = enclosingScrollView { trouve?(defilement) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Sonde {
        let sonde = Sonde()
        sonde.trouve = { [acces] in acces.vue = $0 }
        return sonde
    }

    func updateNSView(_ vue: Sonde, context: Context) {}
}
#endif
