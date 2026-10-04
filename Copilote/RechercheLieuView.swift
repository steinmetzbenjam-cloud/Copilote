import SwiftUI
import MapKit

struct LieuTrouve {
    var nom: String
    var adresse: String
    var coordonnee: CLLocationCoordinate2D
}

/// Suggestions de Plans au fil de la frappe.
@Observable
final class RechercheLieux: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [MKLocalSearchCompletion] = []
    var erreur: String?
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func chercher(_ texte: String) {
        erreur = nil
        if texte.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = []
        } else {
            completer.queryFragment = texte
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        erreur = error.localizedDescription
    }

    func resoudre(_ suggestion: MKLocalSearchCompletion) async -> LieuTrouve? {
        let requete = MKLocalSearch.Request(completion: suggestion)
        guard let item = try? await MKLocalSearch(request: requete).start().mapItems.first else { return nil }
        return LieuTrouve(nom: suggestion.title,
                          adresse: suggestion.subtitle,
                          coordonnee: item.placemark.coordinate)
    }
}

struct RechercheLieuView: View {
    var requeteInitiale: String
    var onChoix: (LieuTrouve) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recherche = RechercheLieux()
    @State private var texte = ""
    @State private var enCours = false
    @FocusState private var champActif: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Musée, restaurant, adresse…", text: $texte)
                            .focused($champActif)
                            .autocorrectionDisabled()
                        if !texte.isEmpty {
                            Button("Effacer", systemImage: "xmark.circle.fill") {
                                texte = ""
                                champActif = true
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let erreur = recherche.erreur, !texte.isEmpty {
                    Text(erreur).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(recherche.suggestions, id: \.self) { s in
                        Button { choisir(s) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).foregroundStyle(.primary)
                                if !s.subtitle.isEmpty {
                                    Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay { if enCours { ProgressView() } }
            .navigationTitle("Chercher un lieu")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .onChange(of: texte) { _, nouveau in recherche.chercher(nouveau) }
            .onAppear {
                texte = requeteInitiale
                champActif = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    private func choisir(_ suggestion: MKLocalSearchCompletion) {
        enCours = true
        Task {
            if let lieu = await recherche.resoudre(suggestion) {
                onChoix(lieu)
                dismiss()
            }
            enCours = false
        }
    }
}
