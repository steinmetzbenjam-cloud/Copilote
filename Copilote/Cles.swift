import Foundation
import Security

/// Clés d'API (Google Places, Tripadvisor) gardées dans le trousseau de l'appareil, jamais dans le code ni sur GitHub.
enum Cles {
    enum Service: String, CaseIterable, Identifiable {
        case google = "fr.steinmetz.Copilote.google-places"
        case tripadvisor = "fr.steinmetz.Copilote.tripadvisor"
        var id: String { rawValue }
        var nom: String { self == .google ? "Google Places" : "Tripadvisor" }
    }

    static func lire(_ service: Service) -> String? {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: AnyObject?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data,
              let texte = String(data: donnees, encoding: .utf8), !texte.isEmpty else { return nil }
        return texte
    }

    static func enregistrer(_ valeur: String, pour service: Service) {
        let nettoyee = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard !nettoyee.isEmpty else { return }
        var ajout = base
        ajout[kSecValueData as String] = Data(nettoyee.utf8)
        SecItemAdd(ajout as CFDictionary, nil)
    }
}
