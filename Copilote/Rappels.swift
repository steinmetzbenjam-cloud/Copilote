import Foundation
import SwiftData
import UserNotifications

/// Rappels sur l'appareil (notifications locales) : veille et jour du départ, étapes, transports,
/// et dépenses déclarées par les autres voyageurs. Rien ne passe par un serveur.
@MainActor
enum Rappels {
    private static let cle = "rappelsActifs"
    private static let prefixe = "copilote-"

    static var actifs: Bool {
        get { UserDefaults.standard.object(forKey: cle) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: cle) }
    }

    static func autoriser() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func autorise() async -> Bool {
        let statut = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return statut == .authorized || statut == .provisional
    }

    static func nombreProgramme() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefixe) }.count
    }

    private struct Rappel {
        var id: String
        var quand: Date
        var titre: String
        var corps: String
    }

    /// Reprogramme tous les rappels à venir : les plus proches d'abord (le système en garde 64 au plus).
    static func planifier(_ voyages: [Voyage]) async {
        let centre = UNUserNotificationCenter.current()
        let anciens = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefixe) }
        centre.removePendingNotificationRequests(withIdentifiers: anciens)
        guard actifs, await autorise() else { return }

        let cal = Calendar.current
        let maintenant = Date.now
        var rappels: [Rappel] = []

        for voyage in voyages {
            let nom = voyage.titre.isEmpty ? "ton voyage" : voyage.titre
            let debut = cal.startOfDay(for: voyage.debut)
            if let veille = cal.date(byAdding: .day, value: -1, to: debut).flatMap({ cal.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }) {
                rappels.append(Rappel(id: "\(voyage.uid)-veille", quand: veille, titre: "Demain, c'est le départ !",
                                      corps: "\(nom) · passeports, billets, bagages : tout est prêt ?"))
            }
            if let matin = cal.date(bySettingHour: 7, minute: 30, second: 0, of: debut) {
                rappels.append(Rappel(id: "\(voyage.uid)-depart", quand: matin, titre: "C'est aujourd'hui !", corps: "Départ pour \(nom). Bon voyage !"))
            }

            for etape in voyage.etapes {
                guard let jour = etape.jour else { continue }
                let titre = etape.titre.isEmpty ? etape.categorie.libelle : etape.titre
                if !etape.apresJour, let heure = etape.dateHeure {
                    rappels.append(Rappel(id: "\(voyage.uid)-e-\(etape.uid)", quand: heure.addingTimeInterval(-30 * 60),
                                          titre: "Dans 30 minutes", corps: etape.lieu.isEmpty ? titre : "\(titre) · \(etape.lieu)"))
                }
                let jourTransport = etape.apresJour ? (cal.date(byAdding: .day, value: 1, to: jour) ?? jour) : jour
                if let t = etape.transport {
                    let zone = voyage.fuseaux(de: t, depuis: etape, vers: voyage.suivante(de: etape)).depart
                    ajouter(t, jour: jourTransport, zone: zone, id: "\(voyage.uid)-t-\(etape.uid)", nom: titre, a: &rappels)
                }
            }
            if let t = voyage.transportAller, let j = voyage.jours.first {
                ajouter(t, jour: j, zone: voyage.fuseaux(de: t, depuis: nil, vers: voyage.elementsDuVoyage.first).depart, id: "\(voyage.uid)-aller", nom: "l'aller", a: &rappels)
            }
            if let t = voyage.transportRetour, let j = voyage.jours.last {
                ajouter(t, jour: j, zone: voyage.fuseaux(de: t, depuis: voyage.elementsDuVoyage.last, vers: nil).depart, id: "\(voyage.uid)-retour", nom: "le retour", a: &rappels)
            }
        }

        for r in rappels.filter({ $0.quand > maintenant.addingTimeInterval(5) }).sorted(by: { $0.quand < $1.quand }).prefix(60) {
            let contenu = UNMutableNotificationContent()
            contenu.title = r.titre
            contenu.body = r.corps
            contenu.sound = .default
            // Écrit en UTC avec son fuseau : le système déclenche au bon instant, quel que soit le fuseau de l'appareil.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            var c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: r.quand)
            c.timeZone = utc.timeZone
            let demande = UNNotificationRequest(identifier: prefixe + r.id, content: contenu,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
            try? await centre.add(demande)
        }
    }

    /// L'heure de départ est celle du fuseau du lieu de départ (ou celui choisi) : le rappel tombe au bon moment, où que soit l'appareil.
    private static func ajouter(_ t: Transport, jour: Date, zone: TimeZone, id: String, nom: String, a rappels: inout [Rappel]) {
        guard let depart = t.depart, let quand = Horaires.instant(jour: jour, heure: depart, zone: zone) else { return }
        let avance: TimeInterval = t.mode == .avion ? 3 * 3600 : 45 * 60
        let numero = [t.compagnie, t.numero].filter { !$0.isEmpty }.joined(separator: " ")
        let detail = numero.isEmpty ? "\(t.mode.libelleCourt) · \(nom)" : "\(t.mode.libelleCourt) \(numero) · \(nom)"
        rappels.append(Rappel(id: id, quand: quand.addingTimeInterval(-avance),
                              titre: t.mode == .avion ? "Ton vol part dans 3 h" : "Départ dans 45 minutes", corps: detail))
    }

    /// Une dépense déclarée par quelqu'un d'autre et qui concerne ma famille, reçue par la synchronisation.
    static func notifierNouvelleDepense(_ depense: Depense) {
        guard actifs, let voyage = depense.voyage else { return }
        let moi = MoiVoyage.lire(voyage)
        guard !moi.isEmpty, depense.payeurUID != moi else { return }
        let mienne = voyage.representant(de: moi, moi: moi)
        let concerne = depense.parts.contains { voyage.representant(de: $0.membreUID, moi: moi) == mienne }
        guard concerne, depense.date > Date.now.addingTimeInterval(-30 * 86_400) else { return }
        let payeur = voyage.membre(uid: depense.payeurUID)?.nom ?? "Quelqu'un"
        let titre = depense.titre.isEmpty ? "une dépense" : depense.titre
        let contenu = UNMutableNotificationContent()
        contenu.title = "Nouvelle dépense · \(voyage.titre)"
        contenu.body = "\(payeur) a payé \(titre) : \(depense.montant.formatted(.currency(code: depense.devise)))."
        contenu.sound = .default
        let demande = UNNotificationRequest(identifier: prefixe + "depense-\(depense.uid)", content: contenu,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(demande)
    }
}
