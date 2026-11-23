import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
import Photos
import ImageIO
import UniformTypeIdentifiers

/// En voyage, à côté de « Y aller » : prendre une photo avec l'appareil, qui rejoint aussitôt l'album de l'étape (ou de la sous-étape),
/// réduite comme les autres. L'original, en pleine résolution, est gardé dans la photothèque de l'appareil.
/// Sans appareil photo, le bouton ouvre la photothèque à la place (la photo y est déjà : rien n'y est ajouté).
struct BoutonPhotoAlbum: View {
    let etape: Etape
    var taille: CGFloat = 50
    @Environment(\.modelContext) private var contexte
    @State private var ouvert = false
    @State private var enCours = false
    @State private var ajoutee = false
    @State private var photothequeRefusee = false

    private static var avecAppareil: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        if !(etape.voyage?.lectureSeule ?? true) {
            Button { ouvert = true } label: {
                VStack(spacing: 4) {
                    ZStack {
                        if enCours {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: ajoutee ? "checkmark" : "camera.fill")
                                .font(.system(size: taille * 0.38, weight: .semibold)).foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: taille, height: taille)
                    .background(Circle().fill(ajoutee ? Color.green : Color.indigo))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    Text(ajoutee ? "Ajoutée" : "Photo").font(.caption.weight(.semibold))
                        .foregroundStyle(ajoutee ? Color.green : Color.indigo)
                }
            }
            .buttonStyle(.plain)
            .disabled(enCours)
            .accessibilityLabel("Prendre une photo pour l'album")
            .fullScreenCover(isPresented: $ouvert) {
                PriseDeVue(source: Self.avecAppareil ? .camera : .photoLibrary) { image, metadonnees in
                    ouvert = false
                    if let image { Task { await ajouter(image, metadonnees: metadonnees, garder: Self.avecAppareil) } }
                }
                .ignoresSafeArea()
            }
            .alert("Photo gardée dans l'album seulement", isPresented: $photothequeRefusee) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pour garder aussi l'original dans tes Photos, autorise Copilote dans Réglages › Confidentialité et sécurité › Photos.")
            }
        }
    }

    /// Encode la photo en pleine résolution avec ses métadonnées, la garde dans la photothèque (prise de vue seulement),
    /// puis la réduit hors du fil principal, comme celles de la photothèque, et l'ajoute à l'album.
    private func ajouter(_ image: UIImage, metadonnees: [String: Any]?, garder: Bool) async {
        enCours = true
        defer { enCours = false }
        guard let originale = await Task.detached(priority: .userInitiated, operation: { Self.encoder(image, metadonnees: metadonnees) }).value
        else { return }
        if garder, !(await Self.garderDansPhotos(originale, lieu: etape.coordonnee)) { photothequeRefusee = true }
        guard var prete = await Task.detached(priority: .userInitiated, operation: { PhotoAlbum.preparer(originale) }).value
        else { return }
        // Sans date de prise de vue dans ses données, la photo date de maintenant.
        if prete.priseLe == nil { prete.priseLe = .now }
        withAnimation(.snappy) { _ = etape.ajouterAuAlbum(prete, dans: contexte) }
        withAnimation { ajoutee = true }
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation { ajoutee = false }
    }

    /// L'image en HEIC (JPEG à défaut), pleine résolution, avec les métadonnées de l'appareil (date, orientation, réglages).
    nonisolated static func encoder(_ image: UIImage, metadonnees: [String: Any]?) -> Data? {
        guard let cg = image.cgImage else { return image.jpegData(compressionQuality: 0.95) }
        var proprietes = metadonnees ?? [:]
        // Les pixels sont ceux du capteur : l'orientation indique comment les tourner.
        proprietes[kCGImagePropertyOrientation as String] = CGImagePropertyOrientation(image.imageOrientation).rawValue
        proprietes[kCGImageDestinationLossyCompressionQuality as String] = 0.9
        for type in [UTType.heic, .jpeg] {
            let sortie = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(sortie, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, cg, proprietes as CFDictionary)
            if CGImageDestinationFinalize(destination) { return sortie as Data }
        }
        return image.jpegData(compressionQuality: 0.95)
    }

    /// Ajoute l'original à la photothèque (autorisation d'ajout seulement), situé au lieu de l'étape. Faux si refusé ou en échec.
    private static func garderDansPhotos(_ donnees: Data, lieu: CLLocationCoordinate2D?) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let demande = PHAssetCreationRequest.forAsset()
                demande.addResource(with: .photo, data: donnees, options: nil)
                if let lieu { demande.location = CLLocation(latitude: lieu.latitude, longitude: lieu.longitude) }
            }
            return true
        } catch {
            return false
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// L'appareil photo du système (ou la photothèque) : rend l'image prise et ses métadonnées, ou nil si on annule.
private struct PriseDeVue: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let fin: (UIImage?, [String: Any]?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = source
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinateur { Coordinateur(fin: fin) }

    final class Coordinateur: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fin: (UIImage?, [String: Any]?) -> Void
        init(fin: @escaping (UIImage?, [String: Any]?) -> Void) { self.fin = fin }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            fin(info[.originalImage] as? UIImage, info[.mediaMetadata] as? [String: Any])
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { fin(nil, nil) }
    }
}
#endif
