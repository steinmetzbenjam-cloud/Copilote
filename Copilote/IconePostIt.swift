import SwiftUI

/// Un petit post-it jaune au coin replié ; des lignes y sont écrites quand le jour a des notes.
struct IconePostIt: View {
    var ecrit: Bool
    var ouvert = false
    static let jaune = Color(red: 1.0, green: 0.86, blue: 0.35)

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, pli = w * 0.28
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: w, y: w - pli))
                    p.addLine(to: CGPoint(x: w - pli, y: w))
                    p.addLine(to: CGPoint(x: 0, y: w))
                    p.closeSubpath()
                }
                .fill(Self.jaune.opacity(ecrit || ouvert ? 1 : 0.55))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                Path { p in
                    p.move(to: CGPoint(x: w, y: w - pli))
                    p.addLine(to: CGPoint(x: w - pli, y: w - pli))
                    p.addLine(to: CGPoint(x: w - pli, y: w))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.85, green: 0.68, blue: 0.15).opacity(ecrit || ouvert ? 1 : 0.6))
                if ecrit {
                    VStack(alignment: .leading, spacing: w * 0.12) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(Color.black.opacity(0.4)).frame(width: w * (i == 2 ? 0.35 : 0.6), height: max(w * 0.06, 1.2))
                        }
                    }
                    .padding(.leading, w * 0.16).padding(.top, w * 0.2)
                }
            }
            .rotationEffect(.degrees(-4))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
