import Foundation
import Security

/// Clés d'API (Google Places, Tripadvisor) gardées dans le trousseau, jamais dans le code ni sur GitHub.
/// Elles passent par le **trousseau iCloud** : saisies sur un appareil, elles apparaissent sur les autres
/// appareils du même compte iCloud, chiffrées de bout en bout. Elles ne sont jamais envoyées aux autres voyageurs.
enum Cles {
    enum Service: String, CaseIterable, Identifiable {
        case google = "fr.steinmetz.Copilote.google-places"
        case tripadvisor = "fr.steinmetz.Copilote.tripadvisor"
        var id: String { rawValue }
        var nom: String { self == .google ? "Google Places" : "Tripadvisor" }
    }

    /// Adresse du site déclaré chez Tripadvisor : à renseigner si la clé y est restreinte à un site (en-tête Referer).
    static var referentTripadvisor: String {
        get { UserDefaults.standard.string(forKey: "referentTripadvisor") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "referentTripadvisor") }
    }

    enum Etat {
        case absente
        /// Recopiée sur les autres appareils par le trousseau iCloud.
        case synchronisee
        /// Gardée sur cet appareil seulement (trousseau iCloud indisponible).
        case locale
    }

    /// `protege` : le trousseau moderne (nécessaire à la synchronisation) ; sinon l'ancien trousseau local,
    /// où les clés étaient rangées avant l'arrivée de la synchronisation.
    private static func requete(_ service: Service, protege: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if protege { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    private static func lireTexte(_ service: Service, protege: Bool) -> String? {
        var q = requete(service, protege: protege)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultat: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data,
              let texte = String(data: donnees, encoding: .utf8), !texte.isEmpty else { return nil }
        return texte
    }

    static func lire(_ service: Service) -> String? {
        if let valeur = lireTexte(service, protege: true) { return valeur }
        // Clé saisie avant la synchronisation : on la reprend et on la range dans le trousseau iCloud.
        if let ancienne = lireTexte(service, protege: false) {
            enregistrer(ancienne, pour: service)
            return ancienne
        }
        return nil
    }

    private static func existeSynchronisee(_ service: Service) -> Bool {
        var q = requete(service, protege: true)
        q[kSecAttrSynchronizable as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func etat(_ service: Service) -> Etat {
        if existeSynchronisee(service) { return .synchronisee }
        guard lire(service) != nil else { return .absente }   // la lecture migre une ancienne clé locale
        return existeSynchronisee(service) ? .synchronisee : .locale
    }

    /// Enregistre la clé dans le trousseau iCloud. Renvoie `true` si elle sera synchronisée, `false` si elle
    /// n'a pu être gardée que sur cet appareil.
    @discardableResult
    static func enregistrer(_ valeur: String, pour service: Service) -> Bool {
        let nettoyee = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(requete(service, protege: true) as CFDictionary)
        SecItemDelete(requete(service, protege: false) as CFDictionary)
        guard !nettoyee.isEmpty else { return true }
        let donnees = Data(nettoyee.utf8)

        let synchronisee: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecValueData as String: donnees,
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemAdd(synchronisee as CFDictionary, nil) == errSecSuccess { return true }

        let locale: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecValueData as String: donnees,
        ]
        SecItemAdd(locale as CFDictionary, nil)
        return false
    }
}
