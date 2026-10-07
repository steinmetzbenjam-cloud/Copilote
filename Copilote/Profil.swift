import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Mon profil : prénom, nom, e-mail et photo. Gardé sur cet appareil.
@MainActor @Observable
final class Profil {
    static let partage = Profil()

    var prenom: String { didSet { UserDefaults.standard.set(prenom, forKey: "profilPrenom") } }
    var nom: String { didSet { UserDefaults.standard.set(nom, forKey: "profilNom") } }
    var email: String { didSet { UserDefaults.standard.set(email, forKey: "profilEmail") } }
    var avatar: Data? { didSet { UserDefaults.standard.set(avatar, forKey: "profilAvatar") } }

    private init() {
        let d = UserDefaults.standard
        prenom = d.string(forKey: "profilPrenom") ?? ""
        nom = d.string(forKey: "profilNom") ?? ""
        email = d.string(forKey: "profilEmail") ?? ""
        avatar = d.data(forKey: "profilAvatar")
    }

    var estRenseigne: Bool { !prenom.trimmingCharacters(in: .whitespaces).isEmpty }
    var nomComplet: String { [prenom, nom].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ") }
    var initiales: String { Self.initiales(prenom: prenom, nom: nom) }

    static func initiales(prenom: String, nom: String) -> String {
        let p = prenom.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let n = nom.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        return (p + n).uppercased()
    }

    /// Initiales d'un nom affiché en un seul morceau (« Florence STEINMETZ » → FS ; « Ben » → B).
    static func initiales(de nomComplet: String) -> String {
        let mots = nomComplet.split(separator: " ")
        return mots.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// Si mon prénom correspond à un voyageur du voyage et que je ne me suis pas encore identifié, je le deviens.
    func reconnaitre(dans voyage: Voyage) {
        guard estRenseigne, MoiVoyage.lire(voyage).isEmpty else { return }
        let cherche = prenom.trimmingCharacters(in: .whitespaces).lowercased()
        let complet = nomComplet.lowercased()
        if let membre = voyage.membres.first(where: { [cherche, complet].contains($0.nom.trimmingCharacters(in: .whitespaces).lowercased()) }) {
            MoiVoyage.ecrire(membre.uid, voyage)
        }
    }

    /// Photo carrée de 256 px, en JPEG léger.
    static func reduire(_ donnees: Data, cote: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cote * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let c = min(image.width, image.height)
        let zone = CGRect(x: (image.width - c) / 2, y: (image.height - c) / 2, width: c, height: c)
        guard let carree = image.cropping(to: zone) else { return nil }
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, carree, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return sortie as Data
    }
}

/// Un rond : la photo si on en a une, sinon les initiales.
struct AvatarView: View {
    var initiales: String
    var donnees: Data?
    var taille: CGFloat = 32
    var couleur: Color = .accentColor

    var body: some View {
        ZStack {
            if let image = Self.image(donnees) {
                image.resizable().scaledToFill()
            } else {
                couleur
                Text(initiales.isEmpty ? "?" : initiales)
                    .font(.system(size: taille * 0.4, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(Circle())
    }

    private static func image(_ donnees: Data?) -> Image? {
        guard let donnees else { return nil }
        #if os(iOS)
        return UIImage(data: donnees).map { Image(uiImage: $0) }
        #else
        return NSImage(data: donnees).map { Image(nsImage: $0) }
        #endif
    }

    /// Une couleur stable par personne.
    static func couleur(pour texte: String) -> Color {
        let palette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .brown, .green, .blue]
        let somme = texte.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 }
        return palette[somme % palette.count]
    }
}

/// Les ronds des voyageurs, à droite du nom du voyage. Mon rond porte ma photo ; toucher le groupe ouvre mon profil.
struct GroupeAvatars: View {
    var voyage: Voyage
    var action: () -> Void
    private var profil = Profil.partage

    init(voyage: Voyage, action: @escaping () -> Void) {
        self.voyage = voyage
        self.action = action
    }

    private struct Rond: Identifiable {
        let id: String
        let initiales: String
        let donnees: Data?
        let couleur: Color
    }

    private var ronds: [Rond] {
        let moi = MoiVoyage.lire(voyage)
        let membres = voyage.membres.sorted { $0.creeLe < $1.creeLe }
        var liste: [Rond] = []
        // Moi d'abord, même si je ne suis pas encore dans la liste des voyageurs.
        liste.append(Rond(id: "moi", initiales: profil.initiales, donnees: profil.avatar, couleur: .accentColor))
        for m in membres where m.uid != moi {
            liste.append(Rond(id: m.uid, initiales: Profil.initiales(de: m.nom), donnees: nil, couleur: AvatarView.couleur(pour: m.uid)))
        }
        return liste
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: -8) {
                ForEach(ronds.prefix(4)) { rond in
                    AvatarView(initiales: rond.initiales, donnees: rond.donnees, taille: 28, couleur: rond.couleur)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
                if ronds.count > 4 {
                    Text("+\(ronds.count - 4)").font(.caption2.bold()).foregroundStyle(.secondary).padding(.leading, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mon profil")
    }
}

/// Saisie et modification de mon profil. À la première ouverture de l'app, elle ne peut pas être fermée sans prénom.
struct ProfilEditView: View {
    var premiereFois = false
    @Environment(\.dismiss) private var dismiss
    @State private var prenom = Profil.partage.prenom
    @State private var nom = Profil.partage.nom
    @State private var email = Profil.partage.email
    @State private var avatar = Profil.partage.avatar
    @State private var choix: PhotosPickerItem?

    private var valide: Bool { !prenom.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        AvatarView(initiales: Profil.initiales(prenom: prenom, nom: nom), donnees: avatar, taille: 96)
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $choix, matching: .images) {
                                Label(avatar == nil ? "Choisir une photo" : "Changer la photo", systemImage: "photo")
                            }
                            if avatar != nil {
                                Button("Retirer", role: .destructive) { avatar = nil; choix = nil }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Sans photo, tes initiales s'affichent à la place.")
                }
                Section {
                    TextField("Prénom", text: $prenom)
                    TextField("Nom", text: $nom)
                    TextField("E-mail", text: $email)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                } header: {
                    Text(premiereFois ? "Bienvenue ! Qui es-tu ?" : "Mes informations")
                } footer: {
                    Text("Ces informations restent sur cet appareil. Ton prénom sert à te reconnaître dans les voyages.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Mon profil")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(premiereFois ? "Continuer" : "Enregistrer") { enregistrer() }.disabled(!valide)
                }
                if !premiereFois {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                }
            }
            .onChange(of: choix) { _, nouveau in
                guard let nouveau else { return }
                Task {
                    if let donnees = try? await nouveau.loadTransferable(type: Data.self), let reduite = Profil.reduire(donnees) {
                        avatar = reduite
                    }
                }
            }
        }
        .interactiveDismissDisabled(premiereFois)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    private func enregistrer() {
        let profil = Profil.partage
        profil.prenom = prenom.trimmingCharacters(in: .whitespaces)
        profil.nom = nom.trimmingCharacters(in: .whitespaces)
        profil.email = email.trimmingCharacters(in: .whitespaces)
        profil.avatar = avatar
        dismiss()
    }
}
