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

    /// Mon voyageur dans ce voyage : je le retrouve par mon prénom, ou je m'y ajoute. Renvoie son identifiant.
    @discardableResult
    func identifier(dans voyage: Voyage, contexte: ModelContext) -> String {
        let actuel = MoiVoyage.lire(voyage)
        if estRenseigne, !voyage.membres.contains(where: { $0.uid == actuel }) {
            reconnaitre(dans: voyage)
            if !voyage.membres.contains(where: { $0.uid == MoiVoyage.lire(voyage) }) {
                let membre = Membre(nom: prenom.trimmingCharacters(in: .whitespaces))
                membre.voyage = voyage
                contexte.insert(membre)
                MoiVoyage.ecrire(membre.uid, voyage)
            }
        }
        publier(dans: contexte)
        return MoiVoyage.lire(voyage)
    }

    /// Recopie mon profil sur mon voyageur dans chaque voyage où je suis identifié : les autres le reçoivent par iCloud.
    func publier(dans contexte: ModelContext) {
        guard estRenseigne else { return }
        let prenomNet = prenom.trimmingCharacters(in: .whitespaces)
        let nomNet = nom.trimmingCharacters(in: .whitespaces)
        let emailNet = email.trimmingCharacters(in: .whitespaces)
        for voyage in (try? contexte.fetch(FetchDescriptor<Voyage>())) ?? [] {
            let uid = MoiVoyage.lire(voyage)
            guard !uid.isEmpty, let membre = voyage.membres.first(where: { $0.uid == uid }) else { continue }
            // On n'écrit que ce qui change, pour ne pas envoyer des mises à jour inutiles.
            if membre.nom != prenomNet { membre.nom = prenomNet }
            if (membre.nomFamille ?? "") != nomNet { membre.nomFamille = nomNet.isEmpty ? nil : nomNet }
            if (membre.email ?? "") != emailNet { membre.email = emailNet.isEmpty ? nil : emailNet }
            if membre.avatar != avatar { membre.avatar = avatar }
        }
        try? contexte.save()
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

/// Les ronds des voyageurs. Mon rond ouvre mon profil ; celui d'un autre ouvre ses informations.
struct GroupeAvatars: View {
    var voyage: Voyage
    var onMoi: () -> Void
    var onAutre: (Membre) -> Void
    private var profil = Profil.partage

    init(voyage: Voyage, onMoi: @escaping () -> Void, onAutre: @escaping (Membre) -> Void) {
        self.voyage = voyage
        self.onMoi = onMoi
        self.onAutre = onAutre
    }

    private var autres: [Membre] {
        let moi = MoiVoyage.lire(voyage)
        return voyage.membres.filter { $0.uid != moi }.sorted { $0.creeLe < $1.creeLe }
    }

    var body: some View {
        HStack(spacing: -8) {
            // Moi d'abord, même si je ne suis pas encore dans la liste des voyageurs.
            Button(action: onMoi) {
                AvatarView(initiales: profil.initiales, donnees: profil.avatar, taille: 28)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mon profil")
            ForEach(autres.prefix(3)) { membre in
                Button { onAutre(membre) } label: {
                    AvatarView(initiales: Profil.initiales(de: membre.nomAffiche), donnees: membre.avatar, taille: 28,
                               couleur: AvatarView.couleur(pour: membre.uid))
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(membre.nomAffiche)
            }
            if autres.count > 3 {
                Text("+\(autres.count - 3)").font(.caption2.bold()).foregroundStyle(.secondary).padding(.leading, 12)
            }
        }
    }
}

extension Membre {
    /// Prénom et nom de famille, quand le voyageur les a renseignés.
    var nomAffiche: String {
        [nom, nomFamille ?? ""].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Voyage {
    func membre(uid: String) -> Membre? { membres.first { $0.uid == uid } }
}

/// Les informations d'un autre voyageur.
struct ProfilMembreView: View {
    let membre: Membre
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                AvatarView(initiales: Profil.initiales(de: membre.nomAffiche), donnees: membre.avatar, taille: 110,
                           couleur: AvatarView.couleur(pour: membre.uid))
                Text(membre.nomAffiche).font(.title2.bold())
                if let email = membre.email, !email.isEmpty {
                    if let lien = URL(string: "mailto:\(email)") {
                        Link(destination: lien) { Label(email, systemImage: "envelope") }
                    } else {
                        Label(email, systemImage: "envelope")
                    }
                } else {
                    Text("Cette personne n'a pas renseigné d'e-mail.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 30).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .navigationTitle("Voyageur")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 360)
        #endif
    }
}

/// Saisie et modification de mon profil. À la première ouverture de l'app, elle ne peut pas être fermée sans prénom.
struct ProfilEditView: View {
    var premiereFois = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
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
                    Text("Ton prénom, ton nom, ton e-mail et ta photo sont visibles des autres voyageurs de tes voyages partagés. Ton prénom sert aussi à te reconnaître dans les voyages.")
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
        profil.publier(dans: contexte)
        dismiss()
    }
}
