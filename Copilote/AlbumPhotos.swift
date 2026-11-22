import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Préparation des photos

/// Les photos d'album sont réduites avant d'être enregistrées (et donc envoyées sur iCloud) :
/// 2 048 pixels au plus sur le grand côté, en HEIC (ou JPEG si l'appareil ne sait pas l'écrire), sans les métadonnées (position GPS…).
/// Une photo d'iPhone de 3 à 6 Mo passe ainsi à quelques centaines de Ko.
enum PhotoAlbum {
    static let coteMax = 2048
    static let qualite = 0.6

    struct Prete: Sendable {
        var donnees: Data
        var extensionFichier: String
        /// Date de prise de vue lue dans la photo, pour ranger l'album dans l'ordre de la journée.
        var priseLe: Date?
    }

    /// Réduit une image (données d'origine de la photothèque) ; nil si ce n'est pas une image lisible.
    static func preparer(_ donnees: Data, coteMax: Int = coteMax) -> Prete? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  // L'orientation est appliquée aux pixels : la photo s'affiche à l'endroit partout.
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: coteMax,
              ] as CFDictionary)
        else { return nil }
        let priseLe = datePriseDeVue(source)
        if let heic = encoder(image, type: .heic) { return Prete(donnees: heic, extensionFichier: "heic", priseLe: priseLe) }
        if let jpeg = encoder(image, type: .jpeg) { return Prete(donnees: jpeg, extensionFichier: "jpg", priseLe: priseLe) }
        return nil
    }

    private static func encoder(_ image: CGImage, type: UTType) -> Data? {
        let sortie = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(sortie, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: qualite] as CFDictionary)
        guard CGImageDestinationFinalize(destination), sortie.length > 0 else { return nil }
        return sortie as Data
    }

    private static func datePriseDeVue(_ source: CGImageSource) -> Date? {
        guard let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = proprietes[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let texte = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return format.date(from: texte)
    }

    /// Une petite image pour la grille de l'album (décodée à la taille voulue, gardée en cache).
    static func vignette(_ donnees: Data, cle: String, cote: Int) -> CGImage? {
        let cleCache = "\(cle)-\(cote)" as NSString
        if let image = cache.object(forKey: cleCache) { return image.cg }
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: cote,
              ] as CFDictionary)
        else { return nil }
        cache.setObject(ImageEnCache(image), forKey: cleCache)
        return image
    }

    private final class ImageEnCache: @unchecked Sendable {
        let cg: CGImage
        init(_ cg: CGImage) { self.cg = cg }
    }
    nonisolated(unsafe) private static let cache: NSCache<NSString, ImageEnCache> = {
        let c = NSCache<NSString, ImageEnCache>()
        c.countLimit = 300
        return c
    }()
}

// MARK: - Album d'une étape

extension Document {
    /// Type des photos d'album d'une étape (les autres photos d'une étape sont celles de son lieu).
    static let typeAlbum = "album"
    var estPhotoAlbum: Bool { typeBrut == Self.typeAlbum }
}

extension Etape {
    /// Les photos de l'album, dans l'ordre de prise de vue.
    var album: [Document] {
        photos.filter(\.estPhotoAlbum).sorted { ($0.creeLe, $0.uid) < ($1.creeLe, $1.uid) }
    }

    /// Les photos du lieu (rapatriées d'un lieu proposé), sans celles de l'album.
    var photosDuLieu: [Document] { photos.filter { !$0.estPhotoAlbum } }

    /// Ajoute une photo déjà réduite à l'album.
    @discardableResult
    func ajouterAuAlbum(_ photo: PhotoAlbum.Prete, dans contexte: ModelContext) -> Document {
        let d = Document(nom: titre.isEmpty ? "Photo" : titre, extensionFichier: photo.extensionFichier, donnees: photo.donnees)
        d.typeBrut = Document.typeAlbum
        if let priseLe = photo.priseLe { d.creeLe = priseLe }
        d.voyage = voyage
        d.etape = self
        contexte.insert(d)
        return d
    }
}

/// Le contenu de la section « Album photo » d'une étape ou d'une sous-étape : la grille, et l'ajout depuis la photothèque.
struct AlbumEtapeSection: View {
    let etape: Etape
    @Environment(\.modelContext) private var contexte
    @State private var choix: [PhotosPickerItem] = []
    @State private var enCours = 0
    @State private var ouverte: PhotoOuverte?

    private var modifiable: Bool { !(etape.voyage?.lectureSeule ?? true) }

    var body: some View {
        let photos = etape.album
        VStack(alignment: .leading, spacing: 10) {
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.element.uid) { index, photo in
                        Button { ouverte = PhotoOuverte(index: index) } label: {
                            VignetteAlbum(photo: photo)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if modifiable {
                                Button("Supprimer la photo", systemImage: "trash", role: .destructive) {
                                    withAnimation { contexte.delete(photo) }
                                }
                            }
                        }
                    }
                }
            }
            if enCours > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(enCours == 1 ? "Ajout d'une photo…" : "Ajout de \(enCours) photos…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if modifiable {
                PhotosPicker(selection: $choix, maxSelectionCount: 50, selectionBehavior: .ordered, matching: .images) {
                    Label(photos.isEmpty ? "Ajouter des photos" : "Ajouter d'autres photos", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .disabled(enCours > 0)
            } else if photos.isEmpty {
                Text("Aucune photo.").font(.footnote).foregroundStyle(.secondary)
            }
            if !photos.isEmpty {
                let taille = photos.reduce(0) { $0 + $1.donnees.count }
                Text("\(photos.count) photo\(photos.count > 1 ? "s" : "") · \(taille.formatted(.byteCount(style: .file)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: choix) { _, elements in
            guard !elements.isEmpty else { return }
            choix = []
            Task { await ajouter(elements) }
        }
        #if os(iOS)
        .fullScreenCover(item: $ouverte) { VisionneuseAlbum(etape: etape, index: $0.index) }
        #else
        .sheet(item: $ouverte) { VisionneuseAlbum(etape: etape, index: $0.index).frame(minWidth: 720, minHeight: 540) }
        #endif
    }

    /// Charge chaque photo choisie, la réduit hors du fil principal, puis l'ajoute à l'album.
    private func ajouter(_ elements: [PhotosPickerItem]) async {
        enCours = elements.count
        for element in elements {
            if let brutes = try? await element.loadTransferable(type: Data.self),
               let prete = await Task.detached(priority: .userInitiated, operation: { PhotoAlbum.preparer(brutes) }).value {
                withAnimation(.snappy) { _ = etape.ajouterAuAlbum(prete, dans: contexte) }
            }
            enCours -= 1
        }
        enCours = 0
    }
}

private struct PhotoOuverte: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Une case carrée de la grille de l'album.
private struct VignetteAlbum: View {
    let photo: Document
    @State private var image: CGImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: photo.uid) {
                let donnees = photo.donnees, cle = photo.uid
                image = await Task.detached(priority: .utility) { PhotoAlbum.vignette(donnees, cle: cle, cote: 300) }.value
            }
    }
}

// MARK: - Visionneuse

/// Les photos de l'album en grand, une à une : on passe de l'une à l'autre en glissant (ou avec les flèches sur Mac).
struct VisionneuseAlbum: View {
    let etape: Etape
    @State var index: Int
    @Environment(\.dismiss) private var fermer
    @Environment(\.modelContext) private var contexte
    @State private var suppressionDemandee = false
    @State private var fichierAPartager: URL?

    private var photos: [Document] { etape.album }
    private var modifiable: Bool { !(etape.voyage?.lectureSeule ?? true) }

    var body: some View {
        let photos = self.photos
        ZStack {
            Color.black.ignoresSafeArea()
            if photos.isEmpty {
                Color.clear.onAppear { fermer() }
            } else {
                defilement(photos)
            }
        }
        .overlay(alignment: .top) { barreDuHaut(photos) }
        .overlay(alignment: .bottom) { legende(photos) }
        .task(id: photos.indices.contains(index) ? photos[index].uid : "") {
            fichierAPartager = photos.indices.contains(index) ? try? photos[index].urlTemporaire() : nil
        }
        .confirmationDialog("Supprimer cette photo de l'album ?", isPresented: $suppressionDemandee, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { supprimer() }
        }
        #if os(iOS)
        .statusBarHidden()
        #else
        .onKeyPress(.leftArrow) { aller(-1); return .handled }
        .onKeyPress(.rightArrow) { aller(1); return .handled }
        #endif
    }

    @ViewBuilder private func defilement(_ photos: [Document]) -> some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.uid) { i, photo in
                PhotoEnGrand(photo: photo).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        #else
        PhotoEnGrand(photo: photos[min(index, photos.count - 1)])
            .id(photos[min(index, photos.count - 1)].uid)
            .overlay(alignment: .leading) { fleche("chevron.left", -1).disabled(index == 0) }
            .overlay(alignment: .trailing) { fleche("chevron.right", 1).disabled(index >= photos.count - 1) }
        #endif
    }

    #if os(macOS)
    private func fleche(_ symbole: String, _ sens: Int) -> some View {
        Button { aller(sens) } label: {
            Image(systemName: symbole).font(.title.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain).padding(16)
    }
    #endif

    private func aller(_ sens: Int) {
        index = max(0, min(photos.count - 1, index + sens))
    }

    private func barreDuHaut(_ photos: [Document]) -> some View {
        HStack(spacing: 14) {
            Button { fermer() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Fermer")
                .keyboardShortcut(.cancelAction)
            Spacer()
            if photos.count > 1 { Text("\(min(index, photos.count - 1) + 1) / \(photos.count)").monospacedDigit() }
            Spacer()
            if let fichierAPartager {
                ShareLink(item: fichierAPartager) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Partager")
            }
            if modifiable {
                Button { suppressionDemandee = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Supprimer")
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    @ViewBuilder private func legende(_ photos: [Document]) -> some View {
        if photos.indices.contains(index) {
            VStack(spacing: 2) {
                Text(etape.titre).font(.subheadline.weight(.semibold))
                Text(photos[index].creeLe.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.top, 30).padding(.bottom, 14)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .allowsHitTesting(false)
        }
    }

    private func supprimer() {
        let photos = self.photos
        guard photos.indices.contains(index) else { return }
        let restantes = photos.count - 1
        contexte.delete(photos[index])
        if restantes == 0 { fermer() } else { index = min(index, restantes - 1) }
    }
}

/// Une photo de l'album à la taille de l'écran (pincer pour zoomer sur iPhone et iPad).
private struct PhotoEnGrand: View {
    let photo: Document
    @State private var image: CGImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var pincement: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .scaleEffect(zoom * pincement)
                    .gesture(MagnifyGesture()
                        .updating($pincement) { valeur, etat, _ in etat = valeur.magnification }
                        .onEnded { valeur in withAnimation(.snappy) { zoom = min(max(zoom * valeur.magnification, 1), 4) } })
                    .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = zoom > 1 ? 1 : 2.5 } }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.uid) {
            let donnees = photo.donnees, cle = photo.uid
            image = await Task.detached(priority: .userInitiated) { PhotoAlbum.vignette(donnees, cle: cle, cote: PhotoAlbum.coteMax) }.value
        }
    }
}
