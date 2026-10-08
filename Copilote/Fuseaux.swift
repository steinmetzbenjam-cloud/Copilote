import SwiftUI
import MapKit
import CoreLocation
import Observation

// MARK: - Affichage d'un fuseau

extension TimeZone {
    /// « Tokyo », « Costa Rica », « Buenos Aires » : le nom de la ville ou de la région du fuseau.
    var ville: String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// « UTC+9 », « UTC−6 », « UTC+5:30 ».
    func decalage(le date: Date = .now) -> String {
        let s = secondsFromGMT(for: date)
        let h = abs(s) / 3600, m = (abs(s) % 3600) / 60
        return "UTC" + (s < 0 ? "−" : "+") + (m == 0 ? "\(h)" : "\(h):\(String(format: "%02d", m))")
    }

    var libelle: String { "\(ville) (\(decalage()))" }
}

// MARK: - Fuseau d'un lieu

/// Le fuseau horaire d'un lieu, trouvé avec ses coordonnées (Plans) puis gardé : les mêmes lieux ne sont jamais redemandés.
@MainActor @Observable
final class FuseauxHoraires {
    static let shared = FuseauxHoraires()
    private(set) var cache: [String: String]
    @ObservationIgnored private var enCours: Set<String> = []
    @ObservationIgnored private let cleStockage = "fuseauxDesLieux"

    private init() {
        cache = UserDefaults.standard.dictionary(forKey: "fuseauxDesLieux") as? [String: String] ?? [:]
    }

    /// Les lieux à moins de 0,2° (environ 20 km) partagent le même fuseau.
    static func cle(_ c: CLLocationCoordinate2D) -> String { String(format: "%.1f,%.1f", (c.latitude * 5).rounded() / 5, (c.longitude * 5).rounded() / 5) }

    func fuseau(_ c: CLLocationCoordinate2D) -> TimeZone? {
        cache[Self.cle(c)].flatMap(TimeZone.init(identifier:))
    }

    func charger(_ c: CLLocationCoordinate2D) async {
        let cle = Self.cle(c)
        guard cache[cle] == nil, !enCours.contains(cle) else { return }
        enCours.insert(cle)
        defer { enCours.remove(cle) }
        let lieu = CLLocation(latitude: c.latitude, longitude: c.longitude)
        if let zone = (try? await CLGeocoder().reverseGeocodeLocation(lieu))?.first?.timeZone {
            cache[cle] = zone.identifier
            UserDefaults.standard.set(cache, forKey: cleStockage)
        }
    }
}

// MARK: - Fuseaux des étapes et des transports

extension Voyage {
    /// Le fuseau du voyage quand rien de plus précis n'est connu : celui du centre de ses étapes localisées.
    @MainActor var fuseauParDefaut: TimeZone? {
        let points = etapes.compactMap(\.coordonnee)
        guard !points.isEmpty else { return nil }
        let centre = CLLocationCoordinate2D(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                            longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
        return FuseauxHoraires.shared.fuseau(centre)
    }

    /// Les fuseaux de départ et d'arrivée d'un transport : ceux choisis à la main, sinon ceux des lieux.
    @MainActor func fuseaux(de transport: Transport, depuis depart: Etape?, vers arrivee: Etape?) -> (depart: TimeZone, arrivee: TimeZone) {
        let ref = fuseauxParDefaut(de: transport, depuis: depart, vers: arrivee)
        let d = transport.fuseauDepart.flatMap(TimeZone.init(identifier:)) ?? ref.depart
        let a = transport.fuseauArrivee.flatMap(TimeZone.init(identifier:)) ?? ref.arrivee
        return (d, a)
    }

    /// Les fuseaux des lieux, sans tenir compte d'un choix manuel.
    @MainActor func fuseauxParDefaut(de transport: Transport, depuis depart: Etape?, vers arrivee: Etape?) -> (depart: TimeZone, arrivee: TimeZone) {
        let cache = FuseauxHoraires.shared
        let d = transport.departCoordonnee.flatMap(cache.fuseau) ?? depart?.fuseau ?? fuseauParDefaut ?? .current
        let a = transport.arriveeCoordonnee.flatMap(cache.fuseau) ?? arrivee?.fuseau ?? d
        return (d, a)
    }

    /// Le fuseau d'un jour : celui du lieu de sa première étape (l'heure locale du pays visité), sans tenir compte d'un fuseau choisi pour une heure saisie.
    @MainActor func fuseau(du jour: Date) -> TimeZone {
        etapes(du: jour).first?.fuseauParDefaut ?? fuseauParDefaut ?? .current
    }
}

extension Etape {
    /// Le fuseau des horaires de l'étape : celui choisi, sinon celui du lieu, sinon celui du voyage.
    @MainActor var fuseau: TimeZone {
        fuseauChoisi.flatMap(TimeZone.init(identifier:))
            ?? coordonnee.flatMap(FuseauxHoraires.shared.fuseau)
            ?? voyage?.fuseauParDefaut
            ?? .current
    }

    @MainActor var fuseauParDefaut: TimeZone {
        coordonnee.flatMap(FuseauxHoraires.shared.fuseau) ?? voyage?.fuseauParDefaut ?? .current
    }

    /// Le moment réel du début de l'étape, l'heure saisie étant l'heure locale de son fuseau.
    @MainActor var dateHeure: Date? {
        guard let jour, let heure else { return nil }
        return Horaires.instant(jour: jour, heure: heure, zone: fuseau)
    }
}

extension Etape {
    /// L'heure saisie pour cette étape, convertie en heure locale du lieu visité ce jour-là (avec le décalage de jour éventuel).
    @MainActor func enHeureLocale(_ heure: Date) -> (date: Date, jours: Int) {
        guard let jour, let voyage else { return (heure, 0) }
        return Horaires.convertir(heure, jour: jour, de: fuseau, vers: voyage.fuseau(du: jour))
    }

    /// « 13:00 », ou « 03:30 (+1 j) » quand la conversion change de jour.
    @MainActor func heureAffichee(_ heure: Date) -> String {
        let r = enHeureLocale(heure)
        let suffixe = r.jours > 0 ? " (+\(r.jours) j)" : (r.jours < 0 ? " (\(r.jours) j)" : "")
        return r.date.formatted(date: .omitted, time: .shortened) + suffixe
    }
}

extension Voyage {
    /// Le résumé d'un transport avec ses heures converties en heure locale du lieu visité (jour du départ).
    @MainActor func descriptifLocal(_ t: Transport, depuis depart: Etape?, vers arrivee: Etape?) -> String {
        guard let d = t.depart else { return t.descriptif }
        let jourDepart = depart?.jour.map { jour in depart?.apresJour == true ? (Calendar.current.date(byAdding: .day, value: 1, to: jour) ?? jour) : jour }
            ?? arrivee?.jour ?? jours.first ?? .now
        let z = fuseaux(de: t, depuis: depart, vers: arrivee)
        let local = fuseau(du: jourDepart)
        let debut = Horaires.convertir(d, jour: jourDepart, de: z.depart, vers: local)
        var heures = debut.date.formatted(date: .omitted, time: .shortened)
        if let a = t.arrivee {
            if let duree = Horaires.duree(t, jour: jourDepart, depart: z.depart, arrivee: z.arrivee) {
                let fin = debut.date.addingTimeInterval(duree)
                let cal = Calendar.current
                let jours = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: fin)).day ?? 0
                heures += " → " + fin.formatted(date: .omitted, time: .shortened) + (jours > 0 ? " (+\(jours) j)" : "")
            } else {
                heures += " → " + Horaires.convertir(a, jour: jourDepart, de: z.arrivee, vers: local).date.formatted(date: .omitted, time: .shortened)
            }
        }
        return t.descriptif(avecHoraires: false) + " · " + heures
    }
}

enum Horaires {
    /// Une heure saisie dans `zone`, exprimée en heure du fuseau `local` : la date retournée se lit directement avec le fuseau de l'app.
    /// `jours` : décalage de jour du résultat par rapport au jour de saisie.
    static func convertir(_ heure: Date, jour: Date, de zone: TimeZone, vers local: TimeZone) -> (date: Date, jours: Int) {
        guard zone.identifier != local.identifier, let moment = instant(jour: jour, heure: heure, zone: zone) else { return (heure, 0) }
        let ecart = TimeInterval(local.secondsFromGMT(for: moment) - zone.secondsFromGMT(for: moment))
        let converti = heure.addingTimeInterval(ecart)
        let cal = Calendar.current
        let jours = cal.dateComponents([.day], from: cal.startOfDay(for: heure), to: cal.startOfDay(for: converti)).day ?? 0
        return (converti, jours)
    }

    /// L'heure saisie (« 10:00 ») un jour donné, lue dans le fuseau indiqué : le moment réel correspondant.
    static func instant(jour: Date, heure: Date, zone: TimeZone) -> Date? {
        let cal = Calendar.current
        let j = cal.dateComponents([.year, .month, .day], from: jour)
        let h = cal.dateComponents([.hour, .minute], from: heure)
        var c = DateComponents()
        c.year = j.year; c.month = j.month; c.day = j.day; c.hour = h.hour; c.minute = h.minute
        var calZone = Calendar(identifier: .gregorian)
        calZone.timeZone = zone
        return calZone.date(from: c)
    }

    /// La durée réelle d'un transport dont les deux heures sont dans des fuseaux différents.
    /// Une arrivée qui tombe avant le départ est comprise comme le lendemain (vol de nuit). Nil si les heures manquent ou sont incohérentes.
    static func duree(_ t: Transport, jour: Date, depart zd: TimeZone, arrivee za: TimeZone) -> TimeInterval? {
        guard let d = t.depart, let a = t.arrivee, let debut = instant(jour: jour, heure: d, zone: zd), var fin = instant(jour: jour, heure: a, zone: za) else { return nil }
        if zd.secondsFromGMT(for: debut) != za.secondsFromGMT(for: fin) {
            var n = 0
            while fin <= debut && n < 3 { fin = fin.addingTimeInterval(86_400); n += 1 }
        }
        let duree = fin.timeIntervalSince(debut)
        return duree > 0 && duree < 40 * 3600 ? duree : nil
    }

    /// Les minutes écoulées depuis minuit, maintenant, dans ce fuseau ; nil si ce n'est pas encore (ou plus) ce jour-là dans ce fuseau.
    static func minutesMaintenant(le jour: Date, zone: TimeZone) -> Double? {
        let cal = Calendar.current
        var calZone = Calendar(identifier: .gregorian)
        calZone.timeZone = zone
        let j = cal.dateComponents([.year, .month, .day], from: jour)
        let n = calZone.dateComponents([.year, .month, .day, .hour, .minute], from: .now)
        guard j.year == n.year, j.month == n.month, j.day == n.day else { return nil }
        return Double((n.hour ?? 0) * 60 + (n.minute ?? 0))
    }
}

// MARK: - Choix du fuseau

/// Une ligne « Fuseau horaire » : le fuseau en vigueur, et un choix parmi tous les fuseaux (ou le retour à celui du lieu).
struct LigneFuseau: View {
    var titre = "Fuseau horaire"
    @Binding var choisi: String?
    var parDefaut: TimeZone
    var coordonnees: [CLLocationCoordinate2D] = []
    var suggestions: [TimeZone] = []
    @State private var ouvert = false

    private var effectif: TimeZone { choisi.flatMap(TimeZone.init(identifier:)) ?? parDefaut }

    var body: some View {
        Button { ouvert = true } label: {
            LabeledContent(titre) {
                HStack(spacing: 6) {
                    Text(effectif.libelle).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    if choisi == nil { Text("du lieu").font(.caption2.weight(.semibold)).foregroundStyle(.tint) }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: coordonnees.map { FuseauxHoraires.cle($0) }) {
            for c in coordonnees { await FuseauxHoraires.shared.charger(c) }
        }
        .sheet(isPresented: $ouvert) { ChoixFuseauView(choisi: $choisi, parDefaut: parDefaut, suggestions: suggestions) }
    }
}

struct ChoixFuseauView: View {
    @Binding var choisi: String?
    var parDefaut: TimeZone
    var suggestions: [TimeZone]
    @Environment(\.dismiss) private var dismiss
    @State private var recherche = ""

    private var tous: [TimeZone] {
        let filtre = recherche.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return TimeZone.knownTimeZoneIdentifiers.compactMap(TimeZone.init(identifier:))
            .filter { filtre.isEmpty || $0.identifier.replacingOccurrences(of: "_", with: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(filtre) }
            .sorted { $0.secondsFromGMT() != $1.secondsFromGMT() ? $0.secondsFromGMT() < $1.secondsFromGMT() : $0.ville < $1.ville }
    }

    var body: some View {
        NavigationStack {
            List {
                if recherche.isEmpty {
                    Section {
                        ligne(nil, "Fuseau du lieu", parDefaut)
                    } footer: {
                        Text("L'heure saisie est l'heure locale à cet endroit. Choisis un autre fuseau si tu notes l'heure d'un autre pays (par exemple l'heure de Paris pour un départ).")
                    }
                    let uniques = Dictionary(grouping: suggestions + [.current], by: \.identifier).values.compactMap(\.first)
                    if !uniques.isEmpty {
                        Section("Fuseaux du voyage") {
                            ForEach(uniques.sorted { $0.ville < $1.ville }, id: \.identifier) { ligne($0.identifier, $0.ville, $0) }
                        }
                    }
                }
                Section(recherche.isEmpty ? "Tous les fuseaux" : "Résultats") {
                    ForEach(tous, id: \.identifier) { ligne($0.identifier, $0.libelle, $0, detail: $0.identifier) }
                }
            }
            .searchable(text: $recherche, prompt: "Ville ou pays (Paris, Costa Rica, Tokyo…)")
            .navigationTitle("Fuseau horaire")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func ligne(_ id: String?, _ titre: String, _ zone: TimeZone, detail: String? = nil) -> some View {
        Button {
            choisi = id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(id == nil ? "\(titre) · \(zone.libelle)" : titre).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                if choisi == id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
