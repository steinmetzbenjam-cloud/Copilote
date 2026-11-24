import SwiftUI

/// Retient où l'on s'est arrêté de faire défiler une vue (l'Itinéraire, le Timing…) pour y revenir exactement au retour,
/// y compris après être passé par une autre app (iOS peut alors fermer l'app : la position est déjà dans les réglages).
/// Deux mesures sont gardées : la position en points, et le repère (un jour, par exemple) en haut de l'écran avec sa place exacte.
/// Le repère compte dans les listes paresseuses : la hauteur des éléments jamais affichés n'y est qu'estimée, si bien qu'une
/// position en points ne retombe pas sur le même jour ; le repère, lui, se retrouve toujours.
@MainActor enum PositionsDefilement {
    /// Le repère en haut de l'écran, et la position de son haut par rapport au haut de la zone visible.
    struct Repere: Equatable { let id: String; let haut: CGFloat }

    private static var valeurs: [String: CGFloat] = [:]
    private static var reperes: [String: Repere] = [:]

    static func lire(_ cle: String) -> CGFloat? {
        if let v = valeurs[cle] { return v }
        return (UserDefaults.standard.object(forKey: "defilement-\(cle)") as? Double).map { CGFloat($0) }
    }

    static func repere(_ cle: String) -> Repere? {
        if let r = reperes[cle] { return r }
        guard let id = UserDefaults.standard.string(forKey: "defilement-repere-\(cle)"),
              let haut = UserDefaults.standard.object(forKey: "defilement-repere-haut-\(cle)") as? Double else { return nil }
        return Repere(id: id, haut: CGFloat(haut))
    }

    /// Notée en mémoire à chaque mouvement, et dans les réglages dès que le défilement s'arrête un instant
    /// (quitter l'app ne prévient pas la vue : la position doit déjà être enregistrée).
    /// Le repère du haut est relevé au moment d'enregistrer, une fois les repères mesurés à leur place définitive.
    static func noter(_ position: CGFloat, reperes affiches: ReperesDefilement, _ cle: String) {
        valeurs[cle] = max(position, 0)
        sources[cle] = affiches
        attentes[cle]?.cancel()
        let attente = DispatchWorkItem { enregistrer(cle) }
        attentes[cle] = attente
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: attente)
    }
    private static var attentes: [String: DispatchWorkItem] = [:]
    private static var sources: [String: ReperesDefilement] = [:]

    static func enregistrer(_ cle: String) {
        guard let v = valeurs[cle] else { return }
        // En quittant la vue, les repères peuvent déjà être retirés : on garde alors le dernier relevé.
        if let r = sources[cle]?.enHaut { reperes[cle] = r }
        let reglages = UserDefaults.standard
        reglages.set(Double(v), forKey: "defilement-\(cle)")
        if let r = reperes[cle] {
            reglages.set(r.id, forKey: "defilement-repere-\(cle)")
            reglages.set(Double(r.haut), forKey: "defilement-repere-haut-\(cle)")
        } else {
            reglages.removeObject(forKey: "defilement-repere-\(cle)")
            reglages.removeObject(forKey: "defilement-repere-haut-\(cle)")
        }
    }
}

/// Les repères affichés d'un défilement (voir `repereDefilement`) et la place de leur haut dans la zone visible.
/// Pas observé : les positions changent à chaque mouvement, sans rien redessiner.
@MainActor final class ReperesDefilement {
    var hauts: [String: CGFloat] = [:]

    /// Le repère du haut de l'écran : le dernier dont le haut est passé au-dessus du bord, sinon le premier affiché.
    var enHaut: PositionsDefilement.Repere? {
        let passes = hauts.filter { $0.value <= 0.5 }
        let choisi = passes.max { $0.value < $1.value } ?? hauts.min { $0.value < $1.value }
        return choisi.map { PositionsDefilement.Repere(id: $0.key, haut: $0.value) }
    }
}

private struct CleReperesDefilement: EnvironmentKey {
    static let defaultValue: ReperesDefilement? = nil
}

extension EnvironmentValues {
    fileprivate var reperesDefilement: ReperesDefilement? {
        get { self[CleReperesDefilement.self] }
        set { self[CleReperesDefilement.self] = newValue }
    }
}

/// Fait d'une vue un repère de `DefilementMemorise` : on y revient par son identifiant, puis au point près.
private struct RepereDefilement: ViewModifier {
    let id: String
    @Environment(\.reperesDefilement) private var reperes

    func body(content: Content) -> some View {
        content
            .id(id)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { reperes?.hauts[id] = $0 }
            .onDisappear { reperes?.hauts[id] = nil }
    }
}

extension View {
    /// Repère pour retrouver la position d'un `DefilementMemorise` (un jour de la liste, par exemple). L'identifiant doit rester le même
    /// d'un lancement à l'autre ; il sert aussi d'`id` à la vue. Dans une liste paresseuse, c'est aussi l'identifiant de l'élément
    /// du `ForEach` qui porte la vue : `scrollTo` ne trouve que lui tant que l'élément n'a jamais été affiché.
    func repereDefilement(_ id: String) -> some View { modifier(RepereDefilement(id: id)) }
}

extension Date {
    /// L'identifiant d'un jour comme repère de défilement (voir `repereDefilement`), le même d'un lancement à l'autre.
    var repereDefilement: String { "jour-\(Int(timeIntervalSinceReferenceDate.rounded()))" }
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
    @State private var repereDepart: PositionsDefilement.Repere?
    /// Faux tant que le retour à la position retenue n'est pas terminé : rien n'est noté entre-temps.
    @State private var pret = false
    @State private var acces = AccesDefilement()
    @State private var reperes = ReperesDefilement()

    init(cle: String, siAucune: ((ScrollViewProxy) -> Void)? = nil, @ViewBuilder contenu: @escaping () -> Contenu) {
        self.cle = cle
        self.siAucune = siAucune
        self.contenu = contenu
        _depart = State(initialValue: PositionsDefilement.lire(cle))
        _repereDepart = State(initialValue: PositionsDefilement.repere(cle))
    }

    var body: some View {
        ScrollViewReader { lecteur in
            ScrollView {
                contenu()
                    .environment(\.reperesDefilement, reperes)
                    .background(TrouveurDefilement(acces: acces))
                    .onGeometryChange(for: CGFloat.self) { -$0.frame(in: .scrollView).minY } action: { y in
                        if pret { PositionsDefilement.noter(y, reperes: reperes, cle) }
                    }
            }
            .onAppear {
                guard depart != nil || repereDepart != nil else {
                    siAucune?(lecteur)
                    pret = true
                    return
                }
                // Plusieurs passages : la vue du système n'est prête qu'après le premier affichage, et les listes paresseuses
                // ne connaissent la hauteur de leurs éléments qu'une fois affichés. On s'arrête si l'on fait défiler entre-temps.
                let passages = [0.0, 0.1, 0.25, 0.45, 0.7]
                for delai in passages {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delai) {
                        guard !pret, !acces.enMain else { return }
                        revenir(lecteur)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (passages.last ?? 0) + 0.1) { pret = true }
            }
            .onDisappear { PositionsDefilement.enregistrer(cle) }
        }
    }

    /// Vers le repère retenu : par son identifiant tant qu'il n'est pas affiché (pour une liste paresseuse, l'identifiant doit être
    /// celui de l'élément du `ForEach`), puis au point près ; sans repère, à la position en points.
    private func revenir(_ lecteur: ScrollViewProxy) {
        guard let repere = repereDepart else {
            if let depart { acces.aller(a: depart) }
            return
        }
        if let haut = reperes.hauts[repere.id] {
            let ecart = haut - repere.haut
            if abs(ecart) > 0.5 { acces.decaler(de: ecart) }
        } else {
            lecteur.scrollTo(repere.id, anchor: .top)
        }
    }
}

/// La vue de défilement du système qui porte un `ScrollView`, pour y régler la position au point près.
@MainActor final class AccesDefilement {
    #if os(iOS)
    weak var vue: UIScrollView?

    /// Le doigt est sur la liste : on ne la déplace plus.
    var enMain: Bool { vue.map { $0.isTracking || $0.isDragging || $0.isDecelerating } ?? false }

    private var maxi: CGFloat {
        guard let vue else { return 0 }
        return max(vue.contentSize.height + vue.adjustedContentInset.bottom - vue.bounds.height, -vue.adjustedContentInset.top)
    }

    func aller(a y: CGFloat) {
        guard let vue else { return }
        vue.setContentOffset(CGPoint(x: vue.contentOffset.x, y: min(y - vue.adjustedContentInset.top, maxi)), animated: false)
    }

    /// Fait défiler de `ecart` points vers le bas (vers le haut s'il est négatif).
    func decaler(de ecart: CGFloat) {
        guard let vue else { return }
        let y = min(max(vue.contentOffset.y + ecart, -vue.adjustedContentInset.top), maxi)
        vue.setContentOffset(CGPoint(x: vue.contentOffset.x, y: y), animated: false)
    }
    #else
    weak var vue: NSScrollView?

    var enMain: Bool { false }

    func aller(a y: CGFloat) {
        guard let vue, let document = vue.documentView else { return }
        let maxi = max(document.frame.height - vue.contentView.bounds.height, 0)
        let cible = document.isFlipped ? min(y, maxi) : maxi - min(y, maxi)
        vue.contentView.scroll(to: NSPoint(x: vue.contentView.bounds.origin.x, y: cible))
        vue.reflectScrolledClipView(vue.contentView)
    }

    /// Fait défiler de `ecart` points vers le bas (vers le haut s'il est négatif).
    func decaler(de ecart: CGFloat) {
        guard let vue, let document = vue.documentView else { return }
        let maxi = max(document.frame.height - vue.contentView.bounds.height, 0)
        let origine = vue.contentView.bounds.origin.y
        let actuelle = document.isFlipped ? origine : maxi - origine
        aller(a: min(max(actuelle + ecart, 0), maxi))
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
