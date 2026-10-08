import SwiftUI
import SwiftData
import PhotosUI

/// La fiche d'une famille : sa photo. Les familles elles-mêmes sont le nom commun de leurs membres (`Membre.familleNom`) ;
/// cette fiche n'existe que si une photo a été choisie, et se retrouve par le nom.
@Model
final class Famille {
    var nom: String = ""
    @Attribute(.externalStorage) var avatar: Data?
    var creeLe: Date = Date.now
    var uid: String = ""
    var voyage: Voyage?

    init(nom: String) {
        self.nom = nom
        self.creeLe = .now
        self.uid = UUID().uuidString
    }
}

extension Voyage {
    func fiche(famille nom: String) -> Famille? {
        fichesFamilles.first { $0.nom.caseInsensitiveCompare(nom) == .orderedSame }
    }

    func photo(famille nom: String) -> Data? { fiche(famille: nom)?.avatar }

    /// Enregistre la photo d'une famille (nil : la retire), en créant ou supprimant la fiche au besoin.
    func definirPhoto(_ photo: Data?, famille nom: String, contexte: ModelContext) {
        if let fiche = fiche(famille: nom) {
            if photo == nil { contexte.delete(fiche) } else if fiche.avatar != photo { fiche.avatar = photo }
        } else if let photo {
            let fiche = Famille(nom: nom)
            fiche.avatar = photo
            fiche.voyage = self
            contexte.insert(fiche)
        }
    }

    /// Renomme la famille : ses membres et sa fiche.
    func renommer(famille ancien: String, en nom: String) {
        for membre in membres where membre.famille.caseInsensitiveCompare(ancien) == .orderedSame { membre.familleNom = nom }
        fiche(famille: ancien)?.nom = nom
    }
}

/// La photo d'une famille, ou à défaut une icône de maison.
struct VignetteFamille: View {
    var photo: Data?
    var nom: String
    var taille: CGFloat = 64

    var body: some View {
        if let photo {
            AvatarView(initiales: "", donnees: photo, taille: taille)
        } else {
            Image(systemName: "house.fill")
                .font(.system(size: taille * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: taille, height: taille)
                .background(Circle().fill(AvatarView.couleur(pour: nom)))
        }
    }
}

/// Création ou modification d'une famille : son nom et sa photo.
struct FamilleEditView: View {
    var voyage: Voyage
    /// nil : nouvelle famille.
    var existante: String?
    /// Reçoit le nom enregistré (pour une nouvelle famille, afin d'y ajouter son premier membre).
    var enregistre: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var nom: String
    @State private var photo: Data?
    @State private var choix: PhotosPickerItem?

    init(voyage: Voyage, existante: String?, enregistre: @escaping (String) -> Void) {
        self.voyage = voyage
        self.existante = existante
        self.enregistre = enregistre
        _nom = State(initialValue: existante ?? "")
        _photo = State(initialValue: existante.flatMap { voyage.photo(famille: $0) })
    }

    private var nomNet: String { nom.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        VignetteFamille(photo: photo, nom: nomNet, taille: 96)
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $choix, matching: .images) {
                                Label(photo == nil ? "Choisir une photo" : "Changer la photo", systemImage: "photo")
                            }
                            if photo != nil { Button("Retirer", role: .destructive) { photo = nil; choix = nil } }
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Sans photo, une icône de maison s'affiche avec le nom de la famille.")
                }
                Section { TextField("Nom de la famille", text: $nom) }
            }
            .formStyle(.grouped)
            .navigationTitle(existante == nil ? "Nouvelle famille" : "Famille")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existante == nil ? "Ajouter un premier membre" : "Enregistrer") { valider() }.disabled(nomNet.isEmpty)
                }
            }
            .onChange(of: choix) { _, nouveau in
                guard let nouveau else { return }
                Task {
                    if let donnees = try? await nouveau.loadTransferable(type: Data.self), let reduite = Profil.reduire(donnees) { photo = reduite }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 420)
        #endif
    }

    private func valider() {
        var nomFinal = nomNet
        if let existante, existante != nomNet { voyage.renommer(famille: existante, en: nomNet) }
        // Un nom déjà pris rejoint la famille du même nom (et garde l'orthographe existante).
        if let autre = voyage.familles.first(where: { $0.nom.caseInsensitiveCompare(nomNet) == .orderedSame }) { nomFinal = autre.nom }
        voyage.definirPhoto(photo, famille: nomFinal, contexte: contexte)
        dismiss()
        enregistre(nomFinal)
    }
}
