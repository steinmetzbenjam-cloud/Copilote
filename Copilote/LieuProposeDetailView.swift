import SwiftUI

struct LieuProposeDetailView: View {
    @State var lieu: LieuPropose
    var onAjouter: (LieuPropose) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !lieu.photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(lieu.photos, id: \.self) { url in
                                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                                        Color.secondary.opacity(0.15)
                                    }
                                    .frame(width: 280, height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lieu.nom).font(.title2.bold())
                        Text([lieu.genre, lieu.prix].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        if !lieu.adresse.isEmpty {
                            Label(lieu.adresse, systemImage: "mappin.and.ellipse").font(.subheadline)
                        }
                    }

                    NotesView(google: lieu.avis(de: .google).map { ($0.note, $0.nombre) },
                              tripadvisor: lieu.avis(de: .tripadvisor).map { ($0.note, $0.nombre) })
                    if let classement = lieu.classementTripadvisor {
                        Text(classement).font(.footnote).foregroundStyle(.secondary)
                    }

                    if let resume = lieu.resume {
                        Text(resume)
                    }

                    if !lieu.horaires.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Horaires").font(.headline)
                            ForEach(lieu.horaires, id: \.self) { Text($0).font(.footnote) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let url = lieu.siteWeb { Link("Site web", destination: url) }
                        ForEach(lieu.avis, id: \.source) { a in
                            if let url = a.lien { Link("Voir sur \(a.source.rawValue)", destination: url) }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Détails")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter à l'étape") { onAjouter(lieu) }
                }
            }
            .task { await completerPhotos() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// Les photos Tripadvisor demandent un appel de plus : on ne le fait qu'à l'ouverture de la fiche.
    private func completerPhotos() async {
        guard lieu.photos.isEmpty, let id = lieu.idTripadvisor, let cle = Cles.lire(.tripadvisor) else { return }
        lieu.photos = await SourceTripadvisor.photos(id: id, cle: cle)
    }
}
