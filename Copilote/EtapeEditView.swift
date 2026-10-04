import SwiftUI
import SwiftData

struct EtapeEditView: View {
    @Bindable var etape: Etape
    var jours: [Date]
    var onSupprimer: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titreActif: Bool

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
        .onAppear { if etape.titre.isEmpty { titreActif = true } }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}
