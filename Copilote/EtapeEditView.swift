import SwiftUI
import SwiftData
import MapKit

struct EtapeEditView: View {
    @Bindable var etape: Etape
    var jours: [Date]
    var onSupprimer: () -> Void
    /// Fiche ouverte dans un cadre posé sur la colonne des jours (Itinéraire) : fermée par ce rappel au lieu d'une feuille.
    var onFermer: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titreActif: Bool
    @State private var rechercheOuverte = false
    @State private var transportOuvert = false
    @State private var suggestionsOuvertes = false
    @State private var photosEnCours = false
    @Environment(\.horizontalSizeClass) private var tailleHorizontale

    private var enCadre: Bool { onFermer != nil }

    private func fermer() {
        if let onFermer { onFermer() } else { dismiss() }
    }

    /// Écran large (iPad, Mac) : les idées s'affichent dans un panneau à droite de la fiche.
    /// Dans un cadre, la place manque : elles restent dans une feuille.
    private var panneauLateral: Bool {
        #if os(macOS)
        !enCadre
        #else
        !enCadre && tailleHorizontale == .regular
        #endif
    }

    @State private var horaireOuvert = false

    /// Sans jour, l'étape n'a pas non plus d'horaires.
    private var jourChoisi: Binding<Date?> {
        Binding(get: { etape.jour },
                set: {
                    etape.jour = $0
                    // Un hébergement est toujours entre ce jour et le suivant.
                    if let jour = $0, etape.categorie == .hebergement, let voyage = etape.voyage { voyage.placerEntreJours(etape, apres: jour) }
                    if $0 == nil { etape.heure = nil; etape.heureFin = nil; etape.apresJour = false; horaireOuvert = false }
                })
    }

    private var horaireActive: Binding<Bool> {
        Binding(get: { horaireOuvert || etape.heure != nil || etape.heureFin != nil },
                set: {
                    horaireOuvert = $0
                    if !$0 { etape.heure = nil; etape.heureFin = nil }
                })
    }

    private func bulleHeure(_ valeur: Binding<Date?>, depart: Int) -> some View {
        BulleHeure(valeur: valeur, jour: etape.jour ?? .now, heureDeDepart: depart)
    }

    var body: some View {
        if enCadre {
            contenu
        } else {
            contenu
                .modifier(TailleDePage())
                #if os(macOS)
                .frame(minWidth: suggestionsOuvertes ? 940 : 420, minHeight: 520)
                #endif
        }
    }

    private var contenu: some View {
        HStack(spacing: 0) {
            formulaire
            if suggestionsOuvertes && panneauLateral {
                Divider()
                SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { valider($0) },
                                onFermer: { withAnimation { suggestionsOuvertes = false } })
                    .frame(minWidth: 380, idealWidth: 440, maxWidth: 480)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.default, value: suggestionsOuvertes)
        .sheet(isPresented: Binding(get: { suggestionsOuvertes && !panneauLateral }, set: { suggestionsOuvertes = $0 })) {
            SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { valider($0) },
                            onFermer: { suggestionsOuvertes = false })
        }
        .sheet(isPresented: $rechercheOuverte) {
            RechercheLieuView(requeteInitiale: etape.lieu.isEmpty ? etape.titre : etape.lieu,
                              pays: etape.voyage?.pays ?? []) { lieu in
                if etape.titre.trimmingCharacters(in: .whitespaces).isEmpty { etape.titre = lieu.nom }
                etape.lieu = lieu.adresse.isEmpty ? lieu.nom : "\(lieu.nom), \(lieu.adresse)"
                etape.latitude = lieu.coordonnee.latitude
                etape.longitude = lieu.coordonnee.longitude
            }
        }
        .onAppear { if etape.titre.isEmpty { titreActif = true } }
    }

    /// En tête de la fiche : l'ampoule des idées, le nom de l'étape au centre (on le modifie en cliquant dessus), puis fermer.
    private var entete: some View {
        HStack(spacing: 10) {
            // Idées de lieux à visiter : une ampoule allumée, au niveau du titre.
            Button { suggestionsOuvertes = true } label: {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: .yellow.opacity(0.7), radius: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Idées de lieux à visiter")
            .help("Idées de lieux à visiter")
            TextField(etape.categorie == .hebergement ? "Nom de l'hébergement" : "Nom de l'étape", text: $etape.titre)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .focused($titreActif)
                .onSubmit { titreActif = false }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4).padding(.horizontal, 6)
                // Un léger fond quand on écrit : on voit que le titre se modifie.
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(titreActif ? 0.12 : 0)))
                .help("Cliquer pour renommer")
            if enCadre {
                Button { fermer() } label: {
                    // Grande croix bien contrastée : on la trouve tout de suite pour fermer le détail.
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.secondary.opacity(0.22)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Fermer")
                .help("Fermer")
            } else {
                Button("OK") { fermer() }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 32)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    /// Dans un cadre comme dans une feuille : l'en-tête, puis les sections.
    private var formulaire: some View {
        VStack(spacing: 0) {
            entete
            Divider()
            champs
        }
        .background(FondDePage.couleur)
    }

    /// Le transport pour aller à cette étape : porté par l'élément qui la précède, ou l'aller pour la toute première.
    private func transportPourArriver(_ voyage: Voyage) -> (transport: Transport?, vue: TransportEditView)? {
        let nom = etape.titre.isEmpty ? "Étape" : etape.titre
        if let depart = voyage.precedente(de: etape) {
            return (depart.transport, TransportEditView(depart: depart, arrivee: etape))
        }
        guard voyage.elementsDuVoyage.first === etape else { return nil }
        let vue = TransportEditView(trajet: "Départ → \(nom)", jour: etape.jour ?? .now, coordonnees: nil,
                                    existant: voyage.transportAller, lieuxExtremites: true, voyage: voyage) { voyage.transportAller = $0 }
        return (voyage.transportAller, vue)
    }

    /// Les catégories proposées : transport et hébergement ont leur propre fenêtre, on ne les garde que pour une étape qui l'est déjà.
    private var categories: [CategorieEtape] {
        CategorieEtape.allCases.filter { ![.transport, .hebergement].contains($0) || $0 == etape.categorie }
    }

    /// Une petite tuile par catégorie, côte à côte ; la catégorie choisie est remplie de couleur.
    private var tuilesCategories: some View {
        FlowLayout(espacement: 6) {
            ForEach(categories) { c in
                let choisie = etape.categorie == c
                Button { withAnimation(.snappy) { etape.categorie = c } } label: {
                    Label(c.libelle, systemImage: c.symbole)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(choisie ? Color.white : Color.primary)
                        .background(Capsule().fill(choisie ? AnyShapeStyle(Color.purple) : AnyShapeStyle(FondDePage.carte)))
                        .overlay(Capsule().strokeBorder(Color.purple.opacity(choisie ? 0 : 0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choisie ? .isSelected : [])
            }
        }
    }

    private var champs: some View {
        ScrollView {
            VStack(spacing: 14) {
                if etape.categorie != .hebergement {
                    CadreSection("Catégorie", symbole: "square.grid.2x2", couleur: .purple) { tuilesCategories }
                }
                CadreSection("Jour et horaire", symbole: "calendar", couleur: .blue) {
                    LabeledContent("Jour") {
                        Picker("Jour", selection: jourChoisi) {
                            Text("Pas encore de jour").tag(Date?.none)
                            ForEach(jours, id: \.self) { j in
                                Text(j.formatted(.dateTime.weekday(.wide).day().month())).tag(Date?.some(j))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if etape.jour != nil, etape.categorie == .hebergement, etape.apresJour, let jour = etape.jour {
                        let lendemain = Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour
                        Text("Nuit du \(jour.formatted(.dateTime.day().month(.wide))) au \(lendemain.formatted(.dateTime.day().month(.wide)))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if etape.jour != nil { Toggle("Horaire", isOn: horaireActive) }
                    if etape.jour != nil, horaireActive.wrappedValue {
                        HStack {
                            Spacer()
                            bulleHeure($etape.heure, depart: 9)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            bulleHeure($etape.heureFin, depart: (etape.heure.map { Calendar.current.component(.hour, from: $0) + 1 } ?? 10) % 24)
                        }
                        // L'heure saisie est celle du lieu de l'étape ; on peut la noter dans un autre fuseau.
                        LigneFuseau(choisi: $etape.fuseauChoisi, parDefaut: etape.fuseauParDefaut,
                                    coordonnees: etape.coordonnee.map { [$0] } ?? [])
                    }
                }
                CadreSection("Budget", symbole: "eurosign.circle", couleur: .green) {
                    LignesPrix(voyage: etape.voyage,
                               adulte: $etape.prixAdulte, adulteLocal: $etape.prixAdulteLocal,
                               etudiant: $etape.prixEtudiant, etudiantLocal: $etape.prixEtudiantLocal,
                               enfant: $etape.prixEnfant, enfantLocal: $etape.prixEnfantLocal)
                    piedBudget(etape.voyage).font(.footnote).foregroundStyle(.secondary)
                }
                CadreSection("Lieu", symbole: "mappin.and.ellipse", couleur: .orange) {
                    TextField("Lieu ou adresse", text: $etape.lieu, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(FondDePage.carte))
                    if etape.coordonnee == nil {
                        Button("Placer sur la carte", systemImage: "magnifyingglass") { rechercheOuverte = true }
                    }
                    if let coord = etape.coordonnee {
                        // Dans un cadre, la grande carte à côté montre déjà le lieu.
                        if !enCadre {
                            Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800)),
                                interactionModes: []) {
                                Marker(etape.titre, systemImage: etape.categorie.symbole, coordinate: coord)
                            }
                            .id("\(coord.latitude),\(coord.longitude)")
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        HStack {
                            Button("Retirer de la carte", systemImage: "mappin.slash", role: .destructive) {
                                etape.latitude = nil
                                etape.longitude = nil
                            }
                            Spacer()
                            Button("Changer de lieu", systemImage: "magnifyingglass") { rechercheOuverte = true }
                        }
                    }
                    if let voyage = etape.voyage, let existant = transportPourArriver(voyage) {
                        Button(existant.transport == nil ? "Ajouter un transport" : "Modifier le transport", systemImage: "arrow.triangle.swap") {
                            transportOuvert = true
                        }
                        .sheet(isPresented: $transportOuvert) { existant.vue }
                    }
                }
                if etape.aDesInfosDeLieu { infosDuLieu }
                CadreSection("Notes", symbole: "note.text", couleur: .yellow) {
                    TextEditor(text: $etape.notes)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 80)
                        .background(RoundedRectangle(cornerRadius: 8).fill(FondDePage.carte))
                }
                // Qui a noté et qui a écrit quoi : le groupe donne son avis en préparation.
                if let voyage = etape.voyage, !voyage.avis(de: etape).isEmpty {
                    CadreSection("Avis du groupe", symbole: "star.bubble", couleur: .pink) {
                        ListeAvisEtape(voyage: voyage, etape: etape)
                    }
                }
                Button(etape.categorie == .hebergement ? "Supprimer l'hébergement" : "Supprimer l'étape", systemImage: "trash", role: .destructive) {
                    onSupprimer()
                    fermer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.borderless)
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .disabled(etape.voyage?.lectureSeule ?? false)
    }

    /// Valide un lieu proposé : l'étape reprend titre, adresse, position, notes, et on rapatrie les photos.
    private func valider(_ lieu: LieuPropose) {
        etape.appliquer(lieu)
        let urls = Array(lieu.photos.prefix(6))
        guard !urls.isEmpty else { return }
        photosEnCours = true
        Task { @MainActor in
            let images = await PhotosLieu.telecharger(urls)
            rangerPhotos(images, de: lieu)
            photosEnCours = false
        }
    }

    @MainActor private func rangerPhotos(_ images: [PhotosLieu.Image], de lieu: LieuPropose) {
        guard let contexte = etape.modelContext, let voyage = etape.voyage else { return }
        for ancienne in etape.photos where ancienne.nom.hasPrefix("\(lieu.nom) – photo") { contexte.delete(ancienne) }
        for (i, image) in images.enumerated() {
            let photo = Document(nom: "\(lieu.nom) – photo \(i + 1)", extensionFichier: image.extensionFichier, donnees: image.donnees)
            photo.voyage = voyage
            photo.etape = etape
            contexte.insert(photo)
        }
    }

    private var infosDuLieu: some View {
        CadreSection("Infos du lieu", symbole: "info.circle", couleur: .teal) {
            if !etape.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(etape.photos.sorted { $0.nom < $1.nom }) { photo in
                            ImageDonnees(donnees: photo.donnees)
                                .frame(width: 220, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .contextMenu {
                                    Button("Supprimer la photo", systemImage: "trash", role: .destructive) { etape.modelContext?.delete(photo) }
                                }
                        }
                    }
                }
            } else if let url = etape.photoURL.flatMap(URL.init) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            NotesView(google: etape.noteGoogle.flatMap { n in etape.avisGoogle.map { (n, $0) } },
                      tripadvisor: etape.noteTripadvisor.flatMap { n in etape.avisTripadvisor.map { (n, $0) } })
            if let resume = etape.resume { Text(resume).font(.callout) }
            if let horaires = etape.horaires {
                DisclosureGroup("Horaires") { Text(horaires).font(.footnote) }
            }
            if let url = etape.siteWeb.flatMap(URL.init) { Link("Site web", destination: url) }
            if let url = etape.lienGoogle.flatMap(URL.init) { Link("Voir sur Google", destination: url) }
            if let url = etape.lienTripadvisor.flatMap(URL.init) { Link("Voir sur Tripadvisor", destination: url) }
            Link("Chercher des vidéos", destination: Etape.lienVideos(pour: etape.titre.isEmpty ? etape.lieu : etape.titre))
            if photosEnCours {
                Label("Téléchargement des photos…", systemImage: "arrow.down.circle").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Une section de la fiche : un cadre teinté et bordé de sa couleur, avec son titre et son icône.
private struct CadreSection<Contenu: View>: View {
    let titre: String
    let symbole: String
    let couleur: Color
    @ViewBuilder let contenu: Contenu

    init(_ titre: String, symbole: String, couleur: Color, @ViewBuilder contenu: () -> Contenu) {
        self.titre = titre
        self.symbole = symbole
        self.couleur = couleur
        self.contenu = contenu()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titre, systemImage: symbole)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(couleur)
            contenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Fond de carte surélevé puis teinte de la section : chaque partie ressort, même en mode sombre.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FondDePage.carte)
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(couleur.opacity(0.16))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(couleur.opacity(0.75), lineWidth: 1.5))
    }
}

/// iPad : fenêtre plus large pour loger la fiche et le panneau d'idées côte à côte.
private struct TailleDePage: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}


/// Bulle d'heure : vide tant qu'on n'a rien choisi. Un toucher ouvre le choix de l'heure ; rien n'est enregistré avant « OK ».
struct BulleHeure: View {
    @Binding var valeur: Date?
    let jour: Date
    let heureDeDepart: Int
    @State private var ouvert = false
    @State private var brouillon = Date()

    var body: some View {
        if let date = valeur {
            DatePicker("", selection: Binding(get: { date }, set: { valeur = $0 }), displayedComponents: .hourAndMinute)
                .labelsHidden()
        } else {
            Button {
                brouillon = Calendar.current.date(bySettingHour: heureDeDepart, minute: 0, second: 0, of: jour) ?? jour
                ouvert = true
            } label: {
                Text("--:--")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $ouvert) {
                VStack(spacing: 8) {
                    DatePicker("", selection: $brouillon, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        #if os(iOS)
                        .datePickerStyle(.wheel)
                        #else
                        .datePickerStyle(.graphical)
                        #endif
                    Button("OK") { valeur = brouillon; ouvert = false }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}
