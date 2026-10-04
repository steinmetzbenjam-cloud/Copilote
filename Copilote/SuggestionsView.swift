import SwiftUI
import MapKit

struct SuggestionsView: View {
    var voyage: Voyage?
    var etape: Etape
    var onChoix: (LieuPropose) -> Void
    var onFermer: () -> Void

    @State private var type: TypeLieu
    @State private var mots: String
    @State private var autour = ""
    @State private var centre: CLLocationCoordinate2D?
    @State private var resultat: Suggestions.Resultat?
    @State private var enCours = false
    @State private var reglagesOuverts = false
    @State private var detail: LieuPropose?

    init(voyage: Voyage?, etape: Etape, onChoix: @escaping (LieuPropose) -> Void, onFermer: @escaping () -> Void) {
        self.voyage = voyage
        self.etape = etape
        self.onChoix = onChoix
        self.onFermer = onFermer
        _type = State(initialValue: etape.categorie == .repas ? .restaurant : .activite)
        _mots = State(initialValue: Self.motsCles(de: etape))
    }

    /// Le titre de l'étape, sinon le nom du lieu (avant la première virgule de l'adresse).
    static func motsCles(de etape: Etape) -> String {
        let titre = etape.titre.trimmingCharacters(in: .whitespaces)
        if !titre.isEmpty { return titre }
        return etape.lieu.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private var aDesCles: Bool { Cles.lire(.google) != nil || Cles.lire(.tripadvisor) != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(TypeLieu.allCases) { Label($0.libelle, systemImage: $0.symbole).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField("Mot-clé (musée, plage, sushi…)", text: $mots)
                        .onSubmit { Task { await relancer(depuisTexte: false) } }
                        .autocorrectionDisabled()
                    TextField("Autour de… (ville, quartier)", text: $autour)
                        .onSubmit { Task { await relancer(depuisTexte: true) } }
                        .autocorrectionDisabled()
                }

                if !aDesCles {
                    Section {
                        Button("Ajouter mes clés Google et Tripadvisor", systemImage: "key.fill") { reglagesOuverts = true }
                    } footer: {
                        Text("Sans clé, les idées viennent de Plans, sans notes ni classement.")
                    }
                }

                if let resultat {
                    ForEach(resultat.avertissements, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Section {
                        ForEach(resultat.lieux) { lieu in
                            Button { detail = lieu } label: { ligne(lieu) }.buttonStyle(.plain)
                        }
                    } footer: {
                        if !resultat.lieux.isEmpty {
                            Text((resultat.sansNotes ? "Source : Plans (sans notes). " : "Classé selon les notes et le nombre d'avis Google et Tripadvisor. ")
                                 + (mots.isEmpty ? "" : "Ceux qui correspondent à « \(mots) » sont en premier."))
                        }
                    }
                }
            }
            .overlay {
                if centre == nil && !enCours {
                    ContentUnavailableView("Où chercher ?", systemImage: "mappin.slash",
                                           description: Text("Écris une ville dans « Autour de… », ou choisis le pays du voyage dans Infos."))
                } else if enCours && resultat == nil { ProgressView() }
                else if let resultat, resultat.lieux.isEmpty, !enCours {
                    ContentUnavailableView("Aucune idée trouvée", systemImage: "magnifyingglass",
                                           description: Text("Essaie une autre ville dans « Autour de… »."))
                }
            }
            .navigationTitle("Idées de lieux")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer", action: onFermer) }
                ToolbarItem { Button("Réglages", systemImage: "key") { reglagesOuverts = true } }
            }
            .task { await preparer() }
            .onChange(of: type) { Task { await relancer(depuisTexte: false) } }
            .sheet(isPresented: $reglagesOuverts, onDismiss: { Task { await relancer(depuisTexte: false) } }) { ReglagesView() }
            .navigationDestination(item: $detail) { lieu in
                LieuProposeDetailView(lieu: lieu) { choisi in
                    onChoix(choisi)
                    detail = nil
                    onFermer()
                }
            }
        }
    }

    private func ligne(_ lieu: LieuPropose) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PhotoLieu(url: lieu.photos.first, taille: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(lieu.nom).font(.headline).foregroundStyle(.primary)
                NotesView(google: lieu.avis(de: .google).map { ($0.note, $0.nombre) },
                          tripadvisor: lieu.avis(de: .tripadvisor).map { ($0.note, $0.nombre) })
                Text([lieu.genre, lieu.prix].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !lieu.adresse.isEmpty {
                    Text(lieu.adresse).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Point de départ : le lieu de l'étape, sinon les étapes du jour, sinon la destination du voyage.
    private func preparer() async {
        if autour.isEmpty {
            autour = voyage?.destination.isEmpty == false ? voyage!.destination : ""
        }
        if let c = etape.coordonnee {
            centre = c
            if autour.isEmpty { autour = etape.lieu }
        } else if let voyage, let c = Self.centroide(voyage.etapes(du: etape.jour).compactMap(\.coordonnee)) {
            centre = c
        } else if !autour.isEmpty {
            centre = await Self.geocoder(autour, pays: voyage?.pays ?? [])
        } else if let region = await Pays.regionCarte(pour: voyage?.pays ?? []) {
            centre = region.center
        }
        if autour.isEmpty, let c = centre { autour = await Self.nomDuLieu(c) ?? "" }
        await relancer(depuisTexte: false)
    }

    private func relancer(depuisTexte: Bool) async {
        if depuisTexte || centre == nil, !autour.trimmingCharacters(in: .whitespaces).isEmpty {
            centre = await Self.geocoder(autour, pays: voyage?.pays ?? []) ?? centre
        }
        guard let centre else { return }
        enCours = true
        resultat = await Suggestions.chercher(type: type, autour: autour.isEmpty ? "ici" : autour, centre: centre,
                                              mots: mots.trimmingCharacters(in: .whitespaces))
        enCours = false
    }

    static func centroide(_ points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        return CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                      longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
    }

    static func geocoder(_ texte: String, pays: [String]) async -> CLLocationCoordinate2D? {
        let requete = MKLocalSearch.Request()
        requete.naturalLanguageQuery = texte
        if let code = pays.first, let region = await Pays.region(de: code) { requete.region = region }
        return try? await MKLocalSearch(request: requete).start().mapItems.first?.placemark.coordinate
    }

    static func nomDuLieu(_ c: CLLocationCoordinate2D) async -> String? {
        let marques = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude))
        return marques?.first?.locality ?? marques?.first?.administrativeArea
    }
}
