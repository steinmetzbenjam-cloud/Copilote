import Foundation

/// Le fuseau de référence d'un voyage : tous ses horaires sont lus dans ce fuseau, où que soit l'appareil.
///
/// Les heures saisies sont enregistrées comme un moment lu dans un fuseau. Si l'on lisait ce moment dans le fuseau de l'appareil,
/// changer de fuseau (en arrivant à destination) décalerait tous les horaires. On fixe donc le fuseau de lecture de toute l'app
/// sur celui du voyage ouvert (variable `TZ` du processus) : l'affichage, les sélecteurs d'heure et les calculs s'y réfèrent.
@MainActor
enum Horloge {
    private static var appliquee: String?
    private static var observateur: NSObjectProtocol?

    /// Le vrai fuseau de l'appareil en ce moment (indépendamment du fuseau de référence appliqué).
    static func zoneAppareil() -> TimeZone {
        let precedent = getenv("TZ").map { String(cString: $0) }
        unsetenv("TZ")
        tzset()
        NSTimeZone.resetSystemTimeZone()
        let reel = TimeZone.current
        if let precedent {
            setenv("TZ", precedent, 1)
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
        return reel
    }

    /// Lit désormais toutes les dates dans ce fuseau.
    static func appliquer(_ identifiant: String) {
        guard TimeZone(identifier: identifiant) != nil else { return }
        setenv("TZ", identifiant, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        appliquee = identifiant
    }

    /// À l'ouverture d'un voyage : on applique son fuseau de référence. Un voyage qui n'en a pas encore reçoit celui de l'appareil
    /// (c'est dans ce fuseau que ses horaires ont été saisis) ; un voyage reçu d'un autre n'est pas modifié.
    static func ouvrir(_ voyage: Voyage) {
        if voyage.fuseauReferenceId == nil, !voyage.estRecu { voyage.fuseauReferenceId = zoneAppareil().identifier }
        appliquer(voyage.fuseauReferenceId ?? zoneAppareil().identifier)
    }

    /// Quand le système change de fuseau (voyage), on garde celui du voyage.
    static func demarrer() {
        guard observateur == nil else { return }
        observateur = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if let id = appliquee { appliquer(id) } }
        }
    }
}
