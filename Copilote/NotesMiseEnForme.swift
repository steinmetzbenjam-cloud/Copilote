import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
typealias PoliceSysteme = UIFont
typealias CouleurSysteme = UIColor
typealias ImageSysteme = UIImage
typealias VueTexteSysteme = UITextView
#else
import AppKit
typealias PoliceSysteme = NSFont
typealias CouleurSysteme = NSColor
typealias ImageSysteme = NSImage
typealias VueTexteSysteme = NSTextView
#endif

// MARK: Format enregistré

/// Des notes mises en forme : une suite de morceaux de texte, chacun avec son style. Une image est un morceau à elle seule.
/// Le format est le même sur iPhone, iPad et Mac (pas de police ni de couleur propres à un système).
struct NoteMiseEnForme: Codable {
    var version = 1
    var morceaux: [Morceau] = []

    struct Morceau: Codable {
        var texte: String
        var style: String?
        var gras: Bool?
        var italique: Bool?
        var souligne: Bool?
        /// Rouge, vert, bleu entre 0 et 1.
        var couleur: [Double]?
        var lien: String?
        var alignement: String?
        var image: Data?
        var largeur: Double?
        var hauteur: Double?
    }
}

enum StyleNote: String, CaseIterable, Identifiable {
    case titre, sousTitre, corps
    var id: String { rawValue }
    var libelle: String {
        switch self {
        case .titre: "Titre"
        case .sousTitre: "Sous-titre"
        case .corps: "Texte"
        }
    }
}

enum AlignementNote: String, CaseIterable, Identifiable {
    case gauche, centre, droite
    var id: String { rawValue }
    var symbole: String {
        switch self {
        case .gauche: "text.alignleft"
        case .centre: "text.aligncenter"
        case .droite: "text.alignright"
        }
    }
    var systeme: NSTextAlignment {
        switch self {
        case .gauche: .left
        case .centre: .center
        case .droite: .right
        }
    }
    init(_ a: NSTextAlignment) {
        switch a {
        case .center: self = .centre
        case .right: self = .droite
        default: self = .gauche
        }
    }
}

extension NSAttributedString.Key {
    static let styleNote = NSAttributedString.Key("copiloteStyle")
    static let grasNote = NSAttributedString.Key("copiloteGras")
    static let italiqueNote = NSAttributedString.Key("copiloteItalique")
    static let couleurNote = NSAttributedString.Key("copiloteCouleur")
    static let imageNote = NSAttributedString.Key("copiloteImage")
}

/// Passage du format enregistré au texte affiché, et retour.
enum MiseEnForme {
    #if os(iOS)
    static let tailleCorps: CGFloat = 17
    static var couleurParDefaut: CouleurSysteme { .label }
    #else
    static let tailleCorps: CGFloat = 14
    static var couleurParDefaut: CouleurSysteme { .labelColor }
    #endif

    static func police(_ style: StyleNote, gras: Bool, italique: Bool) -> PoliceSysteme {
        let taille: CGFloat, poids: PoliceSysteme.Weight
        switch style {
        case .titre: (taille, poids) = (tailleCorps * 1.5, .bold)
        case .sousTitre: (taille, poids) = (tailleCorps * 1.2, .semibold)
        case .corps: (taille, poids) = (tailleCorps, gras ? .bold : .regular)
        }
        let police = PoliceSysteme.systemFont(ofSize: taille, weight: poids)
        guard italique else { return police }
        #if os(iOS)
        return police.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: taille) } ?? police
        #else
        return NSFont(descriptor: police.fontDescriptor.withSymbolicTraits(.italic), size: taille) ?? police
        #endif
    }

    static func couleur(_ rvb: [Double]?) -> CouleurSysteme {
        guard let rvb, rvb.count >= 3 else { return couleurParDefaut }
        return CouleurSysteme(red: rvb[0], green: rvb[1], blue: rvb[2], alpha: 1)
    }

    /// Les attributs d'un texte simple, sans mise en forme.
    static var attributsDeBase: [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.styleNote: StyleNote.corps.rawValue]
        recalculer(&a)
        return a
    }

    /// Police, couleur et paragraphe déduits des attributs propres aux notes.
    static func recalculer(_ a: inout [NSAttributedString.Key: Any]) {
        let style = StyleNote(rawValue: a[.styleNote] as? String ?? "") ?? .corps
        a[.font] = police(style, gras: a[.grasNote] as? Bool ?? false, italique: a[.italiqueNote] as? Bool ?? false)
        a[.foregroundColor] = couleur(a[.couleurNote] as? [Double])
        let paragraphe = ((a[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraphe.paragraphSpacingBefore = style == .corps ? 0 : tailleCorps * 0.5
        paragraphe.paragraphSpacing = style == .corps ? 2 : 4
        a[.paragraphStyle] = paragraphe
    }

    static func texte(depuis donnees: Data?, texteSimple: String, largeur: CGFloat) -> NSAttributedString {
        guard let donnees, let note = try? JSONDecoder().decode(NoteMiseEnForme.self, from: donnees) else {
            return NSAttributedString(string: texteSimple, attributes: attributsDeBase)
        }
        let resultat = NSMutableAttributedString()
        for m in note.morceaux {
            var a: [NSAttributedString.Key: Any] = [.styleNote: m.style ?? StyleNote.corps.rawValue]
            if m.gras == true { a[.grasNote] = true }
            if m.italique == true { a[.italiqueNote] = true }
            if m.souligne == true { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let c = m.couleur { a[.couleurNote] = c }
            if let lien = m.lien, let url = URL(string: lien) { a[.link] = url }
            let paragraphe = NSMutableParagraphStyle()
            paragraphe.alignment = AlignementNote(rawValue: m.alignement ?? "")?.systeme ?? .natural
            a[.paragraphStyle] = paragraphe
            recalculer(&a)
            if let donneesImage = m.image, let image = ImageSysteme(data: donneesImage) {
                let piece = piece(image, taille: CGSize(width: m.largeur ?? 0, height: m.hauteur ?? 0), largeur: largeur)
                let morceau = NSMutableAttributedString(attachment: piece)
                a[.imageNote] = donneesImage
                morceau.addAttributes(a, range: NSRange(location: 0, length: morceau.length))
                resultat.append(morceau)
            } else {
                resultat.append(NSAttributedString(string: m.texte, attributes: a))
            }
        }
        return resultat
    }

    static func donnees(depuis texte: NSAttributedString) -> Data? {
        var note = NoteMiseEnForme()
        let chaine = texte.string as NSString
        texte.enumerateAttributes(in: NSRange(location: 0, length: texte.length)) { a, r, _ in
            var m = NoteMiseEnForme.Morceau(texte: chaine.substring(with: r))
            if let style = a[.styleNote] as? String, style != StyleNote.corps.rawValue { m.style = style }
            if a[.grasNote] as? Bool == true { m.gras = true }
            if a[.italiqueNote] as? Bool == true { m.italique = true }
            if (a[.underlineStyle] as? Int ?? 0) != 0 { m.souligne = true }
            m.couleur = a[.couleurNote] as? [Double]
            if let url = a[.link] as? URL { m.lien = url.absoluteString } else if let lien = a[.link] as? String { m.lien = lien }
            if let p = a[.paragraphStyle] as? NSParagraphStyle, AlignementNote(p.alignment) != .gauche { m.alignement = AlignementNote(p.alignment).rawValue }
            if let piece = a[.attachment] as? NSTextAttachment {
                m.image = a[.imageNote] as? Data ?? piece.image.flatMap(jpeg)
                m.largeur = piece.bounds.width
                m.hauteur = piece.bounds.height
                m.texte = "\u{FFFC}"
            }
            note.morceaux.append(m)
        }
        return try? JSONEncoder().encode(note)
    }

    /// Une image insérée dans le texte, à sa taille d'origine mais jamais plus large que la zone de texte.
    static func piece(_ image: ImageSysteme, taille: CGSize, largeur: CGFloat) -> NSTextAttachment {
        let piece = NSTextAttachment()
        piece.image = image
        var t = taille.width > 0 && taille.height > 0 ? taille : image.size
        let maxi = max(largeur - 12, 60)
        if t.width > maxi { t = CGSize(width: maxi, height: t.height * maxi / t.width) }
        piece.bounds = CGRect(origin: .zero, size: t)
        return piece
    }

    /// Une photo réduite (1 200 points au plus) et compressée, pour ne pas alourdir les notes.
    static func reduire(_ donnees: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return sortie as Data
    }

    static func jpeg(_ image: ImageSysteme) -> Data? {
        #if os(iOS)
        return image.jpegData(compressionQuality: 0.75)
        #else
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        #endif
    }

    static func composantes(_ couleur: Color) -> [Double] {
        #if os(iOS)
        var r: CGFloat = 0, v: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(couleur).getRed(&r, green: &v, blue: &b, alpha: &a)
        return [Double(r), Double(v), Double(b)]
        #else
        let c = NSColor(couleur).usingColorSpace(.sRGB) ?? .black
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
        #endif
    }
}

// MARK: Commandes de la barre d'outils

/// Agit sur le texte en cours d'écriture : la sélection, ou ce qui va être tapé si rien n'est sélectionné.
@MainActor final class ControleurNotes: ObservableObject {
    weak var vue: VueTexteSysteme?
    /// Appelé après chaque modification faite par la barre d'outils.
    var aChange: (() -> Void)?

    @Published var gras = false
    @Published var italique = false
    @Published var souligne = false
    @Published var style = StyleNote.corps
    @Published var alignement = AlignementNote.gauche

    private var stockage: NSTextStorage? {
        #if os(iOS)
        vue?.textStorage
        #else
        vue?.textStorage
        #endif
    }

    private var selection: NSRange {
        get {
            #if os(iOS)
            vue?.selectedRange ?? NSRange(location: 0, length: 0)
            #else
            vue?.selectedRange() ?? NSRange(location: 0, length: 0)
            #endif
        }
        set {
            #if os(iOS)
            vue?.selectedRange = newValue
            #else
            vue?.setSelectedRange(newValue)
            #endif
        }
    }

    private var attributsDeFrappe: [NSAttributedString.Key: Any] {
        get { vue?.typingAttributes ?? MiseEnForme.attributsDeBase }
        set { vue?.typingAttributes = newValue }
    }

    var largeur: CGFloat { vue?.bounds.width ?? 300 }

    /// Met à jour l'état des boutons selon ce qui est sous le curseur.
    func majEtat() {
        guard let stockage else { return }
        let r = selection
        let a: [NSAttributedString.Key: Any]
        if r.length == 0 || stockage.length == 0 {
            a = attributsDeFrappe
        } else {
            a = stockage.attributes(at: min(r.location, stockage.length - 1), effectiveRange: nil)
        }
        gras = a[.grasNote] as? Bool ?? false
        italique = a[.italiqueNote] as? Bool ?? false
        souligne = (a[.underlineStyle] as? Int ?? 0) != 0
        style = StyleNote(rawValue: a[.styleNote] as? String ?? "") ?? .corps
        alignement = (a[.paragraphStyle] as? NSParagraphStyle).map { AlignementNote($0.alignment) } ?? .gauche
    }

    /// Modifie les attributs des caractères sélectionnés (ou de la frappe), puis recalcule police et couleur.
    private func modifier(_ plage: NSRange? = nil, _ changement: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let stockage else { return }
        let r = plage ?? selection
        var frappe = attributsDeFrappe
        changement(&frappe)
        MiseEnForme.recalculer(&frappe)
        if r.length > 0 {
            stockage.beginEditing()
            stockage.enumerateAttributes(in: r) { attributs, sous, _ in
                var a = attributs
                changement(&a)
                MiseEnForme.recalculer(&a)
                stockage.setAttributes(a, range: sous)
            }
            stockage.endEditing()
        }
        attributsDeFrappe = frappe
        aChange?()
        majEtat()
    }

    /// Les paragraphes touchés par la sélection.
    private var paragraphes: NSRange {
        guard let stockage else { return NSRange(location: 0, length: 0) }
        return (stockage.string as NSString).paragraphRange(for: selection)
    }

    func basculerGras() { let v = !gras; modifier { $0[.grasNote] = v ? true : nil } }
    func basculerItalique() { let v = !italique; modifier { $0[.italiqueNote] = v ? true : nil } }
    func basculerSouligne() { let v = !souligne; modifier { $0[.underlineStyle] = v ? NSUnderlineStyle.single.rawValue : nil } }

    func choisir(_ nouveau: StyleNote) {
        modifier(paragraphes) { a in
            a[.styleNote] = nouveau.rawValue
            if nouveau != .corps { a[.grasNote] = nil }
        }
    }

    func aligner(_ nouveau: AlignementNote) {
        modifier(paragraphes) { a in
            let p = ((a[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            p.alignment = nouveau.systeme
            a[.paragraphStyle] = p
        }
    }

    /// nil : la couleur du texte par défaut.
    func colorer(_ couleur: Color?) {
        let rvb = couleur.map(MiseEnForme.composantes)
        modifier { $0[.couleurNote] = rvb }
    }

    /// Ajoute ou retire une puce au début de chaque paragraphe sélectionné.
    func basculerPuces() {
        guard let stockage else { return }
        let plage = paragraphes
        let texte = stockage.string as NSString
        var debuts: [Int] = []
        texte.enumerateSubstrings(in: plage, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in debuts.append(r.location) }
        if debuts.isEmpty { debuts = [plage.location] }
        let puce = "• "
        let toutes = debuts.allSatisfy { texte.length >= $0 + 2 && texte.substring(with: NSRange(location: $0, length: 2)) == puce }
        stockage.beginEditing()
        for debut in debuts.reversed() {
            if toutes {
                stockage.deleteCharacters(in: NSRange(location: debut, length: 2))
            } else if !(texte.length >= debut + 2 && texte.substring(with: NSRange(location: debut, length: 2)) == puce) {
                let a = stockage.length > 0 ? stockage.attributes(at: min(debut, stockage.length - 1), effectiveRange: nil) : attributsDeFrappe
                stockage.insert(NSAttributedString(string: puce, attributes: a.filter { $0.key != .attachment && $0.key != .imageNote }), at: debut)
            }
        }
        stockage.endEditing()
        let decalage = (toutes ? -2 : 2) * debuts.count
        selection = NSRange(location: max(selection.location, 0), length: max(selection.length + (selection.length > 0 ? decalage : 0), 0))
        if selection.length == 0 { selection = NSRange(location: min(plage.location + max(plage.length + decalage, 0), stockage.length), length: 0) }
        aChange?()
    }

    /// Fait de la sélection un lien ; sans sélection, écrit le texte du lien.
    func lier(_ adresse: String, texte: String) {
        var brute = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brute.isEmpty, let stockage else { return }
        if !brute.contains("://") && !brute.hasPrefix("mailto:") { brute = "https://" + brute }
        guard let url = URL(string: brute) else { return }
        let r = selection
        if r.length > 0 {
            stockage.addAttribute(.link, value: url, range: r)
        } else {
            let libelle = texte.trimmingCharacters(in: .whitespaces).isEmpty ? adresse : texte
            var a = attributsDeFrappe
            a[.link] = url
            stockage.insert(NSAttributedString(string: libelle, attributes: a), at: r.location)
            selection = NSRange(location: r.location + (libelle as NSString).length, length: 0)
            var suite = attributsDeFrappe
            suite[.link] = nil
            attributsDeFrappe = suite
        }
        aChange?()
    }

    var selectionTexte: String {
        guard let stockage, selection.length > 0, NSMaxRange(selection) <= stockage.length else { return "" }
        return (stockage.string as NSString).substring(with: selection)
    }

    func insererImage(_ donnees: Data) {
        guard let stockage, let reduite = MiseEnForme.reduire(donnees), let image = ImageSysteme(data: reduite) else { return }
        let piece = MiseEnForme.piece(image, taille: image.size, largeur: largeur)
        let morceau = NSMutableAttributedString(attachment: piece)
        var a = attributsDeFrappe
        a[.link] = nil
        a[.imageNote] = reduite
        morceau.addAttributes(a, range: NSRange(location: 0, length: morceau.length))
        let r = selection
        let avecRetour = NSMutableAttributedString(attributedString: morceau)
        avecRetour.append(NSAttributedString(string: "\n", attributes: a.filter { $0.key != .imageNote }))
        stockage.replaceCharacters(in: r, with: avecRetour)
        selection = NSRange(location: r.location + avecRetour.length, length: 0)
        aChange?()
    }
}

// MARK: Éditeur

/// Les notes mises en forme : une barre d'outils (titres, gras, souligné, couleur, alignement, puces, image, lien) et la zone de texte.
struct EditeurNotes: View {
    @Binding var texte: String
    @Binding var donnees: Data?
    var lectureSeule = false
    var invite = "Écris ici tes notes…"
    @StateObject private var controleur = ControleurNotes()
    @State private var choixImage: PhotosPickerItem?
    @State private var lienOuvert = false
    @State private var adresseLien = ""
    @State private var texteLien = ""

    private static let couleurs: [(String, Color)] = [
        ("Rouge", Color(red: 0.86, green: 0.18, blue: 0.16)), ("Orange", Color(red: 0.93, green: 0.48, blue: 0.0)),
        ("Vert", Color(red: 0.13, green: 0.6, blue: 0.27)), ("Bleu", Color(red: 0.11, green: 0.42, blue: 0.86)),
        ("Violet", Color(red: 0.52, green: 0.27, blue: 0.82)), ("Rose", Color(red: 0.88, green: 0.24, blue: 0.55)),
        ("Gris", Color(red: 0.45, green: 0.45, blue: 0.48)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !lectureSeule { barre }
            ZStack(alignment: .topLeading) {
                // Les valeurs sont lues ici, dans le corps de la vue : une note modifiée sur un autre appareil redessine la zone de texte.
                ZoneTexteNotes(controleur: controleur, texte: $texte, donnees: $donnees, lectureSeule: lectureSeule,
                               texteActuel: texte, donneesActuelles: donnees)
                if texte.isEmpty {
                    Text(lectureSeule ? "Aucune note." : invite)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: choixImage) { _, nouveau in
            guard let nouveau else { return }
            Task {
                if let d = try? await nouveau.loadTransferable(type: Data.self) { controleur.insererImage(d) }
                choixImage = nil
            }
        }
        .alert("Insérer un lien", isPresented: $lienOuvert) {
            TextField("Adresse (ex. www.exemple.com)", text: $adresseLien)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            TextField("Texte affiché", text: $texteLien)
            Button("Insérer") { controleur.lier(adresseLien, texte: texteLien) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Sans texte sélectionné, le texte affiché est écrit à l'endroit du curseur.")
        }
    }

    private var barre: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Menu {
                    ForEach(StyleNote.allCases) { s in
                        Button { controleur.choisir(s) } label: {
                            if controleur.style == s { Label(s.libelle, systemImage: "checkmark") } else { Text(s.libelle) }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(controleur.style.libelle).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .padding(.horizontal, 8).frame(height: 30)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Titre, sous-titre ou texte")

                separateur
                bouton("bold", actif: controleur.gras, aide: "Gras", controleur.basculerGras)
                bouton("italic", actif: controleur.italique, aide: "Italique", controleur.basculerItalique)
                bouton("underline", actif: controleur.souligne, aide: "Souligné", controleur.basculerSouligne)
                Menu {
                    Button("Couleur par défaut", systemImage: "circle.slash") { controleur.colorer(nil) }
                    ForEach(Self.couleurs, id: \.0) { nom, couleur in
                        Button { controleur.colorer(couleur) } label: {
                            Label { Text(nom) } icon: { Image(systemName: "circle.fill").foregroundStyle(couleur) }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette.fill").symbolRenderingMode(.multicolor)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Couleur du texte")

                separateur
                Menu {
                    ForEach(AlignementNote.allCases) { a in
                        Button { controleur.aligner(a) } label: {
                            Label(a == .gauche ? "À gauche" : a == .centre ? "Centré" : "À droite", systemImage: a.symbole)
                        }
                    }
                } label: {
                    Image(systemName: controleur.alignement.symbole).frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Alignement")
                bouton("list.bullet", actif: false, aide: "Liste à puces", controleur.basculerPuces)

                separateur
                PhotosPicker(selection: $choixImage, matching: .images) {
                    Image(systemName: "photo").frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Insérer une image")
                bouton("link", actif: false, aide: "Insérer un lien") {
                    texteLien = controleur.selectionTexte
                    adresseLien = ""
                    lienOuvert = true
                }
            }
            .font(.body)
            .foregroundStyle(.primary)
        }
    }

    private var separateur: some View {
        Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 2)
    }

    private func bouton(_ symbole: String, actif: Bool, aide: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .fontWeight(actif ? .bold : .regular)
                .frame(width: 30, height: 30)
                .background(actif ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(aide)
    }
}

/// La zone de texte du système (UITextView, NSTextView), qui sait afficher styles, images et liens.
private struct ZoneTexteNotes {
    @ObservedObject var controleur: ControleurNotes
    @Binding var texte: String
    @Binding var donnees: Data?
    var lectureSeule: Bool
    var texteActuel: String
    var donneesActuelles: Data?

    final class Coordinateur: NSObject {
        var parent: ZoneTexteNotes
        /// Dernières données écrites ou chargées : une valeur différente vient d'ailleurs (synchronisation) et est rechargée.
        var dernieres: Data?
        var dernierTexte = ""
        init(_ parent: ZoneTexteNotes) { self.parent = parent }

        @MainActor func emettre(_ attribue: NSAttributedString) {
            let d = MiseEnForme.donnees(depuis: attribue)
            dernieres = d
            dernierTexte = attribue.string.replacingOccurrences(of: "\u{FFFC}", with: "")
            parent.donnees = d
            parent.texte = dernierTexte
        }

        @MainActor func charger(_ vue: VueTexteSysteme) {
            let largeur = max(vue.bounds.width, 260)
            let contenu = MiseEnForme.texte(depuis: parent.donnees, texteSimple: parent.texte, largeur: largeur)
            #if os(iOS)
            vue.attributedText = contenu
            #else
            vue.textStorage?.setAttributedString(contenu)
            #endif
            vue.typingAttributes = contenu.length > 0
                ? contenu.attributes(at: contenu.length - 1, effectiveRange: nil).filter { $0.key != .attachment && $0.key != .imageNote && $0.key != .link }
                : MiseEnForme.attributsDeBase
            dernieres = parent.donnees
            dernierTexte = parent.texte
        }

        @MainActor func doitRecharger() -> Bool {
            parent.donneesActuelles != dernieres || (parent.donneesActuelles == nil && parent.texteActuel != dernierTexte)
        }

        /// Recharge une note arrivée d'ailleurs en gardant le curseur à sa place, même pendant l'écriture.
        @MainActor func recharger(_ vue: VueTexteSysteme) {
            #if os(iOS)
            let curseur = vue.selectedRange
            charger(vue)
            let longueur = vue.attributedText.length
            vue.selectedRange = NSRange(location: min(curseur.location, longueur), length: min(curseur.length, max(longueur - curseur.location, 0)))
            #else
            let curseur = vue.selectedRange()
            charger(vue)
            let longueur = vue.textStorage?.length ?? 0
            vue.setSelectedRange(NSRange(location: min(curseur.location, longueur), length: min(curseur.length, max(longueur - curseur.location, 0))))
            #endif
            parent.controleur.majEtat()
        }
    }

    func makeCoordinator() -> Coordinateur { Coordinateur(self) }
}

#if os(iOS)
extension ZoneTexteNotes: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let vue = UITextView()
        vue.backgroundColor = .clear
        vue.delegate = context.coordinator
        vue.isEditable = !lectureSeule
        vue.dataDetectorTypes = lectureSeule ? [.link] : []
        vue.allowsEditingTextAttributes = true
        vue.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        vue.adjustsFontForContentSizeCategory = false
        controleur.vue = vue
        controleur.aChange = { [weak vue, weak coordinateur = context.coordinator] in
            guard let vue else { return }
            coordinateur?.emettre(vue.attributedText)
        }
        context.coordinator.charger(vue)
        return vue
    }

    func updateUIView(_ vue: UITextView, context: Context) {
        context.coordinator.parent = self
        vue.isEditable = !lectureSeule
        if context.coordinator.doitRecharger() { context.coordinator.recharger(vue) }
    }
}

extension ZoneTexteNotes.Coordinateur: UITextViewDelegate {
    func textViewDidChange(_ vue: UITextView) { emettre(vue.attributedText) }
    func textViewDidChangeSelection(_ vue: UITextView) { parent.controleur.majEtat() }
}
#else
extension ZoneTexteNotes: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let defilement = NSTextView.scrollableTextView()
        defilement.drawsBackground = false
        defilement.hasVerticalScroller = true
        guard let vue = defilement.documentView as? NSTextView else { return defilement }
        vue.drawsBackground = false
        vue.isRichText = true
        vue.importsGraphics = true
        vue.allowsUndo = true
        vue.isEditable = !lectureSeule
        vue.isAutomaticLinkDetectionEnabled = false
        vue.textContainerInset = NSSize(width: 0, height: 8)
        vue.delegate = context.coordinator
        controleur.vue = vue
        controleur.aChange = { [weak vue, weak coordinateur = context.coordinator] in
            guard let vue, let stockage = vue.textStorage else { return }
            coordinateur?.emettre(stockage)
        }
        context.coordinator.charger(vue)
        return defilement
    }

    func updateNSView(_ defilement: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let vue = defilement.documentView as? NSTextView else { return }
        vue.isEditable = !lectureSeule
        if context.coordinator.doitRecharger() { context.coordinator.recharger(vue) }
    }
}

extension ZoneTexteNotes.Coordinateur: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let vue = notification.object as? NSTextView, let stockage = vue.textStorage else { return }
        emettre(stockage)
    }
    func textViewDidChangeSelection(_ notification: Notification) { parent.controleur.majEtat() }
}
#endif
