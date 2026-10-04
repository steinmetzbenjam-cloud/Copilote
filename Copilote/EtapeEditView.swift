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

    private var heureActivee: Binding<Bool> {
        Binding(get: { etape.heure != nil },
                set: { etape.heure = $0 ? (etape.heure ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: etape.jour)) : nil })
    }

    private var heureChoisie: Binding<Date> {
        Binding(get: { etape.heure ?? etape.jour }, set: { etape.heure = $0 })
    }

    var body: some View {
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
                    Picker("Catégorie", selection: $etape.categorie) {
                        ForEach(CategorieEtape.allCases) { c in
                            Label(c.libelle, systemImage: c.symbole).tag(c)
                        }
                    }
                }
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
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
