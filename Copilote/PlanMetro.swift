import SwiftUI
import SwiftData

/// Un plan trouvé sur Wikimedia Commons.
struct PlanTrouve: Identifiable {
    let id: String
    var titre: String
    var miniature: URL
    var page: URL?
    var licence: String
    var auteur: String
    var mime: String
}

/// Recherche de plans de métro sur Wikimedia Commons (fichiers sous licence libre), sans clé.
enum RecherchePlans {
    private static func nettoyer(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#039;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requete(_ parametres: [String: String]) async -> [String: Any]? {
        var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        c.queryItems = parametres.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "format", value: "json")]
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url)
        r.setValue("Copilote/1.0 (application de voyage)", forHTTPHeaderField: "User-Agent")
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: r), (reponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
    }

    private static func lire(_ page: [String: Any]) -> (PlanTrouve, Int)? {
        guard let titre = page["title"] as? String, let info = (page["imageinfo"] as? [[String: Any]])?.first,
              let miniature = (info["thumburl"] as? String).flatMap(URL.init(string:)) else { return nil }
        let mime = info["mime"] as? String ?? ""
        guard ["image/svg+xml", "image/png", "image/jpeg"].contains(mime) else { return nil }
        let meta = info["extmetadata"] as? [String: Any]
        func valeur(_ cle: String) -> String { ((meta?[cle] as? [String: Any])?["value"] as? String).map(nettoyer) ?? "" }
        let nom = titre.replacingOccurrences(of: "File:", with: "").split(separator: ".").dropLast().joined(separator: ".")
        return (PlanTrouve(id: titre, titre: nom.isEmpty ? titre : nom, miniature: miniature,
                           page: (info["descriptionurl"] as? String).flatMap(URL.init(string:)),
                           licence: valeur("LicenseShortName"), auteur: valeur("Artist"), mime: mime),
                (page["index"] as? Int) ?? 99)
    }

    static func chercher(_ ville: String) async -> [PlanTrouve] {
        let nom = ville.trimmingCharacters(in: .whitespaces)
        guard !nom.isEmpty else { return [] }
        var trouves: [String: (PlanTrouve, Int)] = [:]
        for (rang, recherche) in ["\(nom) metro map", "\(nom) subway map", "plan métro \(nom)"].enumerated() {
            let json = await requete([
                "action": "query", "generator": "search", "gsrsearch": recherche, "gsrnamespace": "6", "gsrlimit": "10",
                "prop": "imageinfo", "iiprop": "url|mime|extmetadata", "iiurlwidth": "420",
            ])
            let pages = (json?["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] ?? [:]
            for page in pages.values {
                if let (plan, index) = lire(page), trouves[plan.id] == nil { trouves[plan.id] = (plan, rang * 100 + index) }
            }
        }
        // On garde d'abord ce qui ressemble à un plan (« map », « plan », « network »…), les photos de rames viennent après.
        func estUnPlan(_ p: PlanTrouve) -> Bool {
            let t = p.titre.lowercased()
            return ["map", "plan", "mapa", "carte", "network", "diagram", "route", "lines", "schema", "schéma"].contains { t.contains($0) }
        }
        // Les schémas de voies d'une seule station ne sont pas des plans de réseau.
        func bruit(_ p: PlanTrouve) -> Bool { let t = p.titre.lowercased(); return t.contains("rail tracks") || t.contains("track map") }
        func note(_ p: PlanTrouve) -> Int { (estUnPlan(p) ? 0 : 2) + (p.mime == "image/svg+xml" ? 0 : 1) + (bruit(p) ? 4 : 0) }
        let tries = trouves.values.sorted { (note($0.0), $0.1) < (note($1.0), $1.1) }.map(\.0)
        let plans = tries.filter(estUnPlan)
        return Array((plans.count >= 3 ? plans : tries).prefix(18))
    }

    /// Le plan en grande taille (2 600 px de large), prêt à être gardé dans le voyage.
    static func telecharger(_ plan: PlanTrouve) async -> (Data, String)? {
        let json = await requete(["action": "query", "titles": plan.id, "prop": "imageinfo", "iiprop": "url|mime", "iiurlwidth": "2600"])
        guard let page = ((json?["query"] as? [String: Any])?["pages"] as? [String: [String: Any]])?.values.first,
              let info = (page["imageinfo"] as? [[String: Any]])?.first,
              let url = (info["thumburl"] as? String ?? info["url"] as? String).flatMap(URL.init(string:)) else { return nil }
        var r = URLRequest(url: url)
        r.setValue("Copilote/1.0 (application de voyage)", forHTTPHeaderField: "User-Agent")
        guard let (donnees, reponse) = try? await URLSession.shared.data(for: r), (reponse as? HTTPURLResponse)?.statusCode == 200,
              donnees.count < 30_000_000 else { return nil }
        let png = (reponse.mimeType ?? "").contains("png") || url.pathExtension.lowercased() == "png"
        return (donnees, png ? "png" : "jpg")
    }
}

extension Voyage {
    var plansDeMetro: [Document] { documents.filter { $0.typeBrut == TypeDocument.planMetro.rawValue }.sorted { $0.creeLe < $1.creeLe } }
}

/// Cherche le plan du métro d'une ville et l'ajoute au voyage.
struct PlanMetroView: View {
    var voyage: Voyage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var contexte
    @State private var ville: String
    @State private var resultats: [PlanTrouve] = []
    @State private var enRecherche = false
    @State private var dejaCherche = false
    @State private var ajoutEnCours: String?
    @State private var message: String?

    init(voyage: Voyage) {
        self.voyage = voyage
        _ville = State(initialValue: voyage.destination)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Ville (Tokyo, Paris, Lisbonne…)", text: $ville).textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await chercher() } }
                        Button(enRecherche ? "Recherche…" : "Chercher") { Task { await chercher() } }
                            .buttonStyle(.borderedProminent).disabled(enRecherche || ville.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
                    if dejaCherche && resultats.isEmpty && !enRecherche {
                        ContentUnavailableView("Aucun plan trouvé", systemImage: "map",
                                               description: Text("Essaie le nom de la ville en anglais, ou cherche le plan officiel sur le site du réseau."))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(resultats) { carte($0) }
                    }
                    if let lien = URL(string: "https://www.google.com/search?tbm=isch&q=" + ("plan métro " + ville).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
                        Link(destination: lien) { Label("Chercher le plan officiel sur le web", systemImage: "safari") }
                    }
                    Text("Les plans viennent de Wikimedia Commons : fichiers sous licence libre. La source, l'auteur et la licence sont gardés avec le plan. Une fois ajouté, il s'ouvre sans connexion.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("Plan du métro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task {
                if !ville.isEmpty, !dejaCherche { await chercher() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 600)
        #endif
    }

    private func carte(_ plan: PlanTrouve) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: plan.miniature) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().frame(maxWidth: .infinity, minHeight: 110)
            }
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(plan.titre).font(.footnote.weight(.semibold)).lineLimit(2)
            Text([plan.licence, plan.auteur].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Button {
                Task { await ajouter(plan) }
            } label: {
                Label(ajoutEnCours == plan.id ? "Ajout…" : "Ajouter au voyage", systemImage: "plus.circle.fill").font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(ajoutEnCours != nil || voyage.lectureSeule)
        }
        .padding(10)
        .modifier(FondDeCarte())
    }

    private func chercher() async {
        enRecherche = true
        message = nil
        resultats = await RecherchePlans.chercher(ville)
        dejaCherche = true
        enRecherche = false
        if resultats.isEmpty, !Reseau.shared.enLigne { message = "Pas de connexion : la recherche demande le réseau." }
    }

    private func ajouter(_ plan: PlanTrouve) async {
        ajoutEnCours = plan.id
        defer { ajoutEnCours = nil }
        guard let (donnees, extension_) = await RecherchePlans.telecharger(plan) else {
            message = "Impossible de télécharger ce plan. Réessaie, ou choisis-en un autre."
            return
        }
        let doc = Document(nom: "Plan du métro – \(ville.trimmingCharacters(in: .whitespaces)) (\(plan.titre))", extensionFichier: extension_, donnees: donnees)
        doc.voyage = voyage
        doc.type = .planMetro
        doc.notes = "Source : Wikimedia Commons" + (plan.page.map { " — \($0.absoluteString)" } ?? "")
            + (plan.auteur.isEmpty ? "" : " — Auteur : \(plan.auteur)") + (plan.licence.isEmpty ? "" : " — Licence : \(plan.licence)")
        contexte.insert(doc)
        dismiss()
    }
}

/// Les plans de métro gardés dans le voyage, avec leur source.
struct CadrePlansMetro: View {
    @Bindable var voyage: Voyage
    @Environment(\.modelContext) private var contexte
    @State private var recherche = false
    @State private var apercu: FichierAApercevoir?

    var body: some View {
        CadreInfos(titre: "Plans de métro", symbole: "map.fill", couleur: .teal,
                   pied: "Gardés dans le voyage : ils s'ouvrent sans connexion, avec zoom.") {
            ForEach(voyage.plansDeMetro) { doc in
                HStack(spacing: 10) {
                    Button { ouvrir(doc) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "map.fill").foregroundStyle(.white).frame(width: 32, height: 32).background(Circle().fill(Color.teal))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(doc.nom).foregroundStyle(.primary).lineLimit(2)
                                if let notes = doc.notes { Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if !voyage.lectureSeule {
                        Button("Supprimer", systemImage: "trash") { contexte.delete(doc) }
                            .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
            if voyage.plansDeMetro.isEmpty { Text("Aucun plan pour l'instant.").foregroundStyle(.secondary) }
            Button("Ajouter le plan d'une ville", systemImage: "plus.circle") { recherche = true }
                .buttonStyle(.borderless).disabled(voyage.lectureSeule)
        }
        .sheet(isPresented: $recherche) { PlanMetroView(voyage: voyage) }
        .sheet(item: $apercu) { ApercuDocumentView(fichier: $0) }
    }

    private func ouvrir(_ doc: Document) {
        if let url = try? doc.urlTemporaire() { apercu = FichierAApercevoir(url: url, titre: doc.nom) }
    }
}
