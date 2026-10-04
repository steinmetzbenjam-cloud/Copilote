# Activer le partage iCloud

Le partage entre voyageurs passe par iCloud (CloudKit). Tout le code est déjà dans l'app, mais il est
désactivé tant que l'option de compilation `ICLOUD` n'est pas posée : une équipe Xcode gratuite
(« Personal Team ») ne peut pas utiliser iCloud, et l'app ne se compilerait plus sur l'appareil.

## 1. S'inscrire

S'inscrire à l'**Apple Developer Program** (99 €/an) sur developer.apple.com/programs avec l'Apple ID
utilisé dans Xcode. La validation prend de quelques heures à quelques jours.

## 2. Régler Xcode

1. Xcode → Réglages → Comptes : l'équipe payante doit apparaître (sinon se reconnecter).
2. Ouvrir `Copilote.xcodeproj`, cible **Copilote**, onglet **Signing & Capabilities** :
   - **Team** : choisir l'équipe payante (pour iOS et macOS).
   - Si Xcode propose de changer l'identifiant de l'app (`fr.steinmetz.Copilote`), accepter ou en choisir un autre ;
     le conteneur iCloud ci-dessous doit alors porter le même nom (`iCloud.` + identifiant).
3. **+ Capability → iCloud**, cocher **CloudKit**, puis ajouter le conteneur `iCloud.fr.steinmetz.Copilote`.
4. **+ Capability → Push Notifications** (les modifications des autres arrivent par notification silencieuse).
5. **+ Capability → Background Modes**, cocher **Remote notifications** (iOS).

Faire la même chose pour la plateforme macOS (les capacités se règlent par plateforme dans l'onglet).

## 3. Poser l'option de compilation

Cible Copilote → **Build Settings** → rechercher « Active Compilation Conditions » et ajouter `ICLOUD`
(en Debug et en Release).

## 4. Essayer

1. Lancer l'app sur deux appareils, chacun connecté à **un compte iCloud différent**.
2. Sur chacun : icône clé → **Synchroniser avec iCloud**.
3. Sur le premier : ouvrir un voyage → **Infos → Inviter des voyageurs**, envoyer le lien par Messages.
4. Sur le second : ouvrir le lien. Le voyage apparaît, et les modifications des deux côtés se synchronisent.

## Bon à savoir

- CloudKit crée tout seul le schéma en mode développement. Avant de distribuer l'app via TestFlight ou
  l'App Store, il faut le « déployer en production » dans le tableau de bord CloudKit
  (icloud.developer.apple.com → conteneur → Deploy Schema Changes).
- Supprimer un voyage partagé le supprime pour tout le monde ; sur un voyage reçu, l'action devient « Quitter ».
- En cas de modification simultanée du même élément, la dernière modification envoyée l'emporte.
- Les photos et documents sont envoyés dans iCloud (espace du créateur du voyage).
