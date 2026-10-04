import SwiftUI

/// Petite ligne de notes : ★ 4,6 Google (1 234) · ★ 4,5 Tripadvisor (890).
struct NotesView: View {
    var google: (note: Double, nombre: Int)?
    var tripadvisor: (note: Double, nombre: Int)?

    var body: some View {
        HStack(spacing: 10) {
            if let g = google { puce("Google", g.note, g.nombre, .blue) }
            if let t = tripadvisor { puce("Tripadvisor", t.note, t.nombre, .green) }
        }
        .font(.caption)
    }

    private func puce(_ nom: String, _ note: Double, _ nombre: Int, _ couleur: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").foregroundStyle(.orange)
            Text(note.formatted(.number.precision(.fractionLength(1)))).bold()
            Text("\(nom) (\(nombre.formatted()))").foregroundStyle(.secondary)
        }
    }
}

struct PhotoLieu: View {
    var url: URL?
    var taille: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
