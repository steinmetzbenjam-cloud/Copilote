# Activer le partage iCloud

**État : activé.** L'option de compilation `ICLOUD`, les autorisations iCloud (CloudKit, notifications) et le
conteneur `iCloud.fr.steinmetz.Copilote` sont déjà réglés dans le projet, avec l'équipe payante `26SUT848P6`.
Xcode crée tout seul les profils de signature (`-allowProvisioningUpdates` ou signature automatique).

Si un jour l'équipe redevient gratuite ou change, retirer `ICLOUD` de
« Active Compilation Conditions » et les clés iCloud des deux fichiers `.entitlements` : l'app se compile
alors sans synchronisation.

## Essayer le partage

1. Lancer l'app (⌘R) sur deux appareils, chacun connecté à **un compte iCloud différent**.
2. Sur chacun : icône clé → **Synchroniser avec iCloud**.
3. Sur le premier : ouvrir un voyage → **Infos → Inviter des voyageurs**, envoyer le lien par Messages.
4. Sur le second : ouvrir le lien. Le voyage apparaît ; les modifications des deux côtés se synchronisent.

Dans la fiche Dépenses, chacun choisit « Qui es-tu ? » sur son appareil.

## Bon à savoir

- CloudKit crée tout seul le schéma en mode développement. Avant de distribuer l'app via TestFlight ou
  l'App Store, il faut le « déployer en production » dans le tableau de bord CloudKit
  (icloud.developer.apple.com → conteneur → Deploy Schema Changes).
- Supprimer un voyage partagé le supprime pour tout le monde ; sur un voyage reçu, l'action devient « Quitter ».
- En cas de modification simultanée du même élément, la dernière modification envoyée l'emporte.
- Les photos et documents sont envoyés dans iCloud (espace du créateur du voyage).
