import SwiftUI
import SwiftData

/// Fiche d'une journée : titre, lieux autour desquels elle se passe, notes.
struct JourEditView: View {
    @Bindable var jour: JourVoyage
    var voyage: Voyage
    var numero: Int

    @Environment(\.dismiss) private var dismiss
    @State private var rechercheOuverte = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. Arrivée à San José)", text: $jour.titre)
                } header: {
                    Text("Jour \(numero) · \(jour.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                }

                Section {
                    ForEach(jour.lieux) { lieu in
                        HStack {
                            Image(systemName: lieu.estPays ? "flag.fill" : "mappin.circle.fill").foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lieu.etiquette)
                                if !lieu.detail.isEmpty {
                                    Text(lieu.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button("Retirer", systemImage: "xmark.circle.fill") { jour.lieux.removeAll { $0.id == lieu.id } }
                                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Button("Chercher un lieu, une ville, une région…", systemImage: "magnifyingglass") { rechercheOuverte = true }
                    if !voyage.pays.isEmpty {
                        Menu {
                            ForEach(voyage.pays.compactMap { Pays.avec(code: $0) }) { pays in
                                Button("\(pays.drapeau) \(pays.nom)") { Task { await ajouter(pays: pays) } }
                            }
                        } label: {
                            Label("Ajouter un pays du voyage", systemImage: "flag")
                        }
                    }
                } header: {
                    Text("Où se passe la journée ?")
                } footer: {
                    Text("Un pays, une région, une ville ou un endroit précis, un ou plusieurs. Les idées de lieux et la carte se centrent dessus.")
                }

                Section("Notes") {
                    TextEditor(text: $jour.notes).frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Jour \(numero)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .sheet(isPresented: $rechercheOuverte) {
                RechercheLieuView(requeteInitiale: "", pays: voyage.pays, invite: "Pays, région, ville, lieu précis…") { trouve in
                    ajouter(trouve)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 540)
        #endif
    }

    private func normaliser(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    private func ajouter(_ trouve: LieuTrouve) {
        let pays = trouve.codePays.flatMap { Pays.avec(code: $0) }
        let estPays = pays.map { normaliser($0.nom) == normaliser(trouve.nom) } ?? false
        let adresse = trouve.adresse == trouve.nom ? "" : trouve.adresse
        jour.lieux.append(LieuReference(nom: trouve.nom, detail: adresse, latitude: trouve.coordonnee.latitude,
                                        longitude: trouve.coordonnee.longitude, codePays: trouve.codePays, estPays: estPays))
    }

    private func ajouter(pays: Pays) async {
        guard let region = await Pays.region(de: pays.code) else { return }
        jour.lieux.append(LieuReference(nom: pays.nom, latitude: region.center.latitude, longitude: region.center.longitude,
                                        codePays: pays.code, estPays: true))
    }
}
