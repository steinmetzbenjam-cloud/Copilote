import Foundation

/// Rapatrie les photos d'un lieu proposé pour les garder dans l'étape (hors ligne, et sans clé d'API dans les données).
enum PhotosLieu {
    struct Image {
        var donnees: Data
        var extensionFichier: String
    }

    static func telecharger(_ urls: [URL]) async -> [Image] {
        await withTaskGroup(of: (Int, Image?).self) { groupe in
            for (i, url) in urls.enumerated() {
                groupe.addTask { (i, await image(url)) }
            }
            var sortie: [(Int, Image)] = []
            for await (i, image) in groupe { if let image { sortie.append((i, image)) } }
            return sortie.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func image(_ url: URL) async -> Image? {
        guard let (donnees, reponse) = try? await URLSession.shared.data(from: url),
              let http = reponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !donnees.isEmpty, donnees.count < 10_000_000 else { return nil }
        let type = http.mimeType?.lowercased() ?? ""
        let extensionFichier = type.contains("png") ? "png" : (type.contains("webp") ? "webp" : (type.contains("heic") ? "heic" : "jpg"))
        return Image(donnees: donnees, extensionFichier: extensionFichier)
    }
}
