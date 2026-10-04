import SwiftUI
import SwiftData
import MapKit

struct EtapeEditView: View {
    @Bindable var etape: Etape
    var jours: [Date]
    var onSupprimer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titreActif: Bool
    @State private var rechercheOuverte = false
    @State private var suggestionsOuvertes = false
    @Environment(\.horizontalSizeClass) private var tailleHorizontale

    /// Écran large (iPad, Mac) : les idées s'affichent dans un panneau à droite de la fiche.
    private var panneauLateral: Bool {
        #if os(macOS)
        true
        #else
        tailleHorizontale == .regular
        #endif
    }

    private var heureActivee: Binding<Bool> {
        Binding(get: { etape.heure != nil },
                set: { etape.heure = $0 ? (etape.heure ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: etape.jour)) : nil })
    }

    private var heureChoisie: Binding<Date> {
        Binding(get: { etape.heure ?? etape.jour }, set: { etape.heure = $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            formulaire
            if suggestionsOuvertes && panneauLateral {
                Divider()
                SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { etape.appliquer($0) },
                                onFermer: { withAnimation { suggestionsOuvertes = false } })
                    .frame(minWidth: 380, idealWidth: 440, maxWidth: 480)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.default, value: suggestionsOuvertes)
        .sheet(isPresented: Binding(get: { suggestionsOuvertes && !panneauLateral }, set: { suggestionsOuvertes = $0 })) {
            SuggestionsView(voyage: etape.voyage, etape: etape, onChoix: { etape.appliquer($0) },
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
        .modifier(TailleDePage())
        #if os(macOS)
        .frame(minWidth: suggestionsOuvertes ? 940 : 420, minHeight: 520)
        #endif
    }

    private var formulaire: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $etape.titre)
                        .focused($titreActif)
                    TextField("Lieu ou adresse", text: $etape.lieu)
                    Button(etape.coordonnee == nil ? "Placer sur la carte" : "Changer de lieu",
                           systemImage: "magnifyingglass") { rechercheOuverte = true }
                    if let coord = etape.coordonnee {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800)),
                            interactionModes: []) {
                            Marker(etape.titre, systemImage: etape.categorie.symbole, coordinate: coord)
                        }
                        .id("\(coord.latitude),\(coord.longitude)")
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Retirer de la carte", systemImage: "mappin.slash", role: .destructive) {
                            etape.latitude = nil
                            etape.longitude = nil
                        }
                    }
                    Button("Idées de lieux à visiter", systemImage: "sparkles") { suggestionsOuvertes = true }
                    Picker("Catégorie", selection: $etape.categorie) {
                        ForEach(CategorieEtape.allCases) { c in
                            Label(c.libelle, systemImage: c.symbole).tag(c)
                        }
                    }
                }
                if etape.aDesInfosDeLieu { infosDuLieu }
                Section {
                    Picker("Jour", selection: $etape.jour) {
                        ForEach(jours, id: \.self) { j in
                            Text(j.formatted(.dateTime.weekday(.wide).day().month())).tag(j)
                        }
                    }
                    Toggle("Heure", isOn: heureActivee)
                    if etape.heure != nil {
                        DatePicker("À", selection: heureChoisie, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $etape.notes).frame(minHeight: 80)
                }
                Section {
                    Button("Supprimer l'étape", role: .destructive) {
                        onSupprimer()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Étape")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var infosDuLieu: some View {
        Section("Infos du lieu") {
            if let url = etape.photoURL.flatMap(URL.init) {
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
        }
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
